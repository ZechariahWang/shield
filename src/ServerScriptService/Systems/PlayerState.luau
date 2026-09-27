local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local PlayerState = {}

local states: { [Player]: string } = {}
local stateChanged = Instance.new("BindableEvent")
PlayerState.StateChanged = stateChanged.Event

local PlayerStateRemote: RemoteEvent

function PlayerState.set(player: Player, newState: string)
	if states[player] == newState then
		return
	end
	local oldState = states[player]
	states[player] = newState

	if newState == Constants.STATE_SAFE then
		CollectionService:AddTag(player, Constants.IN_ROUND_TAG)
	else
		CollectionService:RemoveTag(player, Constants.IN_ROUND_TAG)
	end

	if PlayerStateRemote then
		PlayerStateRemote:FireAllClients(player, newState)
	end

	stateChanged:Fire(player, oldState, newState)
end

function PlayerState.get(player: Player): string?
	return states[player]
end

function PlayerState.getAllInState(state: string): { Player }
	local result = {}
	for player, s in states do
		if s == state and player.Parent then
			table.insert(result, player)
		end
	end
	return result
end

function PlayerState.countInState(state: string): number
	local count = 0
	for player, s in states do
		if s == state and player.Parent then
			count += 1
		end
	end
	return count
end

function PlayerState.syncTo(target: Player)
	if not PlayerStateRemote then return end
	for player, state in states do
		if player.Parent then
			PlayerStateRemote:FireClient(target, player, state)
		end
	end
end

function PlayerState.init()
	PlayerStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerStateChanged") :: RemoteEvent

	Players.PlayerAdded:Connect(function(player)
		PlayerState.set(player, Constants.STATE_LOBBY)
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		PlayerState.set(player, Constants.STATE_LOBBY)
	end
end

return PlayerState
