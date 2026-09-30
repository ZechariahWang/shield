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
-- request and draws the rope for everyone. The pull is a LinearVelocity with a
-- finite force that brakes before the anchor, so geometry in the way stops the
-- character instead of launching it. While attached the movement input steers
-- sideways, jump steers up and the Slide key steers down, all across the rope.
local GrappleController = {}

local localPlayer = Players.LocalPlayer
local GrappleRequestRemote: RemoteEvent
local GrappleReleaseRemote: RemoteEvent

local currentPhase: string = Constants.PHASE_LOBBY
local anchor: Vector3? = nil
local pull: LinearVelocity? = nil
local startSpeed = 0
local startedAt = 0
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

local function makePull(root: BasePart): LinearVelocity
	local attachment = root:FindFirstChild("RootAttachment") :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "RootAttachment"
		attachment.Parent = root
	end
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "GrappleVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = root.AssemblyMass * Constants.PUSH_MAX_ACCEL
	velocity.VectorVelocity = root.AssemblyLinearVelocity
	velocity.Parent = root
	return velocity
end

-- `launchDirection` is set only when the pull arrived: the character then
-- carries on past the anchor instead of stopping at it.
local function release(launchDirection: Vector3?)
	if not anchor then return end
	anchor = nil
	stalledSince = nil
	lastReleaseAt = os.clock()
	if pull then
		pull:Destroy()
		pull = nil
	end
	local root = getRoot()
	if root and launchDirection then
		root.AssemblyLinearVelocity = GrappleMath.launchVelocity(root.AssemblyLinearVelocity, launchDirection)
	elseif root then
		root.AssemblyLinearVelocity = GrappleMath.clampSpeed(root.AssemblyLinearVelocity, Constants.GRAPPLE_SPEED)
	end
	GrappleReleaseRemote:FireServer()
end

local function start(root: BasePart, hum: Humanoid, point: Vector3)
	local direction = (point - root.Position).Unit
	anchor = point
	startSpeed = root.AssemblyLinearVelocity:Dot(direction)
	startedAt = os.clock()
	stalledSince = nil
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
		release()
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

local function step()
	local point = anchor
	if not point then return end
	local root = getRoot()
	local now = os.clock()
	local elapsed = now - startedAt
	if not root or not pull or not pull.Parent or not canHold() or elapsed >= Constants.GRAPPLE_MAX_TIME then
		release()
		return
	end
	local offset = point - root.Position
	local distance = offset.Magnitude
	local direction = offset.Unit
	if distance <= Constants.GRAPPLE_ARRIVE_DISTANCE then
		release(direction)
		return
	end
	if isStalled(root, now) then
		release()
		return
	end
	local along = direction * GrappleMath.pullSpeed(startSpeed, elapsed, distance)
	pull.VectorVelocity = along + steering(root, direction)
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

	RunService.RenderStepped:Connect(step)
end

return GrappleController
