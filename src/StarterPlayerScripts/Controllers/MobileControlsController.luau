local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local AbilityHUDController = require(script.Parent.AbilityHUDController)
local CombatController = require(script.Parent.CombatController)
local DashController = require(script.Parent.DashController)

-- Touch stand-ins for LMB, Q and E: the Studio-authored Game.MobileControls
-- buttons call the same functions the keys do. Shown only on a touch device
-- without a keyboard while combat is active.
local MobileControlsController = {}

local localPlayer = Players.LocalPlayer
local frame: Frame
local dashButton: TextButton
local localState = Constants.STATE_LOBBY
local currentPhase = Constants.PHASE_LOBBY

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function reconcile()
	local inArena = currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND
	frame.Visible = isTouchDevice() and inArena and localState == Constants.STATE_SAFE
	dashButton.Visible = AbilityHUDController.equippedAbility() == "Dash"
end

function MobileControlsController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gameGui = playerGui:WaitForChild("Game") :: ScreenGui
	frame = gameGui:WaitForChild("MobileControls") :: Frame
	dashButton = frame:WaitForChild("Dash") :: TextButton
	local shieldButton = frame:WaitForChild("Shield") :: TextButton
	local shootButton = frame:WaitForChild("Shoot") :: TextButton
	frame.Visible = false

	shootButton.Activated:Connect(CombatController.tryShoot)
	shieldButton.Activated:Connect(CombatController.tryToggleShield)
	dashButton.Activated:Connect(DashController.tryDash)

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	local ShopStateRemote = Remotes:WaitForChild("ShopState") :: RemoteEvent
	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
		reconcile()
	end)
	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		reconcile()
	end)
	ShopStateRemote.OnClientEvent:Connect(reconcile)
end

return MobileControlsController
