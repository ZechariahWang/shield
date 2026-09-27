local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local AbilityHUDController = require(script.Parent.AbilityHUDController)
local MovementController = require(script.Parent.MovementController)

local DashController = {}

local DASH = "Dash"

local localPlayer = Players.LocalPlayer
local DashRequestRemote: RemoteEvent
local PlayerStateRemote: RemoteEvent
local RoundStateRemote: RemoteEvent

local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY
local lastDash = 0

local function canDash(): boolean
	if currentPhase ~= Constants.PHASE_ROUND then return false end
	return localState == Constants.STATE_SAFE
end

local function tryDash()
	if not canDash() then return end
	-- Only Dash has behavior; the key does nothing with another ability equipped.
	if AbilityHUDController.equippedAbility() ~= DASH then return end
	local now = os.clock()
	if now - lastDash < Abilities.params(DASH).cooldown then return end
	lastDash = now
	DashRequestRemote:FireServer()
	MovementController.playDashAnimation()
	AbilityHUDController.triggerCooldown(DASH)
end

function DashController.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	DashRequestRemote = Remotes:WaitForChild("DashRequest") :: RemoteEvent
	PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
	end)

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		local prevPhase = currentPhase
		currentPhase = phase
		-- Stale cooldown shouldn't carry across rounds (matches server-side reset).
		if phase == Constants.PHASE_ROUND and prevPhase ~= Constants.PHASE_ROUND then
			lastDash = 0
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.E then
			tryDash()
		end
	end)
end

return DashController
