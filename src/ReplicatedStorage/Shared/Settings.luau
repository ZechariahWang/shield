local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- Per-player settings: mouse sensitivity and one key per action. Keys are
-- stored by name (an Enum.KeyCode name or MouseButton1/2/3) so the record is
-- plain data for the DataStore. `merge` is the only way in: it turns any saved
-- or client-sent value into a valid record.
local Settings = {}

export type Record = {
	sensitivity: number,
	keybinds: { [string]: string },
}

local MOUSE_BUTTONS = { MouseButton1 = "LMB", MouseButton2 = "RMB", MouseButton3 = "MMB" }
local RESERVED = { Escape = true, Unknown = true }

Settings.ACTIONS = { "Shoot", "Shield", "Dash", "Sprint", "Aim" }

function Settings.isKeyName(name: any): boolean
	if typeof(name) ~= "string" or RESERVED[name] then return false end
	if MOUSE_BUTTONS[name] then return true end
	local ok, item = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return ok and typeof(item) == "EnumItem"
end

function Settings.displayName(name: string): string
	local mouse = MOUSE_BUTTONS[name]
	if mouse then return mouse end
	local short = name:gsub("^Left", "L"):gsub("^Right", "R")
	return short:upper()
end

-- True when this InputObject is the key or mouse button called `name`.
function Settings.inputMatches(input: InputObject, name: string): boolean
	if MOUSE_BUTTONS[name] then
		return input.UserInputType.Name == name
	end
	return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == name
end

-- The key name an InputObject would be saved as, or nil when it is not bindable.
function Settings.keyNameOf(input: InputObject): string?
	local name = input.UserInputType.Name
	if MOUSE_BUTTONS[name] then return name end
	if input.UserInputType == Enum.UserInputType.Keyboard and Settings.isKeyName(input.KeyCode.Name) then
		return input.KeyCode.Name
	end
	return nil
end

function Settings.merge(raw: any): Record
	local record: Record = { sensitivity = Constants.SENSITIVITY_DEFAULT, keybinds = {} }
	for action, key in Constants.DEFAULT_KEYBINDS do
		record.keybinds[action] = key
	end
	if typeof(raw) ~= "table" then return record end

	if typeof(raw.sensitivity) == "number" and raw.sensitivity == raw.sensitivity then
		record.sensitivity = math.clamp(raw.sensitivity, Constants.SENSITIVITY_MIN, Constants.SENSITIVITY_MAX)
	end

	local rawKeys = if typeof(raw.keybinds) == "table" then raw.keybinds else {}
	for _, action in Settings.ACTIONS do
		if Settings.isKeyName(rawKeys[action]) then
			record.keybinds[action] = rawKeys[action]
		end
	end
	-- Two actions on one key: reset the set rather than guess which one the player meant.
	local seen: { [string]: boolean } = {}
	for _, action in Settings.ACTIONS do
		local key = record.keybinds[action]
		if seen[key] then
			for a, k in Constants.DEFAULT_KEYBINDS do
				record.keybinds[a] = k
			end
			break
		end
		seen[key] = true
	end
	return record
end

return Settings
