local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local PlayerState = require(script.Parent.PlayerState)
local CombatSystem = require(script.Parent.CombatSystem)
local AbilitySystem = require(script.Parent.AbilitySystem)
local GrappleSystem = require(script.Parent.GrappleSystem)
local MapManager = require(script.Parent.MapManager)
local MatchScore = require(script.Parent.MatchScore)
local BotSystem = require(script.Parent.BotSystem)
local RagdollSystem = require(script.Parent.RagdollSystem)
local Store = require(script.Parent.Store)
local WeaponModel = require(script.Parent.WeaponModel)

-- The match loop: a free-for-all deathmatch. Players wait in the lobby and enter
-- the arena with SpawnRequest; a killed player goes back to the lobby and may
-- spawn again after RESPAWN_DELAY. The first combatant to KILL_TARGET kills
-- wins, or the top scorer when ROUND_TIME runs out.
local RoundManager = {}

local currentPhase = Constants.PHASE_LOBBY
local currentPhaseEndClock = 0
local currentPhaseExtra: any = nil
local lastDeathAt: { [Player]: number } = {}
local RoundStateRemote: RemoteEvent
local KillFeedRemote: RemoteEvent
local SpawnRequestRemote: RemoteEvent

local function ensureRemote(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

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

-- A match needs a real player on the server, and MIN_PLAYERS counting the bots.
local function enoughPlayers(): boolean
	local players = #Players:GetPlayers()
	if players < 1 then return false end
	return players + BotSystem.plannedCount() >= Constants.MIN_PLAYERS
end

-- The top scorer alone; nobody when no kill was scored.
local function winnerNames(): { string }
	local name = MatchScore.leader()
	if name then
		return { name }
	end
	return {}
end

-- From the lobby into the arena. Every rule of the SpawnRequest remote is here.
local function spawnIntoArena(player: Player)
	if currentPhase ~= Constants.PHASE_ROUND then return end
	if PlayerState.get(player) ~= Constants.STATE_LOBBY then return end
	local sinceDeath = os.clock() - (lastDeathAt[player] or -math.huge)
	if sinceDeath < Constants.RESPAWN_DELAY then return end

	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root then return end

	CombatSystem.revive(char)
	setSafe(player)
	MapManager.teleportToArena(player)
	CombatSystem.protect(char)
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
	GrappleSystem.stop()
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

local function runMatch()
	MatchScore.reset()
	table.clear(lastDeathAt)

	CombatSystem.start()
	AbilitySystem.start()
	GrappleSystem.start()
	BotSystem.spawn()
	BotSystem.start()

	local matchEnd = os.clock() + Constants.ROUND_TIME
	broadcastPhase(Constants.PHASE_ROUND, Constants.ROUND_TIME, nil)

	while os.clock() < matchEnd do
		task.wait(0.25)

		if not enoughPlayers() then
			endRound(Constants.REASON_ABORTED, {})
			return
		end

		if MatchScore.targetReached() then
			endRound(Constants.REASON_KILL_TARGET, winnerNames())
			return
		end
	end

	endRound(Constants.REASON_TIME_UP, winnerNames())
end

local function gameLoop()
	while true do
		broadcastPhase(Constants.PHASE_LOBBY)

		while not enoughPlayers() do
			task.wait(1)
		end

		local mapLoaded = MapManager.loadRandomMap()
		if not mapLoaded then
			warn("RoundManager: yo add the maps back to server storage")
			task.wait(5)
			continue
		end

		runMatch()
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

	if killerName then
		MatchScore.addKill(killerName)
	end
	local killerPlayer = if killer then Players:GetPlayerFromCharacter(killer) else nil
	if killerPlayer then
		Store.addCoins(killerPlayer, Constants.SHOP_COINS_PER_KILL)
	end

	-- Before the teleport so the corpse lands where they died.
	RagdollSystem.spawn(victim, killer)

	local victimPlayer = Players:GetPlayerFromCharacter(victim)
	if victimPlayer then
		lastDeathAt[victimPlayer] = os.clock()
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
		-- stiff until the respawn timer. Dying while Safe in the arena (a reset) is an
		-- elimination with no killer: kill feed, ragdoll, back to the lobby.
		hum.Died:Connect(function()
			if PlayerState.get(player) == Constants.STATE_SAFE then
				if currentPhase == Constants.PHASE_ROUND then
					onPlayerEliminated(char, nil)
				else
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

	-- A new character always starts in the lobby; the arena is entered with SpawnRequest.
	setLobby(player)
	MapManager.teleportToLobby(player)
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
	KillFeedRemote = ensureRemote(Remotes, "KillFeed")
	SpawnRequestRemote = ensureRemote(Remotes, "SpawnRequest")

	CombatSystem.PlayerEliminated:Connect(onPlayerEliminated)
	SpawnRequestRemote.OnServerEvent:Connect(spawnIntoArena)

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastDeathAt[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end

	task.spawn(gameLoop)
end

return RoundManager
