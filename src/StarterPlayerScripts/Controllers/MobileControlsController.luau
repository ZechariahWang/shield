local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local AbilityHUDController = require(script.Parent.AbilityHUDController)
local CombatController = require(script.Parent.CombatController)
local DashController = require(script.Parent.DashController)
local MovementController = require(script.Parent.MovementController)

-- Touch stand-ins for the combat inputs: the Studio-authored Game.MobileControls
-- buttons call the same functions the keys do. Sprint and aim are held keys on
-- a keyboard and toggles here (a held button would need a third finger). Shown
-- only on a touch device without a keyboard while combat is active.
local MobileControlsController = {}

local localPlayer = Players.LocalPlayer
local frame: Frame
local dashButton: TextButton
local toggles: { [TextButton]: boolean } = {}
local toggleColors: { [TextButton]: { back: Color3, text: Color3 } } = {}
local localState = Constants.STATE_LOBBY
local currentPhase = Constants.PHASE_LOBBY

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function setToggle(button: TextButton, on: boolean, apply: (boolean) -> ())
	toggles[button] = on
	apply(on)
	-- On: fill and label colors swap.
	local colors = toggleColors[button]
	button.BackgroundColor3 = if on then colors.text else colors.back
	button.TextColor3 = if on then colors.back else colors.text
end

local function bindToggle(button: TextButton, apply: (boolean) -> ())
	toggleColors[button] = { back = button.BackgroundColor3, text = button.TextColor3 }
	toggles[button] = false
	button.Activated:Connect(function()
		setToggle(button, not toggles[button], apply)
	end)
end

local function reconcile()
	local inArena = currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND
	frame.Visible = isTouchDevice() and inArena and localState == Constants.STATE_SAFE
	dashButton.Visible = AbilityHUDController.equippedAbility() == "Dash"
	if not frame.Visible then
		-- A toggle left on must not carry into the lobby or the next round.
		for button in toggles do
			if button.Name == "Sprint" then
				setToggle(button, false, MovementController.setSprintHeld)
			else
				setToggle(button, false, MovementController.setAimHeld)
			end
		end
	end
end

function MobileControlsController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gameGui = playerGui:WaitForChild("Game") :: ScreenGui
	frame = gameGui:WaitForChild("MobileControls") :: Frame
	local function button(name: string): TextButton
		return frame:FindFirstChild(name, true) :: TextButton
	end
	dashButton = button("Dash")
	frame.Visible = false

	button("Shoot").Activated:Connect(CombatController.tryShoot)
	button("Shield").Activated:Connect(CombatController.tryToggleShield)
	dashButton.Activated:Connect(DashController.tryDash)
	bindToggle(button("Sprint"), MovementController.setSprintHeld)
	bindToggle(button("Aim"), MovementController.setAimHeld)

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
