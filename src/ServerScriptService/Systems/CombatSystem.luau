local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)

local CombatSystem = {}

type ShieldState = {
	up: boolean,
	expiresAt: number,
	cooldownUntil: number,
	breaksInChain: number,
	lastBreakAt: number,
	lastShotAt: number,
}

local active = false
local shields: { [Player]: ShieldState } = {}
-- PlayerState only catches up at the end of the resumption cycle, so track eliminations here too.
local eliminatedPlayers: { [Player]: boolean } = {}
local heartbeatConn: RBXScriptConnection? = nil

local eliminated = Instance.new("BindableEvent")
CombatSystem.PlayerEliminated = eliminated.Event

local ShootRequestRemote: RemoteEvent
local ShieldRequestRemote: RemoteEvent
local ShieldChangedRemote: RemoteEvent
local ShotBlockedRemote: RemoteEvent
local DamageDealtRemote: RemoteEvent
local DamageTakenRemote: RemoteEvent

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

local function newShieldState(): ShieldState
	return {
		up = false,
		expiresAt = 0,
		cooldownUntil = 0,
		breaksInChain = 0,
		lastBreakAt = -math.huge,
		lastShotAt = -math.huge,
	}
end

local function getState(player: Player): ShieldState
	local s = shields[player]
	if not s then
		s = newShieldState()
		shields[player] = s
	end
	return s
end

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function setWalkSpeed(player: Player, speed: number)
	local hum = getHumanoid(player)
	if hum then
		hum.WalkSpeed = speed
	end
end

local function sendShieldStatus(player: Player, status: string, duration: number, breaks: number)
	if not ShieldChangedRemote then return end
	ShieldChangedRemote:FireClient(player, status, duration, breaks)
end

local function removeShieldPart(player: Player) -- ere
	local char = player.Character
	if not char then return end
	local ff = char:FindFirstChild("PlayerShield")
	if ff then
		ff:Destroy()
	end
end

local function shieldDurationFor(breaks: number): number
	local index = math.clamp(breaks + 1, 1, #Constants.SHIELD_DURATIONS)
	return Constants.SHIELD_DURATIONS[index]
end

local function raiseShield(player: Player)
	if not active then return end
	if PlayerState.get(player) ~= Constants.STATE_SAFE then return end

	local s = getState(player)
	if s.up then return end

	local now = os.clock()
	if now < s.cooldownUntil then return end

	local hum = getHumanoid(player)
	local char = player.Character
	if not hum or not char or hum.Health <= 0 then return end

	if now - s.lastBreakAt > Constants.SHIELD_CHAIN_RESET then
		s.breaksInChain = 0
	end

	local duration = shieldDurationFor(s.breaksInChain)

	removeShieldPart(player)
	local ff = Instance.new("ForceField")
	ff.Name = "PlayerShield"
	ff.Visible = true
	ff.Parent = char

	hum.WalkSpeed = Constants.SHIELD_WALKSPEED

	s.up = true
	s.expiresAt = now + duration
	s.cooldownUntil = 0

	sendShieldStatus(player, Constants.SHIELD_UP, duration, s.breaksInChain)
end

-- withCooldown is false only for a break: a broken shield can be raised again at once.
local function lowerShield(player: Player, withCooldown: boolean)
	local s = getState(player)
	if not s.up then return end

	removeShieldPart(player)
	setWalkSpeed(player, Constants.SAFE_WALKSPEED)
	s.up = false
	s.expiresAt = 0

	if withCooldown then
		s.cooldownUntil = os.clock() + Constants.SHIELD_COOLDOWN
		sendShieldStatus(player, Constants.SHIELD_COOLDOWN_STATUS, Constants.SHIELD_COOLDOWN, s.breaksInChain)
	else
		s.cooldownUntil = 0
		sendShieldStatus(player, Constants.SHIELD_READY, 0, s.breaksInChain)
	end
end

local function breakShield(victim: Player, shooter: Player)
	local s = getState(victim)

	removeShieldPart(victim)
	setWalkSpeed(victim, Constants.SAFE_WALKSPEED)
	s.up = false
	s.expiresAt = 0
	s.cooldownUntil = 0
	s.breaksInChain += 1
	s.lastBreakAt = os.clock()

	sendShieldStatus(victim, Constants.SHIELD_READY, 0, s.breaksInChain)
	playSoundAt(getHead(victim), Constants.SHIELD_BLOCK_SOUND)

	if ShotBlockedRemote then
		ShotBlockedRemote:FireClient(shooter, victim)
		ShotBlockedRemote:FireClient(victim, shooter)
	end
end

local function clearShieldSilently(player: Player)
	removeShieldPart(player)
	shields[player] = newShieldState()
end

local function playSoundAt(part: BasePart?, soundId: string)
	if not part or soundId == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Parent = part
	sound:Play()
	Debris:AddItem(sound, Constants.SOUND_CLEANUP_TIME)
end

local function getHead(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("Head") :: BasePart?
end

local function spawnTracer(origin: Vector3, endPoint: Vector3)
	local delta = endPoint - origin
	local length = delta.Magnitude
	if length < 0.01 then return end

	local tracer = Instance.new("Part")
	tracer.Name = "PistolTracer"
	tracer.Size = Vector3.new(0.1, 0.1, length)
	tracer.CFrame = CFrame.lookAt(origin + delta * 0.5, endPoint)
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 240, 160)
	tracer.Parent = Workspace

	Debris:AddItem(tracer, Constants.PISTOL_TRACER_LIFETIME)
end

local function isFiniteVector(v: Vector3): boolean
	local components = { v.X, v.Y, v.Z }
	for _, n in components do
		if n ~= n then return false end
		if n == math.huge or n == -math.huge then return false end
	end
	return true
end

local function playerFromHit(instance: Instance?): Player?
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local found = Players:GetPlayerFromCharacter(current)
			if found then return found end
		end
		current = current.Parent
	end
	return nil
end

local function eliminate(victim: Player, killer: Player?)
	local hum = getHumanoid(victim)
	if hum then
		hum.Health = hum.MaxHealth
	end
	clearShieldSilently(victim)
	setWalkSpeed(victim, Constants.SAFE_WALKSPEED)
	eliminatedPlayers[victim] = true
	eliminated:Fire(victim, killer)
end

local function shoot(shooter: Player, origin: any, direction: any)
	if not active then return end
	if PlayerState.get(shooter) ~= Constants.STATE_SAFE then return end
	if eliminatedPlayers[shooter] then return end

	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if not isFiniteVector(origin) or not isFiniteVector(direction) then return end
	if direction.Magnitude < 0.001 then return end

	local s = getState(shooter)
	if s.up then return end

	local now = os.clock()
	if now - s.lastShotAt < Constants.PISTOL_COOLDOWN - Constants.PISTOL_COOLDOWN_TOLERANCE then return end

	local char = shooter.Character
	if not char then return end
	local head = char:FindFirstChild("Head") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not head or not hum or hum.Health <= 0 then return end
	if (origin - head.Position).Magnitude > Constants.PISTOL_ORIGIN_TOLERANCE then return end

	s.lastShotAt = now

	local aim = direction.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local result = Workspace:Raycast(origin, aim * Constants.PISTOL_RANGE, params)
	local endPoint = if result then result.Position else origin + aim * Constants.PISTOL_RANGE
	spawnTracer(origin, endPoint)
	playSoundAt(head, Constants.PISTOL_SHOT_SOUND)

	if not result then return end

	local victim = playerFromHit(result.Instance)
	if not victim or victim == shooter then return end
	if PlayerState.get(victim) ~= Constants.STATE_SAFE then return end
	if eliminatedPlayers[victim] then return end

	local victimHum = getHumanoid(victim)
	if not victimHum or victimHum.Health <= 0 then return end

	local victimState = getState(victim)
	if victimState.up then
		breakShield(victim, shooter)
		return
	end

	local newHealth = math.max(0, victimHum.Health - Constants.PISTOL_DAMAGE)

	if DamageDealtRemote then
		DamageDealtRemote:FireClient(shooter, victim, Constants.PISTOL_DAMAGE, newHealth)
	end
	if DamageTakenRemote then
		DamageTakenRemote:FireClient(victim, shooter, Constants.PISTOL_DAMAGE, newHealth)
	end

	if newHealth <= 0 then
		eliminate(victim, shooter)
	else
		victimHum.Health = newHealth
	end
end

local function step()
	local now = os.clock()
	for player, s in shields do
		if not player.Parent then
			shields[player] = nil
			continue
		end

		local hum = getHumanoid(player)
		if s.up and not hum then
			-- Character gone mid-shield: drop the state without telling the client.
			shields[player] = newShieldState()
			continue
		end

		if s.up and now >= s.expiresAt then
			lowerShield(player, true)
		elseif not s.up and s.cooldownUntil > 0 and now >= s.cooldownUntil then
			s.cooldownUntil = 0
			sendShieldStatus(player, Constants.SHIELD_READY, 0, s.breaksInChain)
		end
	end
end

function CombatSystem.start()
	for _, player in Players:GetPlayers() do
		removeShieldPart(player)
		shields[player] = newShieldState()
		sendShieldStatus(player, Constants.SHIELD_READY, 0, 0)
	end
	table.clear(eliminatedPlayers)
	active = true
end

function CombatSystem.stop()
	active = false
	for _, player in Players:GetPlayers() do
		removeShieldPart(player)
		setWalkSpeed(player, Constants.SAFE_WALKSPEED)
		sendShieldStatus(player, Constants.SHIELD_READY, 0, 0)
	end
	table.clear(shields)
	table.clear(eliminatedPlayers)
end

function CombatSystem.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")

	ShootRequestRemote = ensureRemote(Remotes, "ShootRequest")
	ShieldRequestRemote = ensureRemote(Remotes, "ShieldRequest")
	ShieldChangedRemote = ensureRemote(Remotes, "ShieldChanged")
	ShotBlockedRemote = ensureRemote(Remotes, "ShotBlocked")
	DamageDealtRemote = ensureRemote(Remotes, "DamageDealt")
	DamageTakenRemote = ensureRemote(Remotes, "DamageTaken")

	ShootRequestRemote.OnServerEvent:Connect(function(player, origin, direction)
		shoot(player, origin, direction)
	end)

	ShieldRequestRemote.OnServerEvent:Connect(function(player, raise)
		if typeof(raise) ~= "boolean" then return end
		if raise then
			raiseShield(player)
		else
			if not active then return end
			lowerShield(player, true)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		shields[player] = nil
		eliminatedPlayers[player] = nil
	end)

	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	heartbeatConn = RunService.Heartbeat:Connect(step)
end

return CombatSystem
