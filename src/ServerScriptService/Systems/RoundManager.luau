local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)
local CombatSystem = require(script.Parent.CombatSystem)
local AbilitySystem = require(script.Parent.AbilitySystem)
local MapManager = require(script.Parent.MapManager)
local BotSystem = require(script.Parent.BotSystem)

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

-- Read the grip CFrame and motor name from the third-person rig's Right-Arm motor.
-- This lets the user author the grip in Studio (via the rig's pre-rigged weapon)
-- and have it pick up automatically. Falls back to identity + "Weapon" if missing.
local function extractTPGrip(weaponName: string): (CFrame, string)
	local rigsFolder = ReplicatedStorage:FindFirstChild("ThirdPersonRigs")
	if not rigsFolder then return CFrame.new(), "Weapon" end
	local rig = rigsFolder:FindFirstChild(weaponName)
	if not rig or not rig:IsA("Model") then return CFrame.new(), "Weapon" end
	local rightArm = rig:FindFirstChild("Right Arm")
	if not rightArm then return CFrame.new(), "Weapon" end
	for _, m in ipairs(rig:GetDescendants()) do
		if m:IsA("Motor6D") and m.Part0 == rightArm and m.Part1 then
			return m.C0, m.Name
		end
	end
	return CFrame.new(), "Weapon"
end

-- Attach / detach the third-person weapon model on the player's character.
-- Server-side so the welded weapon replicates to every observer. The animation
-- system targets the Motor6D by name (extracted from ThirdPersonRigs.<Name>),
-- so the weapon follows the player's right arm via the TP fire/idle animations.
local function applyTPWeapon(player: Player, on: boolean)
	local char = player.Character
	if not char then return end

	local existing = char:FindFirstChild("EquippedWeapon")
	if existing then existing:Destroy() end
	local rightArm = char:FindFirstChild("Right Arm")
	if rightArm then
		for _, c in ipairs(rightArm:GetChildren()) do
			if c:IsA("Motor6D") and c.Part1 == nil then
				c:Destroy()
			end
		end
	end

	if not on then return end
	if not rightArm then return end

	local weaponName = Constants.VIEWMODEL_DEFAULT_WEAPON
	local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
	if not weaponsFolder then return end
	local template = weaponsFolder:FindFirstChild(weaponName)
	if not template or not template:IsA("Model") then return end

	local clone = template:Clone()
	clone.Name = "EquippedWeapon"
	local primary: BasePart? = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	if not primary then
		clone:Destroy()
		return
	end
	clone.PrimaryPart = primary

	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end

	local grip, motorName = extractTPGrip(weaponName)

	local motor = Instance.new("Motor6D")
	motor.Name = motorName
	motor.Part0 = rightArm
	motor.Part1 = primary
	motor.C0 = grip
	motor.Parent = rightArm

	clone.Parent = char
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

local function survivorNames(): { string }
	local names: { string } = {}
	for _, p in PlayerState.getAllInState(Constants.STATE_SAFE) do
		table.insert(names, p.Name)
	end
	return names
end

local function endRound(reason: string, winners: { string })
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

	if #participants < minPlayers then
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

	if PlayerState.countInState(Constants.STATE_SAFE) < minPlayers then
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

		if #Players:GetPlayers() < minPlayers then
			endRound(Constants.REASON_ABORTED, {})
			return
		end

		if Constants.TEST_MODE then
			if endWallTouched or PlayerState.countInState(Constants.STATE_SAFE) < 1 then
				endRound(Constants.REASON_SURVIVED, survivorNames())
				return
			end
		elseif PlayerState.countInState(Constants.STATE_SAFE) <= 1 then
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

		while PlayerState.countInState(Constants.STATE_LOBBY) < minPlayers do
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

		if PlayerState.countInState(Constants.STATE_LOBBY) < minPlayers then
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
	end

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
