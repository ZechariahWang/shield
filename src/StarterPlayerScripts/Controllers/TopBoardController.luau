local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- The in-match top kills board under the secondary status pill: one row per
-- leading combatant (headshot, rank, name, kills), read from the Top and
-- Kills_<name> attributes on ReplicatedStorage.MatchScores.
local TopBoardController = {}

local localPlayer = Players.LocalPlayer
local board: Frame
local template: Frame
local rows: { Frame } = {}
local avatars: { [string]: string } = {}
local currentPhase: string = Constants.PHASE_LOBBY

local function avatarUserId(name: string): number?
	local player = Players:FindFirstChild(name)
	if player and player:IsA("Player") then
		return player.UserId
	end
	local bots = Workspace:FindFirstChild("Bots")
	local bot = if bots then bots:FindFirstChild(name) else nil
	if bot then
		return bot:GetAttribute("AvatarUserId")
	end
	return nil
end

local retryPending = false

-- A bot's avatar id lands a moment after its spawn (and is gone while it is
-- dead), so a missing id is looked up again shortly.
local function fetchAvatar(name: string)
	local userId = avatarUserId(name)
	if not userId then
		if retryPending then return end
		retryPending = true
		task.delay(Constants.TOP_BOARD_AVATAR_RETRY, function()
			retryPending = false
			TopBoardController.refresh()
		end)
		return
	end
	avatars[name] = ""
	task.spawn(function()
		local ok, content, ready = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		if ok and ready then
			avatars[name] = content
		else
			avatars[name] = nil
		end
		TopBoardController.refresh()
	end)
end

function TopBoardController.refresh()
	local folder = ReplicatedStorage:FindFirstChild("MatchScores")
	local top = if folder then folder:GetAttribute("Top") else nil
	local names = if typeof(top) == "string" and top ~= "" then string.split(top, ",") else {}
	for index, row in rows do
		local name = names[index]
		row.Visible = name ~= nil
		if not name then continue end
		if avatars[name] == nil then
			fetchAvatar(name)
		end
		local avatar = row:FindFirstChild("Avatar") :: ImageLabel
		local rank = row:FindFirstChild("Rank") :: TextLabel
		local nameLabel = row:FindFirstChild("Name") :: TextLabel
		local kills = row:FindFirstChild("Kills") :: TextLabel
		local templateName = template:FindFirstChild("Name") :: TextLabel
		avatar.Image = avatars[name] or ""
		rank.Text = tostring(index)
		nameLabel.Text = string.upper(name)
		nameLabel.TextColor3 = if name == localPlayer.Name then Constants.TOP_BOARD_SELF_COLOR else templateName.TextColor3
		kills.Text = tostring(folder:GetAttribute("Kills_" .. name) or 0)
	end
	board.Visible = currentPhase == Constants.PHASE_ROUND
end

function TopBoardController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("Game")
	board = gui:WaitForChild("TopBoard")
	template = gui:WaitForChild("ID_Objects"):WaitForChild("TopRow")
	for index = 1, Constants.TOP_BOARD_SIZE do
		local row = template:Clone()
		row.LayoutOrder = index
		row.Parent = board
		rows[index] = row
	end

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		if phase == Constants.PHASE_ROUND then
			table.clear(avatars)
		end
		TopBoardController.refresh()
	end)

	local folder = ReplicatedStorage:WaitForChild("MatchScores")
	folder.AttributeChanged:Connect(TopBoardController.refresh)
	TopBoardController.refresh()
end

return TopBoardController
