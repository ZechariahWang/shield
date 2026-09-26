-- Every purchasable item is a ModuleScript under ReplicatedStorage.Items.<Kind>.<Name>
-- returning an ItemData table. Studio-authored children ride along: a weapon's
-- `Model`, an ability's or Robux item's `Icon` ImageLabel.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = {}

Catalog.KIND_WEAPONS = "Weapons"
Catalog.KIND_ABILITIES = "Abilities"
Catalog.KIND_ROBUX = "Robux"
Catalog.KINDS = { Catalog.KIND_WEAPONS, Catalog.KIND_ABILITIES, Catalog.KIND_ROBUX }

export type AbilityParams = {
	cooldown: number,
	duration: number?,
	velocity: number?,
}

export type ItemData = {
	displayName: string,
	price: number?,
	description: string?,
	stats: { { any } }?,
	params: AbilityParams?,
	grip: CFrame?,
	gamePassId: number?,
	productId: number?,
	coins: number?,
}

export type Item = {
	name: string,
	data: ItemData,
	instance: ModuleScript,
}

local cache: { [string]: { Item } }? = nil

local function load(): { [string]: { Item } }
	local byKind: { [string]: { Item } } = {}
	local root = ReplicatedStorage:WaitForChild("Items")
	for _, kind in Catalog.KINDS do
		local list: { Item } = {}
		local folder = root:FindFirstChild(kind)
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("ModuleScript") then
					local ok, data = pcall(require, child)
					if ok and typeof(data) == "table" then
						table.insert(list, { name = child.Name, data = data, instance = child })
					else
						warn("Catalog: " .. child:GetFullName() .. " did not return a table")
					end
				end
			end
		end
		table.sort(list, function(a, b)
			local priceA = a.data.price or 0
			local priceB = b.data.price or 0
			if priceA ~= priceB then return priceA < priceB end
			return a.name < b.name
		end)
		byKind[kind] = list
	end
	return byKind
end

local function all(): { [string]: { Item } }
	if not cache then
		cache = load()
	end
	return cache :: { [string]: { Item } }
end

function Catalog.items(kind: string): { Item }
	return all()[kind] or {}
end

function Catalog.find(kind: string, name: string): Item?
	for _, item in Catalog.items(kind) do
		if item.name == name then return item end
	end
	return nil
end

function Catalog.get(kind: string, name: string): ItemData?
	local item = Catalog.find(kind, name)
	return item and item.data
end

function Catalog.model(kind: string, name: string): Model?
	local item = Catalog.find(kind, name)
	if not item then return nil end
	local model = item.instance:FindFirstChild("Model")
	if model and model:IsA("Model") then return model end
	return nil
end

function Catalog.icon(kind: string, name: string): ImageLabel?
	local item = Catalog.find(kind, name)
	if not item then return nil end
	local icon = item.instance:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then return icon end
	return nil
end

function Catalog.free(kind: string): { string }
	local names: { string } = {}
	for _, item in Catalog.items(kind) do
		if (item.data.price or 0) <= 0 then
			table.insert(names, item.name)
		end
	end
	return names
end

return Catalog
