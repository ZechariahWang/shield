local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local Store = {}

Store.SHOP_KINDS = { Catalog.KIND_WEAPONS, Catalog.KIND_ABILITIES }

export type Record = {
	version: number,
	coins: number,
	owned: { [string]: { string } },
	equipped: { [string]: string },
}

type Prices = { [string]: { [string]: number } }

type Wallet = {
	record: Record?,
	coins: IntValue,
	pendingCoins: number,
	dirty: boolean,
	saveable: boolean,
}

local wallets: { [Player]: Wallet } = {}
local dataStore: DataStore? = nil
local dataStoreUnavailable = false
local ShopStateRemote: RemoteEvent

local function ensureRemote(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function prices(): Prices
	local table_: Prices = {}
	for _, kind in Store.SHOP_KINDS do
		table_[kind] = {}
		for _, item in Catalog.items(kind) do
			if typeof(item.data.price) == "number" then
				table_[kind][item.name] = item.data.price
			end
		end
	end
	return table_
end

-- Pure logic, exposed for StoreTest.

function Store._merge(raw: any, known: Prices): Record
	local record: Record = {
		version = 1,
		coins = Constants.SHOP_STARTING_COINS,
		owned = {},
		equipped = {},
	}
	if typeof(raw) ~= "table" then raw = {} end
	if typeof(raw.coins) == "number" and raw.coins >= 0 then
		record.coins = math.floor(raw.coins)
	end
	local rawOwned = if typeof(raw.owned) == "table" then raw.owned else {}
	local rawEquipped = if typeof(raw.equipped) == "table" then raw.equipped else {}

	for kind, items in known do
		local owned: { string } = {}
		for name, price in items do
			local savedList = rawOwned[kind]
			local saved = typeof(savedList) == "table" and table.find(savedList, name) ~= nil
			if price <= 0 or saved then
				table.insert(owned, name)
			end
		end
		table.sort(owned)
		record.owned[kind] = owned

		local equipped = rawEquipped[kind]
		if typeof(equipped) ~= "string" or not table.find(owned, equipped) then
			equipped = if table.find(owned, Constants.VIEWMODEL_DEFAULT_WEAPON) then Constants.VIEWMODEL_DEFAULT_WEAPON else owned[1]
		end
		if equipped then
			record.equipped[kind] = equipped
		end
	end
	return record
end

function Store._purchase(record: Record, known: Prices, kind: any, name: any): boolean
	if typeof(kind) ~= "string" or typeof(name) ~= "string" then return false end
	local items = known[kind]
	if not items then return false end
	local price = items[name]
	if not price then return false end
	local owned = record.owned[kind]
	if table.find(owned, name) then return false end
	if record.coins < price then return false end
	record.coins -= price
	table.insert(owned, name)
	record.equipped[kind] = name
	return true
end

function Store._equip(record: Record, kind: any, name: any): boolean
	if typeof(kind) ~= "string" or typeof(name) ~= "string" then return false end
	local owned = record.owned[kind]
	if not owned or not table.find(owned, name) then return false end
	record.equipped[kind] = name
	return true
end

-- Persistence.

local function key(player: Player): string
	return tostring(player.UserId)
end

local function noteUnavailable(err: any)
	local message = tostring(err)
	-- Studio without API access rejects every call; retrying only delays the defaults.
	if message:find("403") or message:find("Studio") then
		if not dataStoreUnavailable then
			warn("Store: DataStore unavailable, running session only (" .. message .. ")")
		end
		dataStoreUnavailable = true
	end
end

local function loadRaw(player: Player): (any, boolean)
	for attempt = 1, Constants.STORE_LOAD_RETRIES do
		if dataStoreUnavailable or not dataStore then return nil, false end
		local ok, result = pcall(function()
			return (dataStore :: DataStore):GetAsync(key(player))
		end)
		if ok then return result, true end
		noteUnavailable(result)
		if attempt < Constants.STORE_LOAD_RETRIES and not dataStoreUnavailable then
			task.wait(Constants.STORE_RETRY_DELAY)
		end
	end
	warn("Store: could not load data for " .. player.Name .. ", progress this session will not be saved")
	return nil, false
end

local function save(player: Player, wallet: Wallet): boolean
	if not wallet.saveable or not wallet.dirty or not wallet.record or not dataStore then return false end
	local record = wallet.record
	local ok, err = pcall(function()
		(dataStore :: DataStore):UpdateAsync(key(player), function()
			return record
		end)
	end)
	if ok then
		wallet.dirty = false
	else
		warn("Store: save failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

local function sendState(player: Player)
	local wallet = wallets[player]
	if not wallet or not wallet.record then return end
	ShopStateRemote:FireClient(player, {
		coins = wallet.record.coins,
		owned = wallet.record.owned,
		equipped = wallet.record.equipped,
	})
end

local function markDirty(wallet: Wallet)
	wallet.dirty = true
	if wallet.record then
		wallet.coins.Value = wallet.record.coins
	end
end

local function onPlayerAdded(player: Player)
	if wallets[player] then return end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = Constants.SHOP_STARTING_COINS
	coins.Parent = leaderstats
	leaderstats.Parent = player

	local wallet: Wallet = { record = nil, coins = coins, pendingCoins = 0, dirty = false, saveable = false }
	wallets[player] = wallet

	task.spawn(function()
		local raw, ok = loadRaw(player)
		if wallets[player] ~= wallet then return end
		local record = Store._merge(raw, prices())
		record.coins += wallet.pendingCoins
		wallet.pendingCoins = 0
		wallet.record = record
		wallet.saveable = ok
		wallet.dirty = true
		coins.Value = record.coins
		sendState(player)
	end)
end

local function onPlayerRemoving(player: Player)
	local wallet = wallets[player]
	wallets[player] = nil
	if wallet then
		save(player, wallet)
	end
end

function Store.equipped(player: Player, kind: string): string?
	local wallet = wallets[player]
	if wallet and wallet.record then
		return wallet.record.equipped[kind]
	end
	if kind == Catalog.KIND_WEAPONS then
		return Constants.VIEWMODEL_DEFAULT_WEAPON
	end
	return nil
end

function Store.addCoins(player: Player, amount: number)
	local wallet = wallets[player]
	if not wallet then return end
	if not wallet.record then
		wallet.pendingCoins += amount
		return
	end
	wallet.record.coins += amount
	markDirty(wallet)
	sendState(player)
end

local function purchase(player: Player, kind: any, name: any)
	local wallet = wallets[player]
	if not wallet or not wallet.record then return end
	if Store._purchase(wallet.record, prices(), kind, name) then
		markDirty(wallet)
		sendState(player)
	end
end

local function equip(player: Player, kind: any, name: any)
	local wallet = wallets[player]
	if not wallet or not wallet.record then return end
	if Store._equip(wallet.record, kind, name) then
		markDirty(wallet)
		sendState(player)
	end
end

local function coinPack(productId: number): number?
	for _, item in Catalog.items(Catalog.KIND_ROBUX) do
		if item.data.productId == productId and typeof(item.data.coins) == "number" then
			return item.data.coins
		end
	end
	return nil
end

-- Coins are granted and saved before the receipt is confirmed, so a crash in
-- between re-delivers the receipt instead of losing the purchase.
local function processReceipt(receipt: { PlayerId: number, ProductId: number }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local wallet = player and wallets[player]
	if not player or not wallet or not wallet.record or not wallet.saveable then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local amount = coinPack(receipt.ProductId)
	if not amount then
		warn("Store: no coin pack for product " .. receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Store.addCoins(player, amount)
	if not save(player, wallet) then
		Store.addCoins(player, -amount)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function saveAll()
	for player, wallet in wallets do
		save(player, wallet)
	end
end

function Store.init()
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, Constants.STORE_DATASTORE_NAME)
	if ok then
		dataStore = store
	else
		noteUnavailable(store)
		dataStoreUnavailable = true
	end

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	ShopStateRemote = ensureRemote(Remotes, "ShopState")
	local purchaseRemote = ensureRemote(Remotes, "ShopPurchase")
	local equipRemote = ensureRemote(Remotes, "ShopEquip")

	purchaseRemote.OnServerEvent:Connect(purchase)
	equipRemote.OnServerEvent:Connect(equip)
	MarketplaceService.ProcessReceipt = processReceipt
	-- The join-time state can beat the client's controller; the client asks again once it's listening.
	ShopStateRemote.OnServerEvent:Connect(sendState)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(saveAll)

	task.spawn(function()
		while true do
			task.wait(Constants.STORE_AUTOSAVE_INTERVAL)
			saveAll()
		end
	end)
end

return Store
