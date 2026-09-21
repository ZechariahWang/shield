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

local FOV_LERP_RATE = 8

local stockFov = 70
local stockMinZoom = 0.5
local stockMaxZoom = 128

local function shouldBeActive(): boolean
	if localState ~= Constants.STATE_SAFE then return false end
	return currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND
end

-- Damage shake adds to this so the two never fight over Humanoid.CameraOffset.
function CameraController.getBaseOffset(): Vector3
	return if active then Constants.CAMERA_SHOULDER_OFFSET else Vector3.zero
end

function CameraController.isActive(): boolean
	return active
end

local function setActive(on: boolean)
	if active == on then return end
	active = on

	if on then
		stockFov = Workspace.CurrentCamera.FieldOfView
		stockMinZoom = localPlayer.CameraMinZoomDistance
		stockMaxZoom = localPlayer.CameraMaxZoomDistance
		localPlayer.CameraMinZoomDistance = Constants.CAMERA_MIN_ZOOM
		localPlayer.CameraMaxZoomDistance = Constants.CAMERA_MAX_ZOOM
		UserGameSettings.RotationType = Enum.RotationType.CameraRelative
	else
		localPlayer.CameraMinZoomDistance = stockMinZoom
		localPlayer.CameraMaxZoomDistance = stockMaxZoom
		UserGameSettings.RotationType = Enum.RotationType.MovementRelative
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		Workspace.CurrentCamera.FieldOfView = stockFov
	end
end

local function step(dt: number)
	if not active then return end
	-- Roblox's camera scripts reset MouseBehavior every frame, so re-assert it.
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
		local alpha = 1 - math.exp(-FOV_LERP_RATE * dt)
		camera.FieldOfView += (Constants.CAMERA_COMBAT_FOV - camera.FieldOfView) * alpha
	end
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

	RunService.RenderStepped:Connect(step)
end

return CameraController
