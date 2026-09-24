local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- Forces shift lock while combat is active, the same way the stock PlayerModule
-- does it internally: CameraRelative rotation so the character faces the camera,
-- the mouse locked to screen center, and a shoulder CameraOffset. The stock
-- CameraModule no longer exposes its mouse lock controller, so this re-asserts
-- the mouse behavior right after the camera update each frame. Shift's built-in
-- toggle is unbound so it neither fights this nor conflicts with sprint.
local ShiftLockController = {}

local localPlayer = Players.LocalPlayer
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local MOUSE_LOCK_SWITCH_ACTION = "MouseLockSwitchAction"
local RENDER_STEP_NAME = "BurnRushShiftLock"

local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY
local locked = false

local function getHumanoid(): Humanoid?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

function ShiftLockController.isLocked(): boolean
	return locked
end

-- The CameraOffset the character should rest at; the damage shake adds on top of this.
function ShiftLockController.baseCameraOffset(): Vector3
	return if locked then Constants.SHIFTLOCK_CAMERA_OFFSET else Vector3.zero
end

local function step()
	if not locked then return end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserGameSettings.RotationType = Enum.RotationType.CameraRelative
end

local function setLocked(on: boolean)
	if on == locked then return end
	locked = on
	pcall(ContextActionService.UnbindAction, ContextActionService, MOUSE_LOCK_SWITCH_ACTION)
	if on then
		RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, step)
	else
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserGameSettings.RotationType = Enum.RotationType.MovementRelative
	end
	local hum = getHumanoid()
	if hum then
		hum.CameraOffset = ShiftLockController.baseCameraOffset()
	end
end

local function reconcile()
	local active = localState == Constants.STATE_SAFE
		and (currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND)
	setLocked(active)
end

function ShiftLockController.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
		reconcile()
	end)

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		reconcile()
	end)

	localPlayer.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 5)
		if hum and hum:IsA("Humanoid") then
			hum.CameraOffset = ShiftLockController.baseCameraOffset()
		end
	end)

	-- The stock controller binds Shift once it loads; drop that binding so Shift is free for sprint.
	task.delay(1, function()
		pcall(ContextActionService.UnbindAction, ContextActionService, MOUSE_LOCK_SWITCH_ACTION)
	end)
end

return ShiftLockController
