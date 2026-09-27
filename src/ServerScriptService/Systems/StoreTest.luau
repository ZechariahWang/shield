-- Command-bar check for Store's pure logic: require(game.ServerScriptService.Systems.StoreTest)()
local Store = require(script.Parent.Store)

local PRICES = {
	Weapons = { Pistol = 0, M4A1 = 200 },
	Abilities = { Dash = 0, TestAbility = 200 },
}

local function has(list: { string }, name: string): boolean
	return table.find(list, name) ~= nil
end

return function()
	-- A new player (nil record) owns every free item and has them equipped.
	local fresh = Store._merge(nil, PRICES)
	assert(fresh.coins == 0, "fresh coins")
	assert(has(fresh.owned.Weapons, "Pistol") and not has(fresh.owned.Weapons, "M4A1"), "fresh weapons")
	assert(has(fresh.owned.Abilities, "Dash"), "fresh abilities")
	assert(fresh.equipped.Weapons == "Pistol" and fresh.equipped.Abilities == "Dash", "fresh equipped")

	-- A saved record keeps coins and purchases, drops items the catalog no longer has,
	-- and falls back when the equipped item is not owned.
	local merged = Store._merge({
		version = 1,
		coins = 350,
		owned = { Weapons = { "M4A1", "Removed" }, Abilities = {} },
		equipped = { Weapons = "Removed", Abilities = "TestAbility" },
	}, PRICES)
	assert(merged.coins == 350, "merged coins")
	assert(has(merged.owned.Weapons, "M4A1") and has(merged.owned.Weapons, "Pistol"), "merged weapons")
	assert(not has(merged.owned.Weapons, "Removed"), "unknown item dropped")
	assert(merged.equipped.Weapons == "Pistol", "equipped fallback")
	assert(merged.equipped.Abilities == "Dash", "ability fallback")

	-- Garbage in a record falls back to defaults instead of erroring.
	local garbage = Store._merge({ coins = "lots", owned = 5, equipped = "x" }, PRICES)
	assert(garbage.coins == 0 and garbage.equipped.Weapons == "Pistol", "garbage record")

	-- Purchases.
	local record = Store._merge({ coins = 250 }, PRICES)
	assert(not Store._purchase(record, PRICES, "Weapons", "Pistol"), "cannot rebuy owned")
	assert(not Store._purchase(record, PRICES, "Weapons", "Nope"), "unknown item")
	assert(not Store._purchase(record, PRICES, "Robux", "VIP"), "unknown kind")
	assert(Store._purchase(record, PRICES, "Weapons", "M4A1"), "buy M4A1")
	assert(record.coins == 50 and has(record.owned.Weapons, "M4A1"), "coins deducted, item owned")
	assert(record.equipped.Weapons == "M4A1", "bought item equipped")
	assert(not Store._purchase(record, PRICES, "Abilities", "TestAbility"), "insufficient coins")
	assert(record.coins == 50, "failed purchase leaves coins")

	-- Equip.
	assert(Store._equip(record, "Weapons", "Pistol"), "equip owned")
	assert(record.equipped.Weapons == "Pistol", "equipped changed")
	assert(not Store._equip(record, "Abilities", "TestAbility"), "cannot equip unowned")
	assert(not Store._equip(record, "Weapons", 5), "non-string name")

	-- Settings ride in the record and survive the merge; garbage settings fall back.
	local withSettings = Store._merge({ settings = { sensitivity = 2, keybinds = { Shoot = "F" } } }, PRICES)
	assert(withSettings.settings.sensitivity == 2 and withSettings.settings.keybinds.Shoot == "F", "settings merged")
	assert(withSettings.settings.keybinds.Dash == "E", "settings default filled")
	assert(fresh.settings.keybinds.Shoot == "MouseButton1", "fresh settings")
	assert(garbage.settings.sensitivity == 1, "garbage settings")

	-- The save table survives a merge round trip unchanged.
	local again = Store._merge(record, PRICES)
	assert(again.coins == record.coins, "round trip coins")
	assert(#again.owned.Weapons == #record.owned.Weapons, "round trip owned")
	assert(again.equipped.Weapons == record.equipped.Weapons, "round trip equipped")
	assert(again.settings.keybinds.Shoot == record.settings.keybinds.Shoot, "round trip settings")

	print("StoreTest: all passed")
end
