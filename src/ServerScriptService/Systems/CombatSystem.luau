local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)

-- Every combatant is a character Model. Players map to their Character at the
-- remote boundary; bots are registered directly. Client-only feedback (remotes)
-- is skipped for combatants without a Player.
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
local shields: { [Model]: ShieldState } = {}
-- PlayerState only catches up at the end of the resumption cycle, so track eliminations here too.
local eliminatedChars: { [Model]: boolean } = {}
local bots: { [Model]: boolean } = {}
local heartbeatConn: RBXScriptConnection? = nil

local eliminated = Instance.new("BindableEvent")
CombatSystem.PlayerEliminated = eliminated.Event

local ShootRequestRemote: RemoteEvent
local ShieldRequestRemote: RemoteEvent
local ShieldChangedRemote: RemoteEvent
local ShotBlockedRemote: RemoteEvent
local DamageDealtRemote: RemoteEvent
local DamageTakenRemote: RemoteEvent
local ShotTracerRemote: RemoteEvent

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

local function getState(char: Model): ShieldState
	local s = shields[char]
	if not s then
		s = newShieldState()
		shields[char] = s
	end
	return s
end

local function playerOf(char: Model): Player?
	return Players:GetPlayerFromCharacter(char)
end

-- What remotes carry to identify a combatant: the Player when there is one, else the bot Model.
local function handleOf(char: Model): Player | Model
	local player = playerOf(char)
	if player then return player end
	return char
end

local function isCombatant(char: Model): boolean
	if bots[char] then return true end
	local player = playerOf(char)
	if not player then return false end
	return PlayerState.get(player) == Constants.STATE_SAFE
end

local function getHumanoid(char: Model): Humanoid?
	return char:FindFirstChildOfClass("Humanoid")
end

local function setWalkSpeed(char: Model, speed: number)
	local hum = getHumanoid(char)
	if hum then
		hum.WalkSpeed = speed
	end
end

local function sendShieldStatus(char: Model, status: string, duration: number, breaks: number)
	if not ShieldChangedRemote then return end
	local player = playerOf(char)
	if not player then return end
	ShieldChangedRemote:FireClient(player, status, duration, breaks)
end

local function getHead(char: Model): BasePart?
	return char:FindFirstChild("Head") :: BasePart?
end

local function playSoundAt(part: BasePart?, soundId: string)
	if not part or soundId == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Parent = part
	sound:Play()
	Debris:AddItem(sound, Constants.SOUND_CLEANUP_TIME)
end

local function getShieldPart(char: Model): BasePart?
	return char:FindFirstChild("PlayerShield") :: BasePart?
end

local function removeShieldPart(char: Model)
	local part = getShieldPart(char)
	if part then
		part:Destroy()
	end
end

-- Server-created, so it replicates on its own. CanQuery stays on so shots hit the bubble itself.
local function createShieldPart(char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local part = Instance.new("Part")
	part.Name = "PlayerShield"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * Constants.SHIELD_SIZE
	part.Material = Enum.Material.ForceField
	part.Color = Constants.SHIELD_COLOR
	part.Transparency = Constants.SHIELD_TRANSPARENCY
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = root.CFrame

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part

	part.Parent = char

	-- Pop in: start small and bright, overshoot to full size while settling to the resting transparency.
	local fullSize = part.Size
	part.Size = fullSize * Constants.SHIELD_RAISE_FX_START
	part.Transparency = 0
	local info = TweenInfo.new(Constants.SHIELD_RAISE_FX_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(part, info, { Size = fullSize, Transparency = Constants.SHIELD_TRANSPARENCY }):Play()
end

-- Detached, anchored copy of the bubble that shrinks and fades: used for lower and expiry.
local function spawnLowerEffect(shieldPart: BasePart)
	local fx = shieldPart:Clone()
	fx:ClearAllChildren()
	fx.Name = "ShieldLowerFx"
	fx.Anchored = true
	fx.CanQuery = false
	fx.Parent = Workspace

	local info = TweenInfo.new(Constants.SHIELD_LOWER_FX_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(fx, info, { Size = fx.Size * Constants.SHIELD_LOWER_FX_SCALE, Transparency = 1 }):Play()
	Debris:AddItem(fx, Constants.SHIELD_LOWER_FX_TIME + 0.1)
end

local function spawnBreakEffect(shieldPart: BasePart)
	local fx = shieldPart:Clone()
	fx:ClearAllChildren()
	fx.Name = "ShieldBreakFx"
	fx.Anchored = true
	fx.CanQuery = false
	fx.Parent = Workspace

	local info = TweenInfo.new(Constants.SHIELD_BREAK_FX_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(fx, info, { Size = fx.Size * Constants.SHIELD_BREAK_FX_SCALE, Transparency = 1 }):Play()
	Debris:AddItem(fx, Constants.SHIELD_BREAK_FX_TIME + 0.1)

	-- Shard burst from the bubble's center.
	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(Constants.SHIELD_COLOR)
	burst.LightEmission = 1
	burst.Size = NumberSequence.new(0.6, 0)
	burst.Transparency = NumberSequence.new(0, 1)
	burst.Lifetime = NumberRange.new(0.3, 0.6)
	burst.Speed = NumberRange.new(18, 30)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 4
	burst.Rate = 0
	burst.Parent = fx
	burst:Emit(Constants.SHIELD_BREAK_PARTICLES)

	-- Flat ring expanding across the ground under the bubble.
	local ring = Instance.new("Part")
	ring.Name = "ShieldBreakRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(shieldPart.Position - Vector3.new(0, Constants.SHIELD_SIZE / 2 - 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Constants.SHIELD_COLOR
	ring.Transparency = 0.2
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = Workspace
	local ringInfo = TweenInfo.new(Constants.SHIELD_BREAK_RING_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, ringInfo, {
		Size = Vector3.new(0.2, Constants.SHIELD_BREAK_RING_SIZE, Constants.SHIELD_BREAK_RING_SIZE),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, Constants.SHIELD_BREAK_RING_TIME + 0.1)
end

local function shieldDurationFor(breaks: number): number
	local index = math.clamp(breaks + 1, 1, #Constants.SHIELD_DURATIONS)
	return Constants.SHIELD_DURATIONS[index]
end

local function raiseShield(char: Model)
	if not active then return end
	if not isCombatant(char) then return end
	if eliminatedChars[char] then return end

	local s = getState(char)
	if s.up then return end

	local now = os.clock()
	if now < s.cooldownUntil then return end

	local hum = getHumanoid(char)
	if not hum or hum.Health <= 0 then return end

	if now - s.lastBreakAt > Constants.SHIELD_CHAIN_RESET then
		s.breaksInChain = 0
	end

	local duration = shieldDurationFor(s.breaksInChain)

	removeShieldPart(char)
	createShieldPart(char)
	playSoundAt(getHead(char), Constants.SHIELD_RAISE_SOUND)

	hum.WalkSpeed = Constants.SHIELD_WALKSPEED

	s.up = true
	s.expiresAt = now + duration
	s.cooldownUntil = 0

	sendShieldStatus(char, Constants.SHIELD_UP, duration, s.breaksInChain)
end

-- withCooldown is false only for a break: a broken shield can be raised again at once.
local function lowerShield(char: Model, withCooldown: boolean)
	local s = getState(char)
	if not s.up then return end

	local part = getShieldPart(char)
	if part then
		spawnLowerEffect(part)
	end
	removeShieldPart(char)
	playSoundAt(getHead(char), Constants.SHIELD_LOWER_SOUND)
	setWalkSpeed(char, Constants.SAFE_WALKSPEED)
	s.up = false
	s.expiresAt = 0

	if withCooldown then
		s.cooldownUntil = os.clock() + Constants.SHIELD_COOLDOWN
		sendShieldStatus(char, Constants.SHIELD_COOLDOWN_STATUS, Constants.SHIELD_COOLDOWN, s.breaksInChain)
	else
		s.cooldownUntil = 0
		sendShieldStatus(char, Constants.SHIELD_READY, 0, s.breaksInChain)
	end
end

local function breakShield(victim: Model, shooter: Model)
	local s = getState(victim)

	local part = getShieldPart(victim)
	if part then
		spawnBreakEffect(part)
	end
	removeShieldPart(victim)
	setWalkSpeed(victim, Constants.SAFE_WALKSPEED)
	s.up = false
	s.expiresAt = 0
	s.cooldownUntil = 0
	s.breaksInChain += 1
	s.lastBreakAt = os.clock()

	sendShieldStatus(victim, Constants.SHIELD_READY, 0, s.breaksInChain)
	playSoundAt(getHead(victim), Constants.SHIELD_BREAK_SOUND)

	if ShotBlockedRemote then
		local shooterPlayer = playerOf(shooter)
		local victimPlayer = playerOf(victim)
		if shooterPlayer then
			ShotBlockedRemote:FireClient(shooterPlayer, handleOf(victim))
		end
		if victimPlayer then
			ShotBlockedRemote:FireClient(victimPlayer, handleOf(shooter))
		end
	end
end

local function clearShieldSilently(char: Model)
	removeShieldPart(char)
	shields[char] = newShieldState()
end

-- Everyone but the shooter draws the tracer from this; the shooter drew their own on input.
local function broadcastTracer(shooter: Model, endPoint: Vector3)
	if not ShotTracerRemote then return end
	local shooterPlayer = playerOf(shooter)
	for _, player in Players:GetPlayers() do
		if player ~= shooterPlayer then
			ShotTracerRemote:FireClient(player, shooter, endPoint)
		end
	end
end

-- Hats, hair and the welded weapon would otherwise count as body: only body parts
-- and the shield bubble stay queryable, on the server and (replicated) on every client.
local function prepareHitbox(char: Model)
	local function disable(inst: Instance)
		if not inst:IsA("BasePart") then return end
		if inst:FindFirstAncestorOfClass("Accessory") then
			inst.CanQuery = false
		end
	end
	for _, d in char:GetDescendants() do
		disable(d)
	end
	char.DescendantAdded:Connect(disable)
end

local function isFiniteVector(v: Vector3): boolean
	local components = { v.X, v.Y, v.Z }
	for _, n in components do
		if n ~= n then return false end
		if n == math.huge or n == -math.huge then return false end
	end
	return true
end

-- Walk up from the hit part to the combatant Model that owns it (player character or bot).
local function combatantFromHit(instance: Instance?): Model?
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") then
			if bots[current] or Players:GetPlayerFromCharacter(current) then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function eliminate(victim: Model, killer: Model?)
	local hum = getHumanoid(victim)
	if hum then
		hum.Health = hum.MaxHealth
	end
	clearShieldSilently(victim)
	setWalkSpeed(victim, Constants.SAFE_WALKSPEED)
	eliminatedChars[victim] = true
	eliminated:Fire(victim, killer)
end

-- A client-claimed hit stands when the claimed part belongs to a live combatant, the claimed
-- point is near that part's server position, and nothing blocks the line from origin to it.
-- The shooter's own view of the shot decides, so lag and camera parallax don't eat hits.
local function validateClaim(shooter: Model, origin: Vector3, hitPart: any, hitPosition: any): Model?
	if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") then return nil end
	if typeof(hitPosition) ~= "Vector3" or not isFiniteVector(hitPosition) then return nil end
	if (hitPosition - origin).Magnitude > Constants.PISTOL_RANGE then return nil end

	local victim = combatantFromHit(hitPart)
	if not victim or victim == shooter then return nil end
	if not hitPart:IsDescendantOf(victim) then return nil end

	local slack = hitPart.Size.Magnitude * 0.5 + Constants.PISTOL_HIT_TOLERANCE
	if (hitPosition - hitPart.Position).Magnitude > slack then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { shooter, victim }
	local blocked = Workspace:Raycast(origin, hitPosition - origin, params)
	if blocked then return nil end

	return victim
end

local function shoot(shooter: Model, origin: any, direction: any, hitPart: any, hitPosition: any)
	if not active then return end
	if not isCombatant(shooter) then return end
	if eliminatedChars[shooter] then return end

	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if not isFiniteVector(origin) or not isFiniteVector(direction) then return end
	if direction.Magnitude < 0.001 then return end

	local s = getState(shooter)
	if s.up then return end

	local now = os.clock()
	if now - s.lastShotAt < Constants.PISTOL_COOLDOWN - Constants.PISTOL_COOLDOWN_TOLERANCE then return end

	local head = getHead(shooter)
	local hum = getHumanoid(shooter)
	if not head or not hum or hum.Health <= 0 then return end
	if (origin - head.Position).Magnitude > Constants.PISTOL_ORIGIN_TOLERANCE then return end

	s.lastShotAt = now

	local aim = direction.Unit
	local victim = validateClaim(shooter, origin, hitPart, hitPosition)
	local endPoint: Vector3
	if victim then
		endPoint = hitPosition
	else
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { shooter }
		local result = Workspace:Raycast(origin, aim * Constants.PISTOL_RANGE, params)
		endPoint = if result then result.Position else origin + aim * Constants.PISTOL_RANGE
		if result then
			victim = combatantFromHit(result.Instance)
		end
	end

	broadcastTracer(shooter, endPoint)
	playSoundAt(head, Constants.PISTOL_SHOT_SOUND)
	-- Replicated shot counter; the client minimap flashes the shooter on every change.
	shooter:SetAttribute("Shots", (shooter:GetAttribute("Shots") or 0) + 1)

	if not victim or victim == shooter then return end
	if not isCombatant(victim) then return end
	if eliminatedChars[victim] then return end

	local victimHum = getHumanoid(victim)
	if not victimHum or victimHum.Health <= 0 then return end

	local victimState = getState(victim)
	if victimState.up then
		breakShield(victim, shooter)
		return
	end

	local newHealth = math.max(0, victimHum.Health - Constants.PISTOL_DAMAGE)

	local shooterPlayer = playerOf(shooter)
	local victimPlayer = playerOf(victim)
	if DamageDealtRemote and shooterPlayer then
		DamageDealtRemote:FireClient(shooterPlayer, handleOf(victim), Constants.PISTOL_DAMAGE, newHealth)
	end
	if DamageTakenRemote and victimPlayer then
		DamageTakenRemote:FireClient(victimPlayer, handleOf(shooter), Constants.PISTOL_DAMAGE, newHealth)
	end

	if newHealth <= 0 then
		eliminate(victim, shooter)
	else
		victimHum.Health = newHealth
	end
end

local function step()
	local now = os.clock()
	for char, s in shields do
		if not char.Parent then
			shields[char] = nil
			eliminatedChars[char] = nil
			continue
		end

		local hum = getHumanoid(char)
		if s.up and not hum then
			-- Character gone mid-shield: drop the state without telling the client.
			shields[char] = newShieldState()
			continue
		end

		if s.up and now >= s.expiresAt then
			lowerShield(char, true)
		elseif not s.up and s.cooldownUntil > 0 and now >= s.cooldownUntil then
			s.cooldownUntil = 0
			sendShieldStatus(char, Constants.SHIELD_READY, 0, s.breaksInChain)
		end
	end
end

-- Public entry points for server-driven combatants (bots). Same rules as the remotes.
function CombatSystem.shoot(shooter: Model, origin: Vector3, direction: Vector3)
	shoot(shooter, origin, direction, nil, nil)
end

function CombatSystem.prepareHitbox(char: Model)
	prepareHitbox(char)
end

function CombatSystem.raiseShield(char: Model)
	raiseShield(char)
end

function CombatSystem.registerBot(char: Model)
	bots[char] = true
	prepareHitbox(char)
	shields[char] = newShieldState()
end

function CombatSystem.unregisterBot(char: Model)
	bots[char] = nil
	shields[char] = nil
	eliminatedChars[char] = nil
end

function CombatSystem.start()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			removeShieldPart(char)
			shields[char] = newShieldState()
		end
		ShieldChangedRemote:FireClient(player, Constants.SHIELD_READY, 0, 0)
	end
	table.clear(eliminatedChars)
	active = true
end

function CombatSystem.stop()
	active = false
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			removeShieldPart(char)
			setWalkSpeed(char, Constants.SAFE_WALKSPEED)
		end
		ShieldChangedRemote:FireClient(player, Constants.SHIELD_READY, 0, 0)
	end
	for char in bots do
		removeShieldPart(char)
	end
	table.clear(shields)
	table.clear(eliminatedChars)
end

function CombatSystem.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")

	ShootRequestRemote = ensureRemote(Remotes, "ShootRequest")
	ShieldRequestRemote = ensureRemote(Remotes, "ShieldRequest")
	ShieldChangedRemote = ensureRemote(Remotes, "ShieldChanged")
	ShotBlockedRemote = ensureRemote(Remotes, "ShotBlocked")
	DamageDealtRemote = ensureRemote(Remotes, "DamageDealt")
	DamageTakenRemote = ensureRemote(Remotes, "DamageTaken")
	ShotTracerRemote = ensureRemote(Remotes, "ShotTracer")

	ShootRequestRemote.OnServerEvent:Connect(function(player, origin, direction, hitPosition, hitPart)
		local char = player.Character
		if not char then return end
		shoot(char, origin, direction, hitPart, hitPosition)
	end)

	ShieldRequestRemote.OnServerEvent:Connect(function(player, raise)
		if typeof(raise) ~= "boolean" then return end
		local char = player.Character
		if not char then return end
		if raise then
			raiseShield(char)
		else
			if not active then return end
			lowerShield(char, true)
		end
	end)

	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	heartbeatConn = RunService.Heartbeat:Connect(step)
end

return CombatSystem
