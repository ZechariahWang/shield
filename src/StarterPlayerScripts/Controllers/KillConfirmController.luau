local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local KillConfirmSound = ReplicatedStorage:FindFirstChild("Sounds"):FindFirstChild("Game"):FindFirstChild("KillConfirm") :: Sound

local KillConfirmController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local FRAME_EXPAND_TIME = 0.25
local TEXT_FADE_IN_TIME = 0.20
local HOLD_TIME = 3.0
local TEXT_FADE_OUT_TIME = 0.20
local FRAME_COLLAPSE_TIME = 0.25

-- Stacking: newest banner sits at the template's authored position; older
-- banners shift by (STACK_DIRECTION = -1 → upward) per slot. Flip to +1 if
-- the popup lives near the top of the screen and should grow downward.
local STACK_GAP = 4
local STACK_DIRECTION = -1
local STACK_TWEEN_TIME = 0.18
local MAX_STACK = 5

local LABEL_COLOR = "rgb(255,245,220)"
local NAME_COLOR = "rgb(255,159,80)"

local activeBanners: { GuiObject } = {}

local function findGameGui(): ScreenGui?
	if not playerGui then return nil end
	local gui = playerGui:FindFirstChild("Game")
	if gui and gui:IsA("ScreenGui") then
		return gui
	end
	return nil
end

local function getTemplate(): GuiObject?
	local gui = findGameGui()
	if not gui then return nil end
	local idObjects = gui:FindFirstChild("ID_Objects")
	if not idObjects then return nil end
	local template = idObjects:FindFirstChild("KillConfirm")
	if template and template:IsA("GuiObject") then
		return template
	end
	return nil
end

local function buildText(victimName: string): string
	return string.format(
		'<font color="%s">ELIMINATED</font> <font color="%s">%s</font>',
		LABEL_COLOR,
		NAME_COLOR,
		string.upper(victimName)
	)
end

-- Reflow positions every active banner: the most recently spawned (last in
-- the array) sits at the template's authored position; each older banner is
-- offset by (height + gap) * STACK_DIRECTION per slot away from it.
local function reflowBanners()
	local template = getTemplate()
	if not template then return end
	local basePos = template.Position
	local refHeight = template.AbsoluteSize.Y
	if refHeight <= 0 then refHeight = 30 end
	local count = #activeBanners
	for i, banner in ipairs(activeBanners) do
		if not banner.Parent then continue end
		local stackIndex = count - i
		local targetY = basePos.Y.Offset + STACK_DIRECTION * stackIndex * (refHeight + STACK_GAP)
		local target = UDim2.new(basePos.X.Scale, basePos.X.Offset, basePos.Y.Scale, targetY)
		TweenService:Create(
			banner,
			TweenInfo.new(STACK_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = target }
		):Play()
	end
end

local function playKillConfirm(victimName: string)
	local template = getTemplate()
	local gui = findGameGui()
	if not template or not gui then return end

	local clone = template:Clone()
	local title = clone:FindFirstChild("Title")
	if not title or not title:IsA("TextLabel") then
		clone:Destroy()
		return
	end

	local stroke = title:FindFirstChildOfClass("UIStroke")
	local originalSize = clone.Size
	local collapsedSize = UDim2.new(0, 0, originalSize.Y.Scale, originalSize.Y.Offset)
	local originalTextTransparency = title.TextTransparency
	local originalStrokeTransparency = stroke and stroke.Transparency or 0

	clone.Size = collapsedSize
	clone.Position = template.Position
	title.RichText = true
	title.Text = buildText(victimName)
	title.TextTransparency = 1
	if stroke then stroke.Transparency = 1 end
	clone.Visible = true
	clone.Parent = gui

	if KillConfirmSound then
		KillConfirmSound:Play()
	end

	table.insert(activeBanners, clone)
	-- Soft cap: oldest banner gets evicted so the stack can't run off-screen.
	-- Its own coroutine bails on the next `clone.Parent` check after destroy.
	while #activeBanners > MAX_STACK do
		local oldest = table.remove(activeBanners, 1)
		if oldest and oldest.Parent then oldest:Destroy() end
	end
	reflowBanners()

	local function alive(): boolean
		return clone.Parent ~= nil
	end

	TweenService:Create(
		clone,
		TweenInfo.new(FRAME_EXPAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = originalSize }
	):Play()
	task.wait(FRAME_EXPAND_TIME)
	if not alive() then return end

	TweenService:Create(
		title,
		TweenInfo.new(TEXT_FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = originalTextTransparency }
	):Play()
	if stroke then
		TweenService:Create(
			stroke,
			TweenInfo.new(TEXT_FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = originalStrokeTransparency }
		):Play()
	end
	task.wait(TEXT_FADE_IN_TIME)
	if not alive() then return end

	task.wait(HOLD_TIME)
	if not alive() then return end

	TweenService:Create(
		title,
		TweenInfo.new(TEXT_FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1 }
	):Play()
	if stroke then
		TweenService:Create(
			stroke,
			TweenInfo.new(TEXT_FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1 }
		):Play()
	end
	task.wait(TEXT_FADE_OUT_TIME)
	if not alive() then return end

	TweenService:Create(
		clone,
		TweenInfo.new(FRAME_COLLAPSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = collapsedSize }
	):Play()
	task.wait(FRAME_COLLAPSE_TIME)

	local idx = table.find(activeBanners, clone)
	if idx then table.remove(activeBanners, idx) end
	if clone.Parent then clone:Destroy() end
	reflowBanners()
end

local function onKillFeed(killerName: string?, victimName: string)
	if killerName ~= localPlayer.Name then return end
	task.spawn(playKillConfirm, victimName)
end

function KillConfirmController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local KillFeedRemote = Remotes:WaitForChild("KillFeed") :: RemoteEvent

	KillFeedRemote.OnClientEvent:Connect(onKillFeed)
end

return KillConfirmController
