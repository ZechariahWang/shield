local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- ponytail: session only. Coins, owned weapons and the equipped weapon reset on
-- rejoin; back this table with a DataStore once purchases need to persist.
local WeaponStore = {}

type Wallet = {
	coins: IntValue,
	owned: { [string]: boolean },
	equipped: string,
}

local wallets: { [Player]: Wallet } = {}
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

local function weaponTemplate(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("Weapons")
	if not folder then return nil end
	local model = folder:FindFirstChild(name)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

function WeaponStore.price(name: string): number
	local model = weaponTemplate(name)
	if not model then return 0 end
	local price = model:GetAttribute("Price")
	if typeof(price) == "number" then
		return price
	end
	return Constants.SHOP_DEFAULT_WEAPON_PRICE
end

local function sendState(player: Player)
	local wallet = wallets[player]
	if not wallet then return end
	local owned: { string } = {}
	for name in wallet.owned do
		table.insert(owned, name)
	end
	ShopStateRemote:FireClient(player, wallet.coins.Value, owned, wallet.equipped)
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
		owned = { [Constants.VIEWMODEL_DEFAULT_WEAPON] = true },
		equipped = Constants.VIEWMODEL_DEFAULT_WEAPON,
	}
	sendState(player)
end

function WeaponStore.equipped(player: Player): string
	local wallet = wallets[player]
	if not wallet then return Constants.VIEWMODEL_DEFAULT_WEAPON end
	return wallet.equipped
end

function WeaponStore.addCoins(player: Player, amount: number)
	local wallet = wallets[player]
	if not wallet then return end
	wallet.coins.Value += amount
	sendState(player)
end

local function purchase(player: Player, name: any)
	local wallet = wallets[player]
	if not wallet or typeof(name) ~= "string" then return end
	if not weaponTemplate(name) then return end
	if wallet.owned[name] then return end
	local price = WeaponStore.price(name)
	if wallet.coins.Value < price then return end
	wallet.coins.Value -= price
	wallet.owned[name] = true
	wallet.equipped = name
	sendState(player)
end

local function equip(player: Player, name: any)
	local wallet = wallets[player]
	if not wallet or typeof(name) ~= "string" then return end
	if not wallet.owned[name] then return end
	wallet.equipped = name
	sendState(player)
end

function WeaponStore.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	ShopStateRemote = ensureRemote(Remotes, "ShopState")
	local purchaseRemote = ensureRemote(Remotes, "ShopPurchase")
	local equipRemote = ensureRemote(Remotes, "ShopEquip")

	purchaseRemote.OnServerEvent:Connect(purchase)
	equipRemote.OnServerEvent:Connect(equip)
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

return WeaponStore
