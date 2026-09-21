local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KillFeedController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local MAX_ENTRIES = 5
local DISPLAY_TIME = 4
local FADE_IN_TIME = 0.25
local FADE_OUT_TIME = 0.4
local SLIDE_OFFSET = 80

local KILLER_COLOR = "rgb(255,159,80)"
local VERB_TRANSPARENCY = 0.4

type Entry = {
	row: GuiObject,
	label: TextLabel,
	stroke: UIStroke?,
	strip: GuiObject?,
	removing: boolean,
	originalTextTransparency: number,
	originalStrokeTransparency: number,
	originalStripTransparency: number,
	originalPosition: UDim2,
}

local activeEntries: { Entry } = {}

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
	local template = idObjects:FindFirstChild("KillData")
	if template and template:IsA("GuiObject") then
		return template
	end
	return nil
end

local function fade(entry: Entry, tweenInfo: TweenInfo, text: number, stroke: number, strip: number)
	TweenService:Create(entry.label, tweenInfo, { TextTransparency = text }):Play()
	if entry.stroke then
		TweenService:Create(entry.stroke, tweenInfo, { Transparency = stroke }):Play()
	end
	if entry.strip then
		TweenService:Create(entry.strip, tweenInfo, { BackgroundTransparency = strip }):Play()
	end
end

local function getFeedFrame(): GuiObject?
	local gui = findGameGui()
	if not gui then return nil end
	local feed = gui:FindFirstChild("Killfeed") or gui:FindFirstChild("KillFeed") or gui:FindFirstChild("killfeed")
	if feed and feed:IsA("GuiObject") then
		return feed
	end
	return nil
end

local function removeEntry(entry: Entry)
	if entry.removing then return end
	entry.removing = true

	for i, e in activeEntries do
		if e == entry then
			table.remove(activeEntries, i)
			break
		end
	end

	local row = entry.row
	if not row or not row.Parent then return end

	local tweenInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	fade(entry, tweenInfo, 1, 1, 1)
	local tween = TweenService:Create(
		row,
		tweenInfo,
		{ Position = entry.originalPosition + UDim2.fromOffset(-SLIDE_OFFSET, 0) }
	)
	tween:Play()
	tween.Completed:Once(function()
		if row then row:Destroy() end
	end)
end

local function animateIn(entry: Entry)
	local row = entry.row
	row.Position = entry.originalPosition + UDim2.fromOffset(SLIDE_OFFSET, 0)
	entry.label.TextTransparency = 1
	if entry.stroke then entry.stroke.Transparency = 1 end
	if entry.strip then entry.strip.BackgroundTransparency = 1 end

	local tweenInfo = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	fade(entry, tweenInfo, entry.originalTextTransparency, entry.originalStrokeTransparency, entry.originalStripTransparency)
	TweenService:Create(row, tweenInfo, { Position = entry.originalPosition }):Play()
end

local function addEntry(text: string)
	local template = getTemplate()
	local feed = getFeedFrame()
	if not template or not feed then return end

	local row = template:Clone()
	local label = row:FindFirstChild("Label")
	if not label or not label:IsA("TextLabel") then
		row:Destroy()
		return
	end
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local strip = row:FindFirstChild("Strip")
	if strip and not strip:IsA("GuiObject") then
		strip = nil
	end

	label.RichText = true
	label.Text = text
	row.Visible = true
	row.Parent = feed

	local entry: Entry = {
		row = row,
		label = label,
		stroke = stroke,
		strip = strip :: GuiObject?,
		removing = false,
		originalTextTransparency = label.TextTransparency,
		originalStrokeTransparency = if stroke then stroke.Transparency else 0,
		originalStripTransparency = if strip then (strip :: GuiObject).BackgroundTransparency else 1,
		originalPosition = row.Position,
	}
	table.insert(activeEntries, entry)

	while #activeEntries > MAX_ENTRIES do
		removeEntry(activeEntries[1])
	end

	animateIn(entry)

	task.delay(DISPLAY_TIME, function()
		removeEntry(entry)
	end)
end

local function formatKillText(killer: string?, victim: string): string
	if killer and killer ~= "" then
		return string.format(
			'<font color="%s">%s</font> <font transparency="%s">shot</font> %s',
			KILLER_COLOR,
			string.upper(killer),
			tostring(VERB_TRANSPARENCY),
			string.upper(victim)
		)
	end
	return string.format('%s <font transparency="%s">eliminated</font>', string.upper(victim), tostring(VERB_TRANSPARENCY))
end

function KillFeedController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local KillFeedRemote = Remotes:WaitForChild("KillFeed") :: RemoteEvent

	KillFeedRemote.OnClientEvent:Connect(function(killer: string?, victim: string)
		addEntry(formatKillText(killer, victim))
	end)
end

return KillFeedController
