local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ShopController = require(script.Parent.ShopController)

-- The lobby SPAWN button: during a match it sends the local player into the
-- arena. After a death it counts RESPAWN_DELAY down first; the server checks
-- the same delay from its own clock, which started earlier, so a click the
-- button allows is never refused for being early.
local SpawnController = {}

local localPlayer = Players.LocalPlayer
local button: TextButton
local SpawnRequestRemote: RemoteEvent

local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY
local readyAt = 0

local function secondsLeft(): number
	return math.max(0, readyAt - os.clock())
end

local function trySpawn()
	if currentPhase ~= Constants.PHASE_ROUND then return end
	if localState ~= Constants.STATE_LOBBY then return end
	if secondsLeft() > 0 then return end
	SpawnRequestRemote:FireServer()
end

local function refresh()
	local show = currentPhase == Constants.PHASE_ROUND
	if button.Visible ~= show then
		button.Visible = show
	end
	if not show then return end
	local left = secondsLeft()
	local text = "SPAWN"
	if left > 0 then
		text = string.format("SPAWN IN %d", math.ceil(left))
	end
	if button.Text ~= text then
		button.Text = text
	end
end

function SpawnController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local lobbyGui = playerGui:WaitForChild("Lobby") :: ScreenGui
	button = lobbyGui:WaitForChild("Buttons"):WaitForChild("SpawnButton") :: TextButton
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	SpawnRequestRemote = Remotes:WaitForChild("SpawnRequest") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	ShopController.bindLobbyButton(button, trySpawn)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		local diedInMatch = localState == Constants.STATE_SAFE
			and state == Constants.STATE_LOBBY
			and currentPhase == Constants.PHASE_ROUND
		localState = state
		if diedInMatch then
			readyAt = os.clock() + Constants.RESPAWN_DELAY
		end
	end)

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		if phase ~= currentPhase then
			readyAt = 0
		end
		currentPhase = phase
	end)

	RunService.Heartbeat:Connect(refresh)
end

return SpawnController
