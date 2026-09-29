local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Settings = require(ReplicatedStorage.Shared.Settings)
local ShopController = require(script.Parent.ShopController)

-- The player's settings on this client: keybinds the input controllers ask
-- about through `matches`, and the aim sensitivity, which MovementController
-- applies as UserInputService.MouseDeltaSensitivity only while the Aim key is
-- held (the rest of the time the stock camera runs on the player's own Roblox
-- sensitivity). The record arrives inside ShopState and every edit goes back
-- through SettingsUpdate. The lobby SETTINGS modal edits
-- sensitivity anywhere (steppers or a typed number); the keybind rows exist
-- only on PC. Rebinding goes through the Confirm overlay twice: first as a
-- yes/no question, then covering the rows while it waits for the key, so no
-- click on the modal's own buttons can be taken as the new key.
local SettingsController = {}

local localPlayer = Players.LocalPlayer
local record: Settings.Record = Settings.merge(nil)
local changed = Instance.new("BindableEvent")
SettingsController.Changed = changed.Event

type Row = { frame: Frame, value: TextButton, input: TextBox }
local rows: { [string]: Row } = {}
local sensitivityRow: Row?
local hints: { [string]: TextLabel } = {}
local modalFrame: Frame
local confirmFrame: Frame
local confirmMessage: TextLabel
local confirmYes: TextButton
local confirmNo: TextButton
local confirmNoPosition: UDim2
local overNo = false
local listening: string? = nil
local confirming: string? = nil
local SettingsUpdateRemote: RemoteEvent

local ROW_LABELS = { Shoot = "SHOOT", Shield = "SHIELD", Dash = "DASH", Sprint = "SPRINT", Aim = "AIM", Slide = "SLIDE" }

function SettingsController.get(): Settings.Record
	return record
end

function SettingsController.matches(input: InputObject, action: string): boolean
	local key = record.keybinds[action]
	return key ~= nil and Settings.inputMatches(input, key)
end

local function isPC(): boolean
	return UserInputService.KeyboardEnabled and UserInputService.MouseEnabled
end

local function refreshRows()
	for action, row in rows do
		row.value.Text = Settings.displayName(record.keybinds[action])
	end
	if sensitivityRow then
		sensitivityRow.input.Text = string.format("%.1f", record.sensitivity)
	end
	confirmFrame.Visible = confirming ~= nil or listening ~= nil
	if confirming then
		confirmMessage.Text = "CHANGE " .. ROW_LABELS[confirming] .. " KEYBIND?"
		confirmYes.Visible = true
		confirmNo.Text = "NO"
		confirmNo.Position = confirmNoPosition
	elseif listening then
		confirmMessage.Text = "PRESS A KEY OR MOUSE BUTTON FOR " .. ROW_LABELS[listening]
		confirmYes.Visible = false
		confirmNo.Text = "CANCEL"
		confirmNo.Position = UDim2.new(0.5, 0, confirmNoPosition.Y.Scale, confirmNoPosition.Y.Offset)
	end
end

local function apply(raw: any)
	record = Settings.merge(raw)
	for action, label in hints do
		label.Text = Settings.displayName(record.keybinds[action])
	end
	refreshRows()
	changed:Fire(record)
end

local function send()
	SettingsUpdateRemote:FireServer(record)
end

-- A key already on another action is refused; the row keeps its old key.
local function bindKey(action: string, keyName: string): boolean
	for other, key in record.keybinds do
		if other ~= action and key == keyName then return false end
	end
	record.keybinds[action] = keyName
	return true
end

local function setSensitivity(value: number)
	record.sensitivity = value
	apply(record)
	send()
end

local function stepSensitivity(direction: number)
	local next = record.sensitivity + direction * Constants.SENSITIVITY_STEP
	setSensitivity(Settings.parseSensitivity(next) or record.sensitivity)
end

-- Garbage in the box goes back to the current value.
local function typeSensitivity(text: string)
	local value = Settings.parseSensitivity(text)
	if value then
		setSensitivity(value)
	else
		refreshRows()
	end
end

local function finishListening(keyName: string)
	local action = listening
	listening = nil
	if action and bindKey(action, keyName) then
		apply(record)
		send()
	else
		refreshRows()
	end
end

-- Keys arrive here; one the GUI already took (typed into a box) never binds.
-- Mouse buttons come through the overlay instead, see resolveConfirm.
local function onKeyWhileListening(input: InputObject, gameProcessed: boolean)
	if not listening or gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local keyName = Settings.keyNameOf(input)
	if keyName then
		finishListening(keyName)
	end
end

-- A mouse button pressed on the overlay while it waits for a key binds, except
-- over the CANCEL button, whose Activated cancels instead.
local function onOverlayInput(input: InputObject)
	if not listening or overNo then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then return end
	local keyName = Settings.keyNameOf(input)
	if keyName then
		finishListening(keyName)
	end
end

local function resolveHints(gameGui: ScreenGui)
	local actions = gameGui:WaitForChild("Actions")
	local meters = actions:WaitForChild("Meters")
	hints.Shield = meters:WaitForChild("ShieldMeter"):WaitForChild("BarBG"):WaitForChild("KeyHint") :: TextLabel
	hints.Shoot = meters:WaitForChild("GunMeter"):WaitForChild("BarBG"):WaitForChild("KeyHint") :: TextLabel
	hints.Dash = actions:WaitForChild("AbilityAction"):WaitForChild("KeyHint") :: TextLabel
end

local function buildRow(template: Frame, parent: Instance, label: string, order: number, withSteppers: boolean): Row
	local frame = template:Clone()
	frame.Name = label
	frame.LayoutOrder = order
	frame.Visible = true
	;(frame:WaitForChild("Label") :: TextLabel).Text = label
	local value = frame:WaitForChild("Value") :: TextButton
	local input = frame:WaitForChild("Input") :: TextBox
	local minus = frame:WaitForChild("Minus") :: TextButton
	local plus = frame:WaitForChild("Plus") :: TextButton
	value.Visible = not withSteppers
	input.Visible = withSteppers
	minus.Visible = withSteppers
	plus.Visible = withSteppers
	frame.Parent = parent
	if withSteppers then
		minus.Activated:Connect(function()
			stepSensitivity(-1)
		end)
		plus.Activated:Connect(function()
			stepSensitivity(1)
		end)
		input.FocusLost:Connect(function()
			typeSensitivity(input.Text)
		end)
	end
	return { frame = frame, value = value, input = input }
end

local function resolveConfirm()
	confirmFrame = modalFrame:WaitForChild("Confirm") :: Frame
	confirmMessage = confirmFrame:WaitForChild("Message") :: TextLabel
	confirmYes = confirmFrame:WaitForChild("Yes") :: TextButton
	confirmNo = confirmFrame:WaitForChild("No") :: TextButton
	confirmNoPosition = confirmNo.Position
	confirmFrame.Visible = false
	confirmYes.Activated:Connect(function()
		listening = confirming
		confirming = nil
		refreshRows()
	end)
	confirmNo.Activated:Connect(function()
		confirming = nil
		listening = nil
		refreshRows()
	end)
	confirmNo.MouseEnter:Connect(function()
		overNo = true
	end)
	confirmNo.MouseLeave:Connect(function()
		overNo = false
	end)
	confirmFrame.InputBegan:Connect(onOverlayInput)
	-- The modal closing (Close, or the lobby UI hiding) drops a pending confirm or listen.
	modalFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if modalFrame.Visible then return end
		confirming = nil
		listening = nil
		refreshRows()
	end)
end

local function buildRows(lobbyGui: ScreenGui)
	local template = lobbyGui:WaitForChild("ID_Objects"):WaitForChild("SettingRow") :: Frame
	local container = modalFrame:WaitForChild("Rows")
	for i, action in Settings.ACTIONS do
		local row = buildRow(template, container, ROW_LABELS[action], i, false)
		row.frame.Visible = isPC()
		rows[action] = row
		row.value.Activated:Connect(function()
			confirming = action
			refreshRows()
		end)
	end
	sensitivityRow = buildRow(template, container, "AIM SENSITIVITY", #Settings.ACTIONS + 1, true)
end

function SettingsController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local lobbyGui = playerGui:WaitForChild("Lobby") :: ScreenGui
	local gameGui = playerGui:WaitForChild("Game") :: ScreenGui
	local button = lobbyGui:WaitForChild("Buttons"):WaitForChild("SettingsButton") :: TextButton
	modalFrame = lobbyGui:WaitForChild("SettingsModal") :: Frame
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	SettingsUpdateRemote = Remotes:WaitForChild("SettingsUpdate") :: RemoteEvent
	local ShopStateRemote = Remotes:WaitForChild("ShopState") :: RemoteEvent

	resolveHints(gameGui)
	resolveConfirm()
	buildRows(lobbyGui)
	local open = ShopController.registerModal(modalFrame)
	ShopController.bindLobbyButton(button, open)
	apply(record)

	ShopStateRemote.OnClientEvent:Connect(function(state: { settings: any })
		apply(state.settings)
	end)
	UserInputService.InputBegan:Connect(onKeyWhileListening)
end

return SettingsController
