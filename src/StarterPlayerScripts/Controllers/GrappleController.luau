local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local GrappleMath = require(ReplicatedStorage.Shared.GrappleMath)
local CombatController = require(script.Parent.CombatController)
local SettingsController = require(script.Parent.SettingsController)

-- Grapple: holding the Grapple key latches one rope onto the map geometry under the
-- crosshair and pulls the character to it. The pull runs here because the local
-- character is client-simulated; the server (GrappleSystem) validates the
-- request and draws the rope for everyone. Every frame the velocity the character
-- actually has goes through GrappleMath.pullVelocity, so momentum carries into
-- and out of the rope and a collision is felt. It is applied by a LinearVelocity
-- with a finite force, so geometry in the way stops the character instead of
-- launching it. While attached the movement input steers sideways, jump steers
-- up and the Slide key steers down, all across the rope.
local GrappleController = {}

local localPlayer = Players.LocalPlayer
local GrappleRequestRemote: RemoteEvent
local GrappleReleaseRemote: RemoteEvent

local currentPhase: string = Constants.PHASE_LOBBY
local anchor: Vector3? = nil
local pull: LinearVelocity? = nil
local carry: LinearVelocity? = nil
local startedAt = 0
local closing = false
local stalledSince: number? = nil
local lastReleaseAt = -math.huge
local downHeld = false

local function getRoot(): BasePart?
	local char = localPlayer.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	return hum.RootPart
end

local function canHold(): boolean
	if currentPhase ~= Constants.PHASE_ROUND then return false end
	if not CombatController.isCombatActive() then return false end
	return CombatController.getShieldStatus() ~= Constants.SHIELD_UP
end

local function rootAttachment(root: BasePart): Attachment
	local attachment = root:FindFirstChild("RootAttachment") :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "RootAttachment"
		attachment.Parent = root
	end
	return attachment :: Attachment
end

local function makePull(root: BasePart): LinearVelocity
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "GrappleVelocity"
	velocity.Attachment0 = rootAttachment(root)
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = root.AssemblyMass * Constants.PUSH_MAX_ACCEL
	velocity.VectorVelocity = root.AssemblyLinearVelocity
	velocity.Parent = root
	return velocity
end

local function stopCarry()
	if carry then
		carry:Destroy()
		carry = nil
	end
end

-- An airborne humanoid brakes its own horizontal speed (about 150 studs/s^2), so
-- the speed a release leaves is held in the horizontal plane until the character
-- lands or is down to running pace. Gravity owns the vertical axis.
local function startCarry(root: BasePart)
	local velocity = root.AssemblyLinearVelocity
	local hold = Instance.new("LinearVelocity")
	hold.Name = "GrappleCarry"
	hold.Attachment0 = rootAttachment(root)
	hold.RelativeTo = Enum.ActuatorRelativeTo.World
	hold.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	hold.PrimaryTangentAxis = Vector3.xAxis
	hold.SecondaryTangentAxis = Vector3.zAxis
	hold.MaxForce = root.AssemblyMass * Constants.PUSH_MAX_ACCEL
	hold.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	hold.Parent = root
	carry = hold
end

-- `hop` is set when the player let go or the pull arrived: the character leaves
-- the rope with a lift on top of the velocity it carries.
local function release(hop: boolean)
	if not anchor then return end
	anchor = nil
	stalledSince = nil
	lastReleaseAt = os.clock()
	if pull then
		pull:Destroy()
		pull = nil
	end
	local root = getRoot()
	if root and hop then
		root.AssemblyLinearVelocity = GrappleMath.releaseVelocity(root.AssemblyLinearVelocity)
	elseif root then
		root.AssemblyLinearVelocity = GrappleMath.clampSpeed(root.AssemblyLinearVelocity, Constants.GRAPPLE_MAX_SPEED)
	end
	if root and CombatController.isCombatActive() then
		startCarry(root)
	end
	GrappleReleaseRemote:FireServer()
end

local function start(root: BasePart, hum: Humanoid, point: Vector3)
	stopCarry()
	anchor = point
	startedAt = os.clock()
	closing = false
	stalledSince = nil
	if hum.FloorMaterial ~= Enum.Material.Air then
		root.AssemblyLinearVelocity += Vector3.yAxis * Constants.GRAPPLE_START_HOP
	end
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
	pull = makePull(root)
	GrappleRequestRemote:FireServer(point)
end

local function tryGrapple()
	if anchor then return end
	if not canHold() then return end
	if os.clock() - lastReleaseAt < Constants.GRAPPLE_COOLDOWN then return end

	local char = localPlayer.Character
	local root = getRoot()
	if not char or not root then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local head = char:FindFirstChild("Head")
	if not hum or not head or not head:IsA("BasePart") then return end

	local _, aimPoint, hitPart = CombatController.getAim(head.Position)
	if not aimPoint or not hitPart then return end
	local map = Workspace:FindFirstChild("LoadedMap")
	if not map or not hitPart:IsDescendantOf(map) then return end
	if not GrappleMath.validAnchor(root.Position, aimPoint, 0) then return end
	if (aimPoint - root.Position).Magnitude <= Constants.GRAPPLE_ARRIVE_DISTANCE then return end

	start(root, hum, aimPoint)
end

-- The rope lives while the key is held: down fires it, up lets go. A rope that
-- let go on its own (arrival, stall) needs a new press.
function GrappleController.setHeld(on: boolean)
	if on then
		tryGrapple()
	else
		release(true)
	end
end

function GrappleController.isGrappling(): boolean
	return anchor ~= nil
end

-- Something in the way: barely moving for GRAPPLE_STALL_TIME.
local function isStalled(root: BasePart, now: number): boolean
	if root.AssemblyLinearVelocity.Magnitude >= Constants.GRAPPLE_STALL_SPEED then
		stalledSince = nil
		return false
	end
	if not stalledSince then
		stalledSince = now
	end
	return now - stalledSince >= Constants.GRAPPLE_STALL_TIME
end

-- Sideways comes from the movement input along the camera's right (A/D, or the
-- thumbstick); up is jump held, down the Slide key. Humanoid.Jump is read rather
-- than JumpRequest, which fires with gaps of up to half a second while held.
local function steering(root: BasePart, direction: Vector3): Vector3
	local camera = Workspace.CurrentCamera
	local hum = (root.Parent :: Instance):FindFirstChildOfClass("Humanoid")
	if not camera or not hum then return Vector3.zero end
	local right = camera.CFrame.RightVector
	local sideways = math.clamp(hum.MoveDirection:Dot(right), -1, 1)
	local vertical = 0
	if hum.Jump then
		vertical += 1
	end
	if downHeld then
		vertical -= 1
	end
	return GrappleMath.steer(direction, right, sideways, vertical)
end

local function step(dt: number)
	local point = anchor
	if not point then return end
	local root = getRoot()
	local now = os.clock()
	local elapsed = now - startedAt
	if not root or not pull or not pull.Parent or not canHold() or elapsed >= Constants.GRAPPLE_MAX_TIME then
		release(false)
		return
	end
	local offset = point - root.Position
	local distance = offset.Magnitude
	local direction = offset.Unit
	if distance <= Constants.GRAPPLE_ARRIVE_DISTANCE then
		release(true)
		return
	end
	if isStalled(root, now) then
		release(false)
		return
	end
	-- Past the anchor (it was closing in and no longer is): let go rather than orbit it.
	local velocity = root.AssemblyLinearVelocity
	local towardAnchor = velocity:Dot(direction)
	if towardAnchor > 0 then
		closing = true
	elseif closing and towardAnchor < 0 then
		release(true)
		return
	end
	local steerAccel = steering(root, direction)
	pull.VectorVelocity = GrappleMath.pullVelocity(velocity, direction, steerAccel, dt)
end

local function stepCarry(dt: number)
	local hold = carry
	if not hold then return end
	local root = getRoot()
	local hum = root and (root.Parent :: Instance):FindFirstChildOfClass("Humanoid")
	if not root or not hum or not hold.Parent or not CombatController.isCombatActive() then
		stopCarry()
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local landed = hum.FloorMaterial ~= Enum.Material.Air and velocity.Y <= 0
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local dashing = root:FindFirstChild("DashVelocity") ~= nil
	if landed or dashing or horizontalSpeed <= Constants.SPRINT_WALKSPEED then
		stopCarry()
		return
	end
	local carried = GrappleMath.carryVelocity(velocity, hum.MoveDirection, dt)
	hold.PlaneVelocity = Vector2.new(carried.X, carried.Z)
end

function GrappleController.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	GrappleRequestRemote = Remotes:WaitForChild("GrappleRequest") :: RemoteEvent
	GrappleReleaseRemote = Remotes:WaitForChild("GrappleRelease") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		local prevPhase = currentPhase
		currentPhase = phase
		if phase == Constants.PHASE_ROUND and prevPhase ~= Constants.PHASE_ROUND then
			lastReleaseAt = -math.huge
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if SettingsController.matches(input, "Grapple") then
			GrappleController.setHeld(true)
		elseif SettingsController.matches(input, "Slide") then
			downHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if SettingsController.matches(input, "Grapple") then
			GrappleController.setHeld(false)
		elseif SettingsController.matches(input, "Slide") then
			downHeld = false
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		step(dt)
		stepCarry(dt)
	end)
end

return GrappleController
