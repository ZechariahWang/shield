local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local CombatController = require(script.Parent.CombatController)

-- Client-side movement extras while combat is active: hold Shift to sprint,
-- hold right click to aim (FOV zoom only), and press jump again in the air for
-- a double jump. This controller is the only writer of the camera FOV. The local
-- character is client-simulated, so WalkSpeed is set here and re-applied every
-- frame because the server rewrites it on shield changes.
local MovementController = {}

local localPlayer = Players.LocalPlayer
local shiftHeld = false
local aimHeld = false
local sprinting = false
local aiming = false
local currentFovTarget = Constants.CAMERA_FOV
local fovTween: Tween? = nil

local canDoubleJump = false
local doubleJumped = false

local function getHumanoid(): Humanoid?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function tweenFov(target: number, duration: number)
	if target == currentFovTarget then return end
	currentFovTarget = target
	local camera = Workspace.CurrentCamera
	if not camera then return end
	if fovTween then fovTween:Cancel() end
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = target }
	)
	fovTween:Play()
end

-- Aim wins over sprint for the FOV; sprint still applies to WalkSpeed.
local function reconcileFov()
	if aiming then
		tweenFov(Constants.AIM_FOV, Constants.AIM_FOV_TWEEN_TIME)
	elseif sprinting then
		tweenFov(Constants.SPRINT_FOV, Constants.SPRINT_FOV_TWEEN_TIME)
	else
		local duration = if currentFovTarget == Constants.AIM_FOV then Constants.AIM_FOV_TWEEN_TIME else Constants.SPRINT_FOV_TWEEN_TIME
		tweenFov(Constants.CAMERA_FOV, duration)
	end
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
end

local function step()
	setSprinting(canSprint())
	aiming = aimHeld and CombatController.isCombatActive()
	reconcileFov()
	if not sprinting then return end
	local hum = getHumanoid()
	if hum and hum.WalkSpeed ~= Constants.SPRINT_WALKSPEED then
		hum.WalkSpeed = Constants.SPRINT_WALKSPEED
	end
end

local function onJumpRequest()
	if not CombatController.isCombatActive() then return end
	if not canDoubleJump or doubleJumped then return end
	local hum = getHumanoid()
	if not hum or hum:GetState() ~= Enum.HumanoidStateType.Freefall then return end
	doubleJumped = true
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
end

local function bindCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum or not hum:IsA("Humanoid") then return end
	canDoubleJump = false
	doubleJumped = false
	hum.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Landed then
			canDoubleJump = false
			doubleJumped = false
		elseif new == Enum.HumanoidStateType.Freefall then
			-- Wait a beat so the first jump's own Freefall doesn't immediately count as airborne.
			task.delay(Constants.DOUBLE_JUMP_DELAY, function()
				if hum:GetState() == Enum.HumanoidStateType.Freefall then
					canDoubleJump = true
				end
			end)
		end
	end)
end

function MovementController.isSprinting(): boolean
	return sprinting
end

function MovementController.isAiming(): boolean
	return aiming
end

function MovementController.init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			aimHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			aimHeld = false
		end
	end)
	UserInputService.JumpRequest:Connect(onJumpRequest)

	localPlayer.CharacterAdded:Connect(bindCharacter)
	if localPlayer.Character then
		bindCharacter(localPlayer.Character)
	end

	RunService.RenderStepped:Connect(step)
end

return MovementController
