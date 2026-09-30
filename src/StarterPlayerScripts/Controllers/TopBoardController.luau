local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- The in-match top kills board under the secondary status pill: one ringed
-- headshot per leading combatant, left to right, read from the Top attribute
-- on ReplicatedStorage.MatchScores.
local TopBoardController = {}

local localPlayer = Players.LocalPlayer
local board: Frame
local template: ImageLabel
local circles: { ImageLabel } = {}
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
	if not board then return end
	local folder = ReplicatedStorage:FindFirstChild("MatchScores")
	local top = if folder then folder:GetAttribute("Top") else nil
	local names = if typeof(top) == "string" and top ~= "" then string.split(top, ",") else {}
	for index, circle in circles do
		local name = names[index]
		circle.Visible = name ~= nil
		if not name then continue end
		if avatars[name] == nil then
			fetchAvatar(name)
		end
		circle.Image = avatars[name] or ""
		local ring = circle:FindFirstChild("Ring") :: UIStroke
		local templateRing = template:FindFirstChild("Ring") :: UIStroke
		ring.Color = if name == localPlayer.Name then Constants.TOP_BOARD_SELF_COLOR else templateRing.Color
	end
	board.Visible = currentPhase == Constants.PHASE_ROUND
end

function TopBoardController.init()
	-- The remote first: the server syncs the phase to a new character at the
	-- moment the StarterGui copies land in PlayerGui, so waiting for the GUI
	-- before listening can miss it.
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		if phase == Constants.PHASE_ROUND then
			table.clear(avatars)
		end
		TopBoardController.refresh()
	end)

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("Game")
	template = gui:WaitForChild("ID_Objects"):WaitForChild("TopAvatar")
	local boardFrame = gui:WaitForChild("TopBoard") :: Frame
	for index = 1, Constants.TOP_BOARD_SIZE do
		local circle = template:Clone()
		circle.LayoutOrder = index
		circle.Parent = boardFrame
		circles[index] = circle
	end
	board = boardFrame

	local folder = ReplicatedStorage:WaitForChild("MatchScores")
	folder.AttributeChanged:Connect(TopBoardController.refresh)
	TopBoardController.refresh()
end

return TopBoardController
