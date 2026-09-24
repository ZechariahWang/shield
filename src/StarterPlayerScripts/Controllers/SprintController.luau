local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local CombatController = require(script.Parent.CombatController)

-- Hold Shift to sprint while combat is active and the shield is down. The local
-- character is client-simulated, so WalkSpeed is set here; it is re-applied every
-- frame because the server rewrites WalkSpeed on shield changes.
local SprintController = {}

local localPlayer = Players.LocalPlayer
local shiftHeld = false
local sprinting = false
local fovTween: Tween? = nil

local function getHumanoid(): Humanoid?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function tweenFov(target: number)
	local camera = Workspace.CurrentCamera
	if not camera then return end
	if fovTween then fovTween:Cancel() end
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(Constants.SPRINT_FOV_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = target }
	)
	fovTween:Play()
end

local function canSprint(): boolean
	if not shiftHeld then return false end
	if not CombatController.isCombatActive() then return false end
	return CombatController.getShieldStatus() ~= Constants.SHIELD_UP
end

local function setSprinting(on: boolean)
	if on == sprinting then return end
	sprinting = on
	local hum = getHumanoid()
	if hum then
		hum.WalkSpeed = if on then Constants.SPRINT_WALKSPEED else Constants.SAFE_WALKSPEED
	end
	tweenFov(if on then Constants.SPRINT_FOV else Constants.CAMERA_FOV)
end

local function step()
	setSprinting(canSprint())
	if not sprinting then return end
	local hum = getHumanoid()
	if hum and hum.WalkSpeed ~= Constants.SPRINT_WALKSPEED then
		hum.WalkSpeed = Constants.SPRINT_WALKSPEED
	end
end

function SprintController.isSprinting(): boolean
	return sprinting
end

function SprintController.init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = false
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return SprintController
