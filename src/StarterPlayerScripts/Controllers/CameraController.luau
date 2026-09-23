local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local CameraController = {}

local localPlayer = Players.LocalPlayer
local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY
local active = false

-- Target angles come straight from the mouse; the smoothed pair is what the camera renders.
local yaw = 0
local pitch = 0
local smoothYaw = 0
local smoothPitch = 0
local smoothFocus = Vector3.zero
local zoom = Constants.CAMERA_DEFAULT_ZOOM
local smoothDistance = Constants.CAMERA_DEFAULT_ZOOM
local shakeOffset = Vector3.zero

local stockFov = 70
local stockMinZoom = 0.5
local stockMaxZoom = 128

local PITCH_MIN = math.rad(Constants.CAMERA_PITCH_MIN)
local PITCH_MAX = math.rad(Constants.CAMERA_PITCH_MAX)

local function shouldBeActive(): boolean
	if localState ~= Constants.STATE_SAFE then return false end
	return currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND
end

local function lerpRate(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function getRoot(): BasePart?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(): Humanoid?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

function CameraController.isActive(): boolean
	return active
end

-- Damage shake feeds a camera-space offset here; the camera adds it on top of its own pose.
function CameraController.setShake(offset: Vector3)
	shakeOffset = offset
end

local function seedFromCurrentCamera()
	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.asin(math.clamp(look.Y, -1, 1))
	pitch = math.clamp(pitch, PITCH_MIN, PITCH_MAX)
	smoothYaw = yaw
	smoothPitch = pitch

	local root = getRoot()
	smoothFocus = if root then root.Position + Vector3.new(0, Constants.CAMERA_FOCUS_HEIGHT, 0) else camera.CFrame.Position
	zoom = Constants.CAMERA_DEFAULT_ZOOM
	smoothDistance = zoom
	shakeOffset = Vector3.zero
end

local function setActive(on: boolean)
	if active == on then return end
	active = on

	local camera = Workspace.CurrentCamera
	if on then
		stockFov = camera.FieldOfView
		stockMinZoom = localPlayer.CameraMinZoomDistance
		stockMaxZoom = localPlayer.CameraMaxZoomDistance
		seedFromCurrentCamera()
		camera.CameraType = Enum.CameraType.Scriptable
		UserGameSettings.RotationType = Enum.RotationType.CameraRelative
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserGameSettings.RotationType = Enum.RotationType.MovementRelative
		localPlayer.CameraMinZoomDistance = stockMinZoom
		localPlayer.CameraMaxZoomDistance = stockMaxZoom
		camera.FieldOfView = stockFov
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = getHumanoid()
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function onInputChanged(input: InputObject, gameProcessed: boolean)
	if not active then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local sensitivity = Constants.CAMERA_SENSITIVITY * UserGameSettings.MouseSensitivity
		yaw -= input.Delta.X * sensitivity
		pitch = math.clamp(pitch - input.Delta.Y * sensitivity, PITCH_MIN, PITCH_MAX)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not gameProcessed then
		zoom = math.clamp(zoom - input.Position.Z * Constants.CAMERA_ZOOM_STEP, Constants.CAMERA_MIN_ZOOM, Constants.CAMERA_MAX_ZOOM)
	end
end

-- Pull the camera in front of anything between the pivot and where it wants to sit.
local function occludedDistance(pivot: Vector3, back: Vector3, wanted: number): number
	local char = localPlayer.Character
	if not char then return wanted end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true
	local result = Workspace:Raycast(pivot, back * wanted, params)
	if not result then return wanted end
	return math.max(result.Distance - Constants.CAMERA_OCCLUSION_PADDING, Constants.CAMERA_OCCLUSION_MIN_DISTANCE)
end

local function step(dt: number)
	if not active then return end
	local camera = Workspace.CurrentCamera
	local root = getRoot()
	if not camera or not root then return end

	-- Roblox's camera scripts are idle while Scriptable, but re-asserting is free and survives focus changes.
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	local rotAlpha = lerpRate(Constants.CAMERA_ROTATION_SMOOTHING, dt)
	smoothYaw += (yaw - smoothYaw) * rotAlpha
	smoothPitch += (pitch - smoothPitch) * rotAlpha

	local focusTarget = root.Position + Vector3.new(0, Constants.CAMERA_FOCUS_HEIGHT, 0)
	smoothFocus = smoothFocus:Lerp(focusTarget, lerpRate(Constants.CAMERA_FOLLOW_SMOOTHING, dt))

	local rotation = CFrame.fromEulerAnglesYXZ(smoothPitch, smoothYaw, 0)
	local pivot = smoothFocus + rotation:VectorToWorldSpace(Constants.CAMERA_SHOULDER_OFFSET)

	local back = -rotation.LookVector
	local wanted = occludedDistance(pivot, back, zoom)
	-- Snap in fast so walls never clip, ease back out so the zoom does not pop.
	local zoomRate = if wanted < smoothDistance then Constants.CAMERA_OCCLUSION_IN_RATE else Constants.CAMERA_ZOOM_SMOOTHING
	smoothDistance += (wanted - smoothDistance) * lerpRate(zoomRate, dt)

	local position = pivot + back * smoothDistance + rotation:VectorToWorldSpace(shakeOffset)
	camera.CFrame = CFrame.new(position) * rotation
	camera.Focus = CFrame.new(pivot)
	camera.FieldOfView += (Constants.CAMERA_COMBAT_FOV - camera.FieldOfView) * lerpRate(Constants.CAMERA_FOV_SMOOTHING, dt)
end

function CameraController.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
		setActive(shouldBeActive())
	end)

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		setActive(shouldBeActive())
	end)

	UserInputService.InputChanged:Connect(onInputChanged)
	-- After the stock camera update so nothing runs over our CFrame within the frame.
	RunService:BindToRenderStep("CombatCamera", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
