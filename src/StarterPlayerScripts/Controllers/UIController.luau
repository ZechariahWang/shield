local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local UIController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local statusLabel: TextLabel?
local secondaryLabel: TextLabel?
local lastMainText = ""
local lastSecondaryText = ""

local currentPhase = Constants.PHASE_LOBBY
local phaseEndTime = 0
local endExtra: any = nil
local playerStates: { [Player]: string } = {}

local WHITE = Color3.fromRGB(240, 240, 240)
local YELLOW = Color3.fromRGB(255, 159, 80)
local RED = Color3.fromRGB(255, 25, 0)
local GREEN = Color3.fromRGB(80, 220, 80)
local CYAN = Color3.fromRGB(120, 220, 255)
local CREAM = Color3.fromRGB(255, 245, 220)

local function colorize(color: Color3, text: string): string
	return string.format(
		"<font color=\"rgb(%d,%d,%d)\">%s</font>",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
		text
	)
end

local function countByState(state: string): number
	local count = 0
	for _, s in playerStates do
		if s == state then
			count += 1
		end
	end
	return count
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function buildMainText(): string
	if currentPhase == Constants.PHASE_LOBBY then
		return colorize(WHITE, "WAITING FOR PLAYERS...")
	elseif currentPhase == Constants.PHASE_INTERMISSION then
		return colorize(YELLOW, "GET READY!")
	elseif currentPhase == Constants.PHASE_REVEAL then
		return colorize(YELLOW, "GET READY!")
	elseif currentPhase == Constants.PHASE_ROUND then
		return colorize(WHITE, "LAST ONE STANDING")
	elseif currentPhase == Constants.PHASE_END then
		if endExtra and typeof(endExtra) == "table" then
			local winners = endExtra.winners
			if typeof(winners) == "table" and #winners > 0 then
				if #winners == 1 then
					return colorize(GREEN, string.upper(winners[1]) .. " SURVIVED!")
				elseif #winners == 2 then
					return colorize(GREEN, string.upper(winners[1]) .. " AND " .. string.upper(winners[2]) .. " SURVIVED!")
				else
					return colorize(GREEN, string.format("%d PLAYERS SURVIVED!", #winners))
				end
			end
		end
		return colorize(WHITE, "ROUND ENDED")
	end
	return ""
end

-- Returns (left, right). Right is only used during Round (the alive count).
local function buildSecondaryText(): (string, string)
	if currentPhase == Constants.PHASE_LOBBY then
		local lobbyCount = countByState(Constants.STATE_LOBBY)
		return colorize(CREAM, string.format("PLAYERS %d/%d", lobbyCount, Constants.MIN_PLAYERS)), ""
	elseif currentPhase == Constants.PHASE_INTERMISSION then
		if phaseEndTime > 0 then
			local remaining = math.max(0, phaseEndTime - os.time())
			local color = if remaining <= 3 then RED else CREAM
			return colorize(color, string.format("STARTING IN %d", math.ceil(remaining))), ""
		end
		return "", ""
	elseif currentPhase == Constants.PHASE_REVEAL then
		if phaseEndTime > 0 then
			local remaining = math.max(0, phaseEndTime - os.time())
			return colorize(YELLOW, string.format("POSITION YOURSELF %d", math.ceil(remaining))), ""
		end
		return colorize(YELLOW, "POSITION YOURSELF"), ""
	elseif currentPhase == Constants.PHASE_ROUND then
		local left = ""
		if phaseEndTime > 0 then
			local remaining = phaseEndTime - os.time()
			local color = if remaining <= 30 then RED else CREAM
			left = colorize(color, formatTime(remaining))
		end
		local safeCount = countByState(Constants.STATE_SAFE)
		local totalCount = safeCount + countByState(Constants.STATE_LOBBY)
		return left, colorize(CREAM, string.format("ALIVE %d/%d", safeCount, totalCount))
	end
	return "", ""
end

local function resolveLabel(frameName: string, labelName: string, cached: TextLabel?): TextLabel?
	if cached and cached.Parent then
		return cached
	end

	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return nil end
	local frame = gameGui:FindFirstChild(frameName)
	if not frame then return nil end
	local label = frame:FindFirstChild(labelName)
	if not label or not label:IsA("TextLabel") then return nil end

	if not label.RichText then
		label.RichText = true
	end
	return label
end

local function updateLoop()
	local newStatus = resolveLabel("StatusFrame", "Status", statusLabel)
	if newStatus ~= statusLabel then
		statusLabel = newStatus
		lastMainText = ""
	end

	local newSecondary = resolveLabel("SecondaryStatus", "Secondary", secondaryLabel)
	if newSecondary ~= secondaryLabel then
		secondaryLabel = newSecondary
		lastSecondaryText = ""
	end

	if statusLabel then
		local text = buildMainText()
		if text ~= lastMainText then
			statusLabel.Text = text
			lastMainText = text
		end
	end

	if secondaryLabel then
		local left, right = buildSecondaryText()
		local pill = secondaryLabel.Parent :: GuiObject
		local aliveLabel = pill:FindFirstChild("Alive")
		local divider = pill:FindFirstChild("Divider")

		-- GUI without the Alive chip: fall back to one joined string.
		if right ~= "" and not (aliveLabel and aliveLabel:IsA("TextLabel")) then
			left = if left ~= "" then left .. "  |  " .. right else right
			right = ""
		end

		local key = left .. "\0" .. right
		if key ~= lastSecondaryText then
			lastSecondaryText = key
			local split = right ~= ""
			secondaryLabel.Text = left
			secondaryLabel.Size = UDim2.new(if split then 0.5 else 1, 0, 1, 0)
			if aliveLabel and aliveLabel:IsA("TextLabel") then
				aliveLabel.Text = right
				aliveLabel.Visible = split
			end
			if divider and divider:IsA("GuiObject") then
				divider.Visible = split
			end
			pill.Visible = left ~= "" or right ~= ""
		end
	end
end

function UIController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent

	RoundStateRemote.OnClientEvent:Connect(function(phase: string, duration: number?, extra: any?)
		currentPhase = phase
		phaseEndTime = if duration then os.time() + duration else 0
		endExtra = extra
	end)

	-- Seed every connected player as Lobby up-front. The server's initial
	-- PlayerStateChanged broadcast can fire before this listener attaches, so
	-- without seeding, the local player wouldn't be counted in the lobby total.
	for _, p in Players:GetPlayers() do
		if playerStates[p] == nil then
			playerStates[p] = Constants.STATE_LOBBY
		end
	end

	Players.PlayerAdded:Connect(function(p)
		if playerStates[p] == nil then
			playerStates[p] = Constants.STATE_LOBBY
		end
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		playerStates[player] = state
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
	end)

	RunService.RenderStepped:Connect(updateLoop)
end

return UIController
