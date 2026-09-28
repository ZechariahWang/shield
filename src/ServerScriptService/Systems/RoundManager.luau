local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local PlayerState = require(script.Parent.PlayerState)
local CombatSystem = require(script.Parent.CombatSystem)
local AbilitySystem = require(script.Parent.AbilitySystem)
local MapManager = require(script.Parent.MapManager)
local BotSystem = require(script.Parent.BotSystem)
local RagdollSystem = require(script.Parent.RagdollSystem)
local Store = require(script.Parent.Store)
local WeaponModel = require(script.Parent.WeaponModel)

local RoundManager = {}

local minPlayers = if Constants.TEST_MODE then 1 else Constants.MIN_PLAYERS

local currentPhase = Constants.PHASE_LOBBY
local currentPhaseEndClock = 0
local currentPhaseExtra: any = nil
local RoundStateRemote: RemoteEvent
local KillFeedRemote: RemoteEvent

local function broadcastPhase(phase: string, duration: number?, extra: any?)
	currentPhase = phase
	currentPhaseEndClock = if duration then os.clock() + duration else 0
	currentPhaseExtra = extra
	RoundStateRemote:FireAllClients(phase, duration, extra)
end

local function syncPhaseTo(player: Player)
	if not RoundStateRemote then return end
	local remaining: number? = nil
	if currentPhaseEndClock > 0 then
		remaining = math.max(0, currentPhaseEndClock - os.clock())
	end
	RoundStateRemote:FireClient(player, currentPhase, remaining, currentPhaseExtra)
end

local function setWalkSpeed(player: Player, speed: number)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = speed end
end

-- The third-person weapon follows the equipped choice; WeaponModel does the welding.
local function applyTPWeapon(player: Player, on: boolean)
	local char = player.Character
	if not char then return end
	if not on then
		WeaponModel.detach(char)
		return
	end
	local weaponName = Store.equipped(player, Catalog.KIND_WEAPONS) or Constants.VIEWMODEL_DEFAULT_WEAPON
	WeaponModel.attach(char, weaponName)
end

local function setSafe(player: Player)
	PlayerState.set(player, Constants.STATE_SAFE)
	setWalkSpeed(player, Constants.SAFE_WALKSPEED)
	applyTPWeapon(player, true)
end

local function setLobby(player: Player)
	PlayerState.set(player, Constants.STATE_LOBBY)
	setWalkSpeed(player, Constants.SAFE_WALKSPEED)
	applyTPWeapon(player, false)
end

local function healAllPlayers()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = hum.MaxHealth
		end
	end
end

-- Everyone still standing: Safe players and alive bots (bots count as players).
local function survivorNames(): { string }
	local names: { string } = {}
	for _, p in PlayerState.getAllInState(Constants.STATE_SAFE) do
		table.insert(names, p.Name)
	end
	for _, name in BotSystem.aliveNames() do
		table.insert(names, name)
	end
	return names
end

local function aliveCount(): number
	return PlayerState.countInState(Constants.STATE_SAFE) + #BotSystem.aliveNames()
end

local function endRound(reason: string, winners: { string })
	for _, name in winners do
		local winner = Players:FindFirstChild(name)
		if winner and winner:IsA("Player") then
			Store.addCoins(winner, Constants.SHOP_COINS_PER_WIN)
		end
	end

	-- Stop combat first: it strips every PlayerShield, so the freeze ForceField
	-- added below is the only one left on a character.
	CombatSystem.stop()
	AbilitySystem.stop()
	BotSystem.stop()

	for _, player in Players:GetPlayers() do
		applyTPWeapon(player, false)
	end

	-- Belt-and-suspenders invincibility for the freeze window in case any
	-- in-flight shot lands after the systems stopped.
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and not char:FindFirstChild("RoundEndForceField") then
			local ff = Instance.new("ForceField")
			ff.Name = "RoundEndForceField"
			ff.Visible = false
			ff.Parent = char
		end
	end

	-- Broadcast END now (with the full freeze + lobby duration) so clients
	-- transition out of round-mode visuals while players remain in the arena.
	broadcastPhase(Constants.PHASE_END, Constants.END_DELAY_TIME + Constants.END_TIME, {
		winners = winners,
		reason = reason,
	})

	task.wait(Constants.END_DELAY_TIME)

	healAllPlayers()

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local ff = char:FindFirstChild("RoundEndForceField")
			if ff then ff:Destroy() end
		end
		setLobby(player)
		MapManager.teleportToLobby(player)
	end

	BotSystem.despawn()
	RagdollSystem.clear()
	MapManager.unloadMap()

	task.wait(Constants.END_TIME)
end

-- Test mode: the round ends when a Safe player's character touches the end wall.
-- Connections die with the map, so nothing to clean up.
local function bindTestEndWall(onTouched: () -> ())
	local map = Workspace:FindFirstChild("LoadedMap")
	if not map then return end
	for _, part in map:GetDescendants() do
		if not part:IsA("BasePart") or part.Name ~= Constants.TEST_END_WALL then continue end
		part.Touched:Connect(function(hit)
			local char = hit:FindFirstAncestorOfClass("Model")
			if not char then return end
			local player = Players:GetPlayerFromCharacter(char)
			if player and PlayerState.get(player) == Constants.STATE_SAFE then
				onTouched()
			end
		end)
	end
end

local function runRound()
	local participants: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			setSafe(player)
			MapManager.teleportToArena(player)
			table.insert(participants, player)
		end
	end

	if #participants + BotSystem.plannedCount() < minPlayers then
		for _, player in participants do
			setLobby(player)
			MapManager.teleportToLobby(player)
		end
		MapManager.unloadMap()
		broadcastPhase(Constants.PHASE_LOBBY)
		return
	end

	BotSystem.spawn()

	-- Reveal phase: positioning countdown. Shooting, shields and dash stay off.
	broadcastPhase(Constants.PHASE_REVEAL, Constants.REVEAL_TIME, nil)
	task.wait(Constants.REVEAL_TIME)

	if aliveCount() < minPlayers then
		endRound(Constants.REASON_ABORTED, {})
		return
	end

	CombatSystem.start()
	AbilitySystem.start()
	BotSystem.start()

	local roundEnd = os.clock() + Constants.ROUND_TIME
	broadcastPhase(Constants.PHASE_ROUND, Constants.ROUND_TIME, nil)

	local endWallTouched = false
	if Constants.TEST_MODE then
		bindTestEndWall(function()
			endWallTouched = true
		end)
	end

	while Constants.TEST_MODE or os.clock() < roundEnd do
		task.wait(0.25)

		if #Players:GetPlayers() + BotSystem.plannedCount() < minPlayers then
			endRound(Constants.REASON_ABORTED, {})
			return
		end

		if Constants.TEST_MODE then
			if endWallTouched or PlayerState.countInState(Constants.STATE_SAFE) < 1 then
				endRound(Constants.REASON_SURVIVED, survivorNames())
				return
			end
		elseif aliveCount() <= 1 then
			endRound(Constants.REASON_LAST_STANDING, survivorNames())
			return
		end
	end

	-- Time up: every remaining player is a winner.
	endRound(Constants.REASON_SURVIVED, survivorNames())
end

local function gameLoop()
	while true do
		broadcastPhase(Constants.PHASE_LOBBY)

		while PlayerState.countInState(Constants.STATE_LOBBY) + BotSystem.plannedCount() < minPlayers do
			task.wait(1)
		end

		local mapLoaded = MapManager.loadRandomMap()
		if not mapLoaded then
			warn("RoundManager: yo add the maps back to server storage")
			task.wait(5)
			continue
		end

		broadcastPhase(Constants.PHASE_INTERMISSION, Constants.INTERMISSION_TIME)
		task.wait(Constants.INTERMISSION_TIME)

		if PlayerState.countInState(Constants.STATE_LOBBY) + BotSystem.plannedCount() < minPlayers then
			MapManager.unloadMap()
			continue
		end

		runRound()
	end
end

local function combatantName(char: Model): string
	local player = Players:GetPlayerFromCharacter(char)
	if player then return player.Name end
	return char.Name
end

local function onPlayerEliminated(victim: Model, killer: Model?)
	if currentPhase ~= Constants.PHASE_ROUND then return end

	local killerName: string? = if killer then combatantName(killer) else nil
	KillFeedRemote:FireAllClients(killerName, combatantName(victim))

	local killerPlayer = if killer then Players:GetPlayerFromCharacter(killer) else nil
	if killerPlayer then
		Store.addCoins(killerPlayer, Constants.SHOP_COINS_PER_KILL)
	end

	-- Before the teleport so the corpse lands where they died.
	RagdollSystem.spawn(victim, killer)

	local victimPlayer = Players:GetPlayerFromCharacter(victim)
	if victimPlayer then
		setLobby(victimPlayer)
		MapManager.teleportToLobby(victimPlayer)
	elseif BotSystem.isBot(victim) then
		BotSystem.remove(victim)
	end
end

local function onCharacterAdded(player: Player, char: Model)
	char:WaitForChild("HumanoidRootPart", 5)

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.BreakJointsOnDeath = false
		-- Every death reloads the character at once instead of leaving the body lying
		-- stiff until the respawn timer. Dying while Safe in the arena also sends the
		-- player back to the lobby: a Round death is an elimination with no killer
		-- (kill feed, ragdoll), a Reveal death is just the trip back.
		hum.Died:Connect(function()
			if PlayerState.get(player) == Constants.STATE_SAFE then
				if currentPhase == Constants.PHASE_ROUND then
					onPlayerEliminated(char, nil)
				elseif currentPhase == Constants.PHASE_REVEAL then
					setLobby(player)
				end
			end
			task.defer(function()
				if player.Parent and player.Character == char then
					player:LoadCharacter()
				end
			end)
		end)
	end
	CombatSystem.prepareHitbox(char)

	syncPhaseTo(player)
	PlayerState.syncTo(player)

	local state = PlayerState.get(player)
	local inRoundPhase = currentPhase == Constants.PHASE_ROUND or currentPhase == Constants.PHASE_REVEAL
	local inActiveRound = inRoundPhase
		and state == Constants.STATE_SAFE
		and MapManager.hasMap()

	if inActiveRound then
		setSafe(player)
		MapManager.teleportToArena(player)
	else
		setLobby(player)
		MapManager.teleportToLobby(player)
	end
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function RoundManager.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	local existingKillFeed = Remotes:FindFirstChild("KillFeed")
	if existingKillFeed and existingKillFeed:IsA("RemoteEvent") then
		KillFeedRemote = existingKillFeed
	else
		KillFeedRemote = Instance.new("RemoteEvent")
		KillFeedRemote.Name = "KillFeed"
		KillFeedRemote.Parent = Remotes
	end

	CombatSystem.PlayerEliminated:Connect(onPlayerEliminated)

	Players.PlayerAdded:Connect(bindPlayer)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end

	task.spawn(gameLoop)
end

return RoundManager
