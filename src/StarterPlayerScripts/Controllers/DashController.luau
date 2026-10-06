local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local DashMath = require(ReplicatedStorage.Shared.DashMath)
local AbilityHUDController = require(script.Parent.AbilityHUDController)
local CombatController = require(script.Parent.CombatController)
local MovementController = require(script.Parent.MovementController)

-- The dash has no key of its own: tapping Space twice inside
-- DASH_DOUBLE_TAP_WINDOW dashes toward the crosshair, up or down included.
local DashController = {}

local DASH = "Dash"

local localPlayer = Players.LocalPlayer
local DashRequestRemote: RemoteEvent
local PlayerStateRemote: RemoteEvent
local RoundStateRemote: RemoteEvent

local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY
local lastDash = 0
local lastTapAt = -math.huge

local function canDash(): boolean
	if currentPhase ~= Constants.PHASE_ROUND then return false end
	return localState == Constants.STATE_SAFE
end

-- From the character toward what the crosshair is over.
local function aimDirection(): Vector3?
	local char = localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local direction = CombatController.getAim(root.Position)
	return direction
end

function DashController.tryDash()
	if not canDash() then return end
	-- Only Dash has behavior; the key does nothing with another ability equipped.
	if AbilityHUDController.equippedAbility() ~= DASH then return end
	local now = os.clock()
	if now - lastDash < Abilities.params(DASH).cooldown then return end
	local direction = aimDirection()
	if not direction then return end
	lastDash = now
	DashRequestRemote:FireServer(direction)
	MovementController.playDashAnimation(direction)
	AbilityHUDController.triggerCooldown(DASH)
end

local function onSpace()
	local now = os.clock()
	local doubleTap = DashMath.isDoubleTap(lastTapAt, now)
	lastTapAt = now
	if not doubleTap then return end
	-- A third tap starts over instead of chaining off the second.
	lastTapAt = -math.huge
	DashController.tryDash()
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
		if input.KeyCode == Enum.KeyCode.Space then
			onSpace()
		end
	end)
end

return DashController
