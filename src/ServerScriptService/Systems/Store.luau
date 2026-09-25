local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- ponytail: session only. Coins, owned items and the equipped weapon reset on
-- rejoin; back the wallets table with a DataStore once purchases need to persist.
local Store = {}

Store.KIND_WEAPON = "Weapon"
Store.KIND_ABILITY = "Ability"

type Wallet = {
	coins: IntValue,
	ownedWeapons: { [string]: boolean },
	equippedWeapon: string,
	ownedAbilities: { [string]: boolean },
}

local wallets: { [Player]: Wallet } = {}
local ShopStateRemote: RemoteEvent

local CATALOG_FOLDERS = {
	[Store.KIND_WEAPON] = "Weapons",
	[Store.KIND_ABILITY] = "Abilities",
}

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

local function catalogItem(kind: string, name: string): Instance?
	local folderName = CATALOG_FOLDERS[kind]
	if not folderName then return nil end
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	if not folder then return nil end
	return folder:FindFirstChild(name)
end

function Store.price(kind: string, name: string): number
	local item = catalogItem(kind, name)
	if not item then return 0 end
	local price = item:GetAttribute("Price")
	if typeof(price) == "number" then
		return price
	end
	return Constants.SHOP_DEFAULT_PRICE
end

local function names(set: { [string]: boolean }): { string }
	local list: { string } = {}
	for name in set do
		table.insert(list, name)
	end
	return list
end

local function sendState(player: Player)
	local wallet = wallets[player]
	if not wallet then return end
	ShopStateRemote:FireClient(
		player,
		wallet.coins.Value,
		names(wallet.ownedWeapons),
		wallet.equippedWeapon,
		names(wallet.ownedAbilities)
	)
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

	wallets[player] = {
		coins = coins,
		ownedWeapons = { [Constants.VIEWMODEL_DEFAULT_WEAPON] = true },
		equippedWeapon = Constants.VIEWMODEL_DEFAULT_WEAPON,
		ownedAbilities = { [Constants.SHOP_DEFAULT_ABILITY] = true },
	}
	sendState(player)
end

function Store.equipped(player: Player): string
	local wallet = wallets[player]
	if not wallet then return Constants.VIEWMODEL_DEFAULT_WEAPON end
	return wallet.equippedWeapon
end

function Store.addCoins(player: Player, amount: number)
	local wallet = wallets[player]
	if not wallet then return end
	wallet.coins.Value += amount
	sendState(player)
end

local function ownedSet(wallet: Wallet, kind: string): { [string]: boolean }?
	if kind == Store.KIND_WEAPON then return wallet.ownedWeapons end
	if kind == Store.KIND_ABILITY then return wallet.ownedAbilities end
	return nil
end

local function purchase(player: Player, kind: any, name: any)
	local wallet = wallets[player]
	if not wallet or typeof(kind) ~= "string" or typeof(name) ~= "string" then return end
	local owned = ownedSet(wallet, kind)
	if not owned or not catalogItem(kind, name) then return end
	if owned[name] then return end
	local price = Store.price(kind, name)
	if wallet.coins.Value < price then return end
	wallet.coins.Value -= price
	owned[name] = true
	if kind == Store.KIND_WEAPON then
		wallet.equippedWeapon = name
	end
	sendState(player)
end

-- Coin packs are developer products authored as ReplicatedStorage.Robux children
-- with ProductId and Coins attributes. ponytail: no receipt log; coins are session
-- only anyway, so a re-delivered receipt after a crash just grants again.
local function coinPack(productId: number): number?
	local folder = ReplicatedStorage:FindFirstChild("Robux")
	if not folder then return nil end
	for _, item in folder:GetChildren() do
		if item:GetAttribute("ProductId") == productId then
			local amount = item:GetAttribute("Coins")
			if typeof(amount) == "number" then
				return amount
			end
		end
	end
	return nil
end

local function processReceipt(receipt: { PlayerId: number, ProductId: number }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not wallets[player] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local amount = coinPack(receipt.ProductId)
	if not amount then
		warn("Store: no coin pack for product " .. receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Store.addCoins(player, amount)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function equip(player: Player, name: any)
	local wallet = wallets[player]
	if not wallet or typeof(name) ~= "string" then return end
	if not wallet.ownedWeapons[name] then return end
	wallet.equippedWeapon = name
	sendState(player)
end

function Store.init()
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
	Players.PlayerRemoving:Connect(function(player)
		wallets[player] = nil
	end)
end

return Store
