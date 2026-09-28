-- Command-bar check for the shared Settings merge: require(game.ServerScriptService.Systems.SettingsTest)()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local Settings = require(ReplicatedStorage.Shared.Settings)

return function()
	-- Nothing saved: every default.
	local fresh = Settings.merge(nil)
	assert(fresh.sensitivity == Constants.SENSITIVITY_DEFAULT, "fresh sensitivity")
	for action, key in Constants.DEFAULT_KEYBINDS do
		assert(fresh.keybinds[action] == key, "fresh keybind " .. action)
	end

	-- Valid changes are kept, unknown actions are dropped.
	local changed = Settings.merge({ sensitivity = 2.5, keybinds = { Shoot = "F", Sprint = "LeftControl", Fly = "G" } })
	assert(changed.sensitivity == 2.5, "sensitivity kept")
	assert(changed.keybinds.Shoot == "F" and changed.keybinds.Sprint == "LeftControl", "keybinds kept")
	assert(changed.keybinds.Fly == nil, "unknown action dropped")
	assert(changed.keybinds.Shield == Constants.DEFAULT_KEYBINDS.Shield, "untouched action keeps default")

	-- A key name that is not a KeyCode or mouse button, or is reserved, falls back for that action.
	local bad = Settings.merge({ keybinds = { Shoot = "NotAKey", Dash = "Escape", Aim = "Unknown" } })
	assert(bad.keybinds.Shoot == Constants.DEFAULT_KEYBINDS.Shoot, "bad key name")
	assert(bad.keybinds.Dash == Constants.DEFAULT_KEYBINDS.Dash, "escape reserved")
	assert(bad.keybinds.Aim == Constants.DEFAULT_KEYBINDS.Aim, "unknown reserved")

	-- Two actions on one key: the whole set resets rather than guessing.
	local dupe = Settings.merge({ keybinds = { Shoot = "F", Shield = "F", Dash = "G" } })
	for action, key in Constants.DEFAULT_KEYBINDS do
		assert(dupe.keybinds[action] == key, "duplicate resets " .. action)
	end

	-- Sensitivity is clamped, garbage falls back.
	assert(Settings.merge({ sensitivity = 100 }).sensitivity == Constants.SENSITIVITY_MAX, "clamped high")
	assert(Settings.merge({ sensitivity = -1 }).sensitivity == Constants.SENSITIVITY_MIN, "clamped low")
	assert(Settings.merge({ sensitivity = "fast" }).sensitivity == Constants.SENSITIVITY_DEFAULT, "garbage sensitivity")
	assert(Settings.merge("junk").sensitivity == Constants.SENSITIVITY_DEFAULT, "garbage record")

	-- Typed sensitivity: parsed, rounded to a step, clamped; garbage is nil.
	assert(Settings.parseSensitivity("2.5") == 2.5, "typed number")
	assert(Settings.parseSensitivity(" 1.26 ") == 1.3, "typed rounds to a step")
	assert(Settings.parseSensitivity("100") == Constants.SENSITIVITY_MAX, "typed clamped high")
	assert(Settings.parseSensitivity("-3") == Constants.SENSITIVITY_MIN, "typed clamped low")
	assert(Settings.parseSensitivity("fast") == nil, "typed garbage")
	assert(Settings.parseSensitivity("") == nil, "typed empty")
	assert(Settings.parseSensitivity("nan") == nil, "typed nan")

	-- Display names.
	assert(Settings.displayName("MouseButton1") == "LMB", "lmb")
	assert(Settings.displayName("MouseButton2") == "RMB", "rmb")
	assert(Settings.displayName("LeftShift") == "LSHIFT", "lshift")
	assert(Settings.displayName("Q") == "Q", "q")

	-- The merge is a fixed point.
	local again = Settings.merge(changed)
	assert(again.sensitivity == changed.sensitivity and again.keybinds.Shoot == "F", "round trip")

	print("SettingsTest: all checks passed")
end
