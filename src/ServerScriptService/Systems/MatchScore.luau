local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- Kills per combatant for the running match, keyed by name (a player's name, a
-- bot's generated name). The scores replicate as attributes on the
-- ReplicatedStorage.MatchScores folder: Kills_<name> per combatant plus
-- LeaderName and LeaderKills, and Top (the TOP_BOARD_SIZE leading names, comma
-- joined), so clients and late joiners need no remote.
local MatchScore = {}

export type State = {
	kills: { [string]: number },
	reachedAt: { [string]: number }, -- the kill number, match wide, that brought the name to its current count
	sequence: number,
}

local FOLDER_NAME = "MatchScores"
local KILLS_PREFIX = "Kills_"

local state: State
local folder: Folder

function MatchScore._new(): State
	return { kills = {}, reachedAt = {}, sequence = 0 }
end

function MatchScore._addKill(board: State, name: string)
	board.sequence += 1
	board.kills[name] = (board.kills[name] or 0) + 1
	board.reachedAt[name] = board.sequence
end

function MatchScore._kills(board: State, name: string): number
	return board.kills[name] or 0
end

-- The top scorer and their kills, or nil and 0 when nobody has scored. A tie
-- goes to whoever reached the count first.
function MatchScore._leader(board: State): (string?, number)
	local bestName: string? = nil
	local bestKills = 0
	local bestReachedAt = math.huge
	for name, kills in board.kills do
		local reachedAt = board.reachedAt[name]
		local ahead = kills > bestKills
		local tiedButEarlier = kills == bestKills and reachedAt < bestReachedAt
		if ahead or tiedButEarlier then
			bestName = name
			bestKills = kills
			bestReachedAt = reachedAt
		end
	end
	return bestName, bestKills
end

-- The top n names: kills descending, a tie to whoever reached the count first.
function MatchScore._top(board: State, n: number): { string }
	local names: { string } = {}
	for name in board.kills do
		table.insert(names, name)
	end
	table.sort(names, function(a: string, b: string): boolean
		if board.kills[a] ~= board.kills[b] then
			return board.kills[a] > board.kills[b]
		end
		return board.reachedAt[a] < board.reachedAt[b]
	end)
	while #names > n do
		table.remove(names)
	end
	return names
end

function MatchScore._targetReached(board: State): boolean
	local _, kills = MatchScore._leader(board)
	return kills >= Constants.KILL_TARGET
end

local function publishLeader()
	local name, kills = MatchScore._leader(state)
	folder:SetAttribute("LeaderName", name)
	folder:SetAttribute("LeaderKills", kills)
	folder:SetAttribute("Top", table.concat(MatchScore._top(state, Constants.TOP_BOARD_SIZE), ","))
end

function MatchScore.reset()
	state = MatchScore._new()
	for attribute in folder:GetAttributes() do
		folder:SetAttribute(attribute, nil)
	end
	publishLeader()
end

function MatchScore.addKill(name: string)
	MatchScore._addKill(state, name)
	folder:SetAttribute(KILLS_PREFIX .. name, state.kills[name])
	publishLeader()
end

function MatchScore.leader(): (string?, number)
	return MatchScore._leader(state)
end

function MatchScore.targetReached(): boolean
	return MatchScore._targetReached(state)
end

function MatchScore.init()
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	MatchScore.reset()
end

return MatchScore
