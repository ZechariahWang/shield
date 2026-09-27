local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Settings = require(ReplicatedStorage.Shared.Settings)
local ShopController = require(script.Parent.ShopController)

-- The player's settings on this client: keybinds the input controllers ask
-- about through `matches`, and the mouse sensitivity, applied as
-- UserInputService.MouseDeltaSensitivity (UserGameSettings.MouseSensitivity is
-- off limits to a LocalScript). The record arrives inside ShopState and every
-- edit goes back through SettingsUpdate. Editing (the lobby SETTINGS modal) is
-- PC only.
local SettingsController = {}

local localPlayer = Players.LocalPlayer
local record: Settings.Record = Settings.merge(nil)
local changed = Instance.new("BindableEvent")
SettingsController.Changed = changed.Event

type Row = { value: TextButton }
local rows: { [string]: Row } = {}
local sensitivityRow: Row?
local hints: { [string]: TextLabel } = {}
local modalFrame: Frame
local listening: string? = nil
local SettingsUpdateRemote: RemoteEvent

local ROW_LABELS = { Shoot = "SHOOT", Shield = "SHIELD", Dash = "DASH", Sprint = "SPRINT", Aim = "AIM" }

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
		row.value.Text = if listening == action then "PRESS A KEY" else Settings.displayName(record.keybinds[action])
	end
	if sensitivityRow then
		sensitivityRow.value.Text = string.format("%.1f", record.sensitivity)
	end
end

local function apply(raw: any)
	record = Settings.merge(raw)
	for action, label in hints do
		label.Text = Settings.displayName(record.keybinds[action])
	end
	UserInputService.MouseDeltaSensitivity = record.sensitivity
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

local function stepSensitivity(direction: number)
	local next = record.sensitivity + direction * Constants.SENSITIVITY_STEP
	next = math.round(next * 10) / 10
	record.sensitivity = math.clamp(next, Constants.SENSITIVITY_MIN, Constants.SENSITIVITY_MAX)
	apply(record)
	send()
end

local function onInputWhileListening(input: InputObject)
	local action = listening
	if not action then return end
	if not modalFrame.Visible or input.KeyCode == Enum.KeyCode.Escape then
		listening = nil
		refreshRows()
		return
	end
	local keyName = Settings.keyNameOf(input)
	if not keyName then return end
	listening = nil
	if bindKey(action, keyName) then
		apply(record)
		send()
	else
		refreshRows()
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
	local minus = frame:WaitForChild("Minus") :: TextButton
	local plus = frame:WaitForChild("Plus") :: TextButton
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
	end
	return { value = value }
end

local function buildRows(lobbyGui: ScreenGui)
	local template = lobbyGui:WaitForChild("ID_Objects"):WaitForChild("SettingRow") :: Frame
	local container = modalFrame:WaitForChild("Rows")
	for i, action in Settings.ACTIONS do
		local row = buildRow(template, container, ROW_LABELS[action], i, false)
		rows[action] = row
		row.value.Activated:Connect(function()
			listening = if listening == action then nil else action
			refreshRows()
		end)
	end
	sensitivityRow = buildRow(template, container, "SENSITIVITY", #Settings.ACTIONS + 1, true)
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
	buildRows(lobbyGui)
	local open = ShopController.registerModal(modalFrame)
	ShopController.bindLobbyButton(button, open)
	button.Visible = isPC()
	apply(record)

	ShopStateRemote.OnClientEvent:Connect(function(state: { settings: any })
		apply(state.settings)
	end)
	UserInputService.InputBegan:Connect(onInputWhileListening)
end

return SettingsController
