local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local DashMath = require(ReplicatedStorage.Shared.DashMath)
local AbilityHUDController = require(script.Parent.AbilityHUDController)
local MovementController = require(script.Parent.MovementController)

-- The dash has no key of its own: tapping a movement key twice inside
-- DASH_DOUBLE_TAP_WINDOW dashes to that key's side of the camera.
local DashController = {}

local DASH = "Dash"

local localPlayer = Players.LocalPlayer
local DashRequestRemote: RemoteEvent
local PlayerStateRemote: RemoteEvent
local RoundStateRemote: RemoteEvent

local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY
local lastDash = 0
local lastTapKey: string? = nil
local lastTapAt = 0

local function canDash(): boolean
	if currentPhase ~= Constants.PHASE_ROUND then return false end
	return localState == Constants.STATE_SAFE
end

-- The way the character is moving, or facing when it stands still.
local function moveDirection(): Vector3?
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = hum and hum.RootPart
	if not hum or not root then return nil end
	if hum.MoveDirection.Magnitude >= 0.1 then
		return DashMath.horizontal(hum.MoveDirection)
	end
	return DashMath.horizontal(root.CFrame.LookVector)
end

-- `direction` is the level unit vector to dash along; without one (the touch
-- button) the dash follows the movement input.
function DashController.tryDash(direction: Vector3?)
	if not canDash() then return end
	direction = direction or moveDirection()
	if not direction then return end
	-- Only Dash has behavior; the key does nothing with another ability equipped.
	if AbilityHUDController.equippedAbility() ~= DASH then return end
	local now = os.clock()
	if now - lastDash < Abilities.params(DASH).cooldown then return end
	lastDash = now
	DashRequestRemote:FireServer(direction)
	MovementController.playDashAnimation(direction)
	AbilityHUDController.triggerCooldown(DASH)
end

local function onKey(keyName: string)
	local side = DashMath.side(keyName)
	if not side then return end
	local now = os.clock()
	local doubleTap = DashMath.isDoubleTap(lastTapKey, lastTapAt, keyName, now)
	lastTapKey = keyName
	lastTapAt = now
	if not doubleTap then return end
	-- A third tap starts over instead of chaining off the second.
	lastTapKey = nil
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local direction = DashMath.direction(side, camera.CFrame.LookVector)
	if direction then
		DashController.tryDash(direction)
	end
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
		onKey(input.KeyCode.Name)
	end)
end

return DashController
