local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ShopButtonController = {}

local TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local IDLE_SCALE = 1
local HOVER_SCALE = 1.05
local PRESS_SCALE = 0.95
local IDLE_TRANSPARENCY = 0.25
local HOVER_TRANSPARENCY = 0.05

local hovering = false
local pressing = false

local function refresh(button: TextButton, scale: UIScale)
	local targetScale = IDLE_SCALE
	if pressing then
		targetScale = PRESS_SCALE
	elseif hovering then
		targetScale = HOVER_SCALE
	end
	local targetTransparency = if hovering or pressing then HOVER_TRANSPARENCY else IDLE_TRANSPARENCY

	TweenService:Create(scale, TWEEN_INFO, { Scale = targetScale }):Play()
	TweenService:Create(button, TWEEN_INFO, { BackgroundTransparency = targetTransparency }):Play()
end

function ShopButtonController.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local lobbyGui = playerGui:WaitForChild("Lobby")
	local button = lobbyGui:WaitForChild("ShopButton") :: TextButton
	local scale = button:WaitForChild("UIScale") :: UIScale

	button.MouseEnter:Connect(function()
		hovering = true
		refresh(button, scale)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		pressing = false
		refresh(button, scale)
	end)
	button.MouseButton1Down:Connect(function()
		pressing = true
		refresh(button, scale)
	end)
	button.MouseButton1Up:Connect(function()
		pressing = false
		refresh(button, scale)
	end)
end

return ShopButtonController
