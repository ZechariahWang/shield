local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- The Tab scoreboard: every player and bot with their kills and deaths this
-- match, from the Kills_<name> / Deaths_<name> attributes on
-- ReplicatedStorage.MatchScores. Tab toggles it; the stock player list is off.
local ScoreboardController = {}

local localPlayer = Players.LocalPlayer
local board: Frame
local rowsFrame: ScrollingFrame
local template: Frame

local function combatantNames(folder: Instance): { string }
	local seen: { [string]: boolean } = {}
	for _, player in Players:GetPlayers() do
		seen[player.Name] = true
	end
	local bots = Workspace:FindFirstChild("Bots")
	if bots then
		for _, bot in bots:GetChildren() do
			seen[bot.Name] = true
		end
	end
	for attribute in folder:GetAttributes() do
		local name = string.match(attribute, "^Kills_(.+)$") or string.match(attribute, "^Deaths_(.+)$")
		if name then
			seen[name] = true
		end
	end
	local names: { string } = {}
	for name in seen do
		table.insert(names, name)
	end
	return names
end

local function refresh()
	if not board.Visible then return end
	local folder = ReplicatedStorage:FindFirstChild("MatchScores")
	if not folder then return end
	local function kills(name: string): number
		return folder:GetAttribute("Kills_" .. name) or 0
	end
	local function deaths(name: string): number
		return folder:GetAttribute("Deaths_" .. name) or 0
	end
	local names = combatantNames(folder)
	table.sort(names, function(a: string, b: string): boolean
		if kills(a) ~= kills(b) then return kills(a) > kills(b) end
		if deaths(a) ~= deaths(b) then return deaths(a) < deaths(b) end
		return a < b
	end)
	for _, row in rowsFrame:GetChildren() do
		if row:IsA("Frame") then
			row:Destroy()
		end
	end
	for index, name in names do
		local row = template:Clone()
		local nameLabel = row:FindFirstChild("Name") :: TextLabel
		local killsLabel = row:FindFirstChild("Kills") :: TextLabel
		local deathsLabel = row:FindFirstChild("Deaths") :: TextLabel
		nameLabel.Text = string.upper(name)
		if name == localPlayer.Name then
			nameLabel.TextColor3 = Constants.TOP_BOARD_SELF_COLOR
		end
		killsLabel.Text = tostring(kills(name))
		deathsLabel.Text = tostring(deaths(name))
		row.LayoutOrder = index
		row.Visible = true
		row.Parent = rowsFrame
	end
end

function ScoreboardController.setOpen(open: boolean)
	board.Visible = open
	refresh()
end

function ScoreboardController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("Game")
	board = gui:WaitForChild("Scoreboard")
	rowsFrame = board:WaitForChild("Rows")
	template = gui:WaitForChild("ID_Objects"):WaitForChild("ScoreRow")

	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Tab then
			ScoreboardController.setOpen(not board.Visible)
		end
	end)

	local folder = ReplicatedStorage:WaitForChild("MatchScores")
	folder.AttributeChanged:Connect(refresh)
	Players.PlayerAdded:Connect(refresh)
	Players.PlayerRemoving:Connect(refresh)
end

return ScoreboardController
