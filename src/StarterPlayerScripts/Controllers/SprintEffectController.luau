local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MovementController = require(script.Parent.MovementController)

-- Purely cosmetic sprint speed lines: thin streaks hanging off the screen
-- border, pointing at the center, that fade in while the local character is sprinting
-- and actually moving at sprint speed, and flicker by respawning at new angles.
-- Built in code inside the Game ScreenGui; nothing here touches gameplay.
local SprintEffectController = {}

local localPlayer = Players.LocalPlayer

type Streak = { frame: Frame, dieAt: number }
local container: Frame
local streaks: { Streak } = {}
local intensity = 0

local function respawn(streak: Streak)
	local half = container.AbsoluteSize / 2
	local angle = math.random() * 2 * math.pi
	local dir = Vector2.new(math.cos(angle), math.sin(angle))
	-- Distance from the center to the screen border along this angle: the streak's bright end sits right on it.
	local edge = math.min(half.X / math.max(math.abs(dir.X), 0.001), half.Y / math.max(math.abs(dir.Y), 0.001))
	local length = edge * (Constants.SPEED_LINE_MIN_LENGTH + math.random() * (Constants.SPEED_LINE_MAX_LENGTH - Constants.SPEED_LINE_MIN_LENGTH))
	local center = half + dir * (edge - length / 2)
	local frame = streak.frame
	frame.Size = UDim2.fromOffset(length, Constants.SPEED_LINE_THICKNESS)
	frame.Position = UDim2.fromOffset(center.X, center.Y)
	frame.Rotation = math.deg(angle)
	streak.dieAt = os.clock() + Constants.SPEED_LINE_LIFETIME * (0.5 + math.random() * 0.5)
end

local function buildStreak(): Streak
	local frame = Instance.new("Frame")
	frame.Name = "Streak"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Constants.SPEED_LINE_COLOR
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	-- Bright at the edge end, gone at the center end (local X runs outward).
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = frame
	frame.Parent = container
	local streak = { frame = frame, dieAt = 0 }
	respawn(streak)
	return streak
end

local function buildContainer(gameGui: ScreenGui)
	container = Instance.new("Frame")
	container.Name = "SpeedLines"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Visible = false
	container.Parent = gameGui
	for _ = 1, Constants.SPEED_LINE_COUNT do
		table.insert(streaks, buildStreak())
	end
end

local function movingAtSprintSpeed(): boolean
	if not MovementController.isSprinting() then return false end
	local char = localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end
	local v = root.AssemblyLinearVelocity
	local horizontal = Vector2.new(v.X, v.Z).Magnitude
	return horizontal >= Constants.SPEED_LINE_MIN_SPEED
end

local function step(dt: number)
	local target = if movingAtSprintSpeed() then 1 else 0
	local maxStep = dt / Constants.SPEED_LINE_FADE_TIME
	intensity += math.clamp(target - intensity, -maxStep, maxStep)
	container.Visible = intensity > 0
	if not container.Visible then return end
	local now = os.clock()
	for _, streak in streaks do
		if now >= streak.dieAt then
			respawn(streak)
		end
		streak.frame.BackgroundTransparency = 1 - intensity * (1 - Constants.SPEED_LINE_MAX_TRANSPARENCY)
	end
end

function SprintEffectController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gameGui = playerGui:WaitForChild("Game") :: ScreenGui
	buildContainer(gameGui)
	RunService.RenderStepped:Connect(step)
end

return SprintEffectController
