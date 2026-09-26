# Shop, inventory and persistence redesign

Date: 2026-09-26

## Goal

Replace the attribute-driven, session-only shop with a module-driven item catalog, DataStore persistence for coins and items, equippable abilities, equipped indicators in both modals, and a richer weapon preview in the details panel.

## 1. Item catalog

Every purchasable thing is one ModuleScript under `ReplicatedStorage.Items.<Kind>.<Name>`, authored in Rojo as `src/ReplicatedStorage/Items/<Kind>/<Name>/init.luau`. Kinds are the folder names `Weapons`, `Abilities`, `Robux`.

Each item folder carries an `init.meta.json` with `"ignoreUnknownInstances": true` so Studio-authored children survive syncs. The `Items` folder and each kind folder carry the same meta so extra Studio-only items can be added without source.

Module shape (all fields optional except `displayName`):

```lua
return {
	displayName = "Pistol",
	price = 0,                 -- coins; 0 means free and granted on first join. Weapons and abilities only.
	description = "Standard issue sidearm. One clean shot eliminates.",
	stats = { { "Damage", 100 }, { "Range", 200 }, { "Cooldown", "1s" } },  -- ordered pairs, rendered verbatim
	params = { cooldown = 3, duration = 0.2, velocity = 60 },  -- abilities only; replaces Abilities.Params
	grip = CFrame.new(),       -- weapons only; replaces Constants.WEAPON_GRIPS
	gamePassId = 0,            -- Robux only: game pass listing
	productId = 0, coins = 500, -- Robux only: developer product granting coins
}
```

Studio-authored children:

- Weapons: `Model` (the weapon model, welded at spawn and shown in previews).
- Abilities: `Icon` (ImageLabel; image and color are copied to cards, the details panel and the HUD tile).
- Robux: optional `Icon` ImageLabel; otherwise the marketplace icon is used.

`Shared/Catalog.luau` reads the tree once on first use:

- `Catalog.KINDS = { "Weapons", "Abilities", "Robux" }`
- `Catalog.items(kind): { { name, data, instance } }`, sorted by price then name.
- `Catalog.get(kind, name)` returns the module table or nil.
- `Catalog.model(kind, name)` returns the `Model` child or nil.
- `Catalog.icon(kind, name)` returns the `Icon` ImageLabel or nil.
- `Catalog.free(kind)` returns the names with `price == 0`.

`Shared/Abilities.luau` keeps its public surface (`get`, `params`, `AbilityDef`) but sources everything from the catalog. `Abilities.Params`, `Abilities.Categories`, `primaryFor` and `categoryForState` go away; the HUD reads the equipped ability instead.

Removed: `Constants.SHOP_DEFAULT_PRICE`, `Constants.SHOP_DEFAULT_ABILITY`, `Constants.WEAPON_GRIPS`, the `Price` and `Description` attribute paths, the `Weapons`, `Abilities` and `Robux` folders. `Constants.VIEWMODEL_DEFAULT_WEAPON` stays as the fallback when a save names a weapon that no longer exists.

Initial content: `Weapons/Pistol` (free), `Weapons/M4A1`, `Abilities/Dash` (free), `Abilities/TestAbility`, `Robux/VIP` (gamePassId 0), `Robux/500 Coins` (productId 0, coins 500). Descriptions and stats copied from the current Studio attributes; M4A1 and TestAbility priced at 200.

## 2. Persistence (`Systems/Store.luau`)

One `DataStoreService` store named `Constants.STORE_DATASTORE_NAME` (`"PlayerData"`), key `tostring(UserId)`. Saved table, version-tagged:

```lua
{
	version = 1,
	coins = 0,
	owned = { Weapons = { "Pistol" }, Abilities = { "Dash" } },
	equipped = { Weapons = "Pistol", Abilities = "Dash" },
}
```

Lifecycle per player:

1. On join: `GetAsync` with up to `STORE_LOAD_RETRIES` attempts, `STORE_RETRY_DELAY` apart. On success (or a nil record for a new player) build the wallet from the record merged with defaults: every free catalog item is owned, unknown owned names are dropped, an equipped name that is not owned falls back to the first owned item. On repeated failure the wallet is built from defaults and flagged `unsaveable`, and a warning is logged.
2. `leaderstats.Coins` IntValue mirrors the wallet's coins as today.
3. Save: `UpdateAsync` writing the wallet's current table. Runs on `PlayerRemoving`, on `BindToClose` for every remaining player, every `STORE_AUTOSAVE_INTERVAL` seconds, and right after a coin pack receipt. Skipped while `unsaveable`.
4. A wallet marked dirty by any change is what the autosave loop writes; clean wallets are skipped.

Purchases: `ShopPurchase(kind, name)` requires a loaded wallet, a catalog item of that kind with a `price`, not already owned, and enough coins. On success coins drop, the item is owned and becomes equipped (both weapons and abilities).

Equip: `ShopEquip(kind, name)` requires the item owned. Sets `equipped[kind]`.

Coin packs: `ProcessReceipt` returns `NotProcessedYet` until the player's wallet is loaded and saveable, then grants `coins` from the catalog entry with that `productId`, saves, and returns `PurchaseGranted`. This is what makes a granted pack survive a crash.

Public API: `Store.equipped(player, kind)`, `Store.addCoins(player, n)`, `Store.init()`.

Studio: DataStore calls fail without "Enable Studio Access to API Services". The load failure path then makes the session behave as today (defaults, nothing saved) with one warning per player.

## 3. Remotes

- `ShopState` (server to owner): one table `{ coins, owned, equipped }` in the save shape. The client still fires it empty to request a copy.
- `ShopPurchase(kind, name)` unchanged.
- `ShopEquip(kind, name)`: gains `kind`.

Consumers: `RoundManager.setSafe` welds `Catalog.model("Weapons", Store.equipped(player, "Weapons"))` with that item's `grip`. `AbilitySystem` reads the player's equipped ability and only acts when it is `Dash`, using its `params`. On the client `DashController` and `AbilityHUDController` read `equipped.Abilities` from the latest `ShopState`; the HUD tile shows the equipped ability's icon and name, and Q sends `DashRequest` only when Dash is equipped.

## 4. Client (`Controllers/ShopController.luau`)

- Items come from `Catalog.items(kind)`; description, stats and price from the module. The `Abilities.params` stat rows go away because abilities list their stats explicitly.
- Equipped indicator: an `EquippedTag` Frame (accent background, small "EQUIPPED" label) is built in code and parented to the equipped item's card in both modals, and to the details panel preview when that item is selected. Card buttons read `BUY` / `OWNED` in the shop and `EQUIP` / `EQUIPPED` in the inventory for both weapons and abilities.
- Preview: the details-panel weapon viewport spins at `PREVIEW_SPIN_SPEED` degrees per second and can be dragged horizontally to rotate (`PREVIEW_DRAG_SENSITIVITY`); dragging pauses the spin until release. Card previews stay static.
- Robux tab unchanged in behavior; listing data and icons come from the catalog.

## 5. Migration (Studio, via MCP, confirmed before running)

After the new source is synced: move each `ReplicatedStorage.Weapons.<Name>` model to `Items.Weapons.<Name>` renamed `Model`, each `Abilities.<Name>.AbilityIcon` to `Items.Abilities.<Name>` renamed `Icon`, then delete `Weapons`, `Abilities` and `Robux`. `ThirdPersonRigs` and `Remotes` are untouched.

## 6. Testing

`src/ServerScriptService/Systems/StoreTest.luau` (a ModuleScript, run from the command bar with `require(...)()`) asserts the pure logic: default merge drops unknown items and grants free ones, equip falls back when the equipped item is not owned, purchase rejects unowned kinds, insufficient coins and duplicates, and the save table round-trips. `Store` exposes those helpers as `Store._merge`, `Store._purchase` and `Store._equip` operating on plain tables so the test needs no DataStore.

Manual smoke additions: equip an ability in the inventory and see the HUD tile change at Reveal; rejoin and keep coins, items and equipped choices; buy a coin pack in Studio with a real product id and see coins persist.

## Out of scope

Session locking across servers, receipt logs, trading, item rarity, per-item sounds or effects.
