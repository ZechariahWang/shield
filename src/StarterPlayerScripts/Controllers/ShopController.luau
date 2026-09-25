local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local ShopController = {}

-- Lobby button feedback
local TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local IDLE_SCALE = 1
local HOVER_SCALE = 1.05
local PRESS_SCALE = 0.95
local IDLE_TRANSPARENCY = 0.25
local HOVER_TRANSPARENCY = 0.05

-- Modal behavior. The look (colors, sizes, fonts) is authored in Studio on
-- Lobby.ShopModal / Lobby.InventoryModal and the Lobby.ID_Objects.ItemCard template;
-- the accent, text, dim and panel colors are read off those instances.
local MUTED_BUTTON_COLOR = Color3.fromRGB(52, 40, 32)
local UNAFFORDABLE_TRANSPARENCY = 0.55
local SCRIM_TRANSPARENCY = 0.45
local HOVER_LIFT = 0.15 -- how far a hovered button's color moves toward white
local MODAL_CLOSED_SCALE = 0.85
local MODAL_CLOSED_DRIFT = UDim2.fromScale(0, 0.04)   -- closed pose sits slightly below the open one
local MODAL_OPEN_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local MODAL_CLOSE_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TAB_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Weapon preview camera
local PREVIEW_FOV = 40
local PREVIEW_DISTANCE = 1.15 -- multiples of the model's bounding-box diagonal
local PREVIEW_TILT = 0.35     -- 0 = pure side profile, higher = more three-quarter view

local KIND_WEAPON = "Weapon"
local KIND_ABILITY = "Ability"
local KINDS = { KIND_WEAPON, KIND_ABILITY }
local TAB_NAMES = { [KIND_WEAPON] = "WeaponsTab", [KIND_ABILITY] = "AbilitiesTab" }
local GRID_NAMES = { [KIND_WEAPON] = "WeaponGrid", [KIND_ABILITY] = "AbilityGrid" }
local CATALOG_FOLDERS = { [KIND_WEAPON] = "Weapons", [KIND_ABILITY] = "Abilities" }

local MODE_SHOP = "Shop"
local MODE_INVENTORY = "Inventory"

type Item = { kind: string, name: string, template: Instance }
type Card = { item: Item, frame: Frame, price: TextLabel, action: TextButton, cost: number, baseColor: Color3 }
type Modal = {
	mode: string,
	accent: Color3,
	textColor: Color3,
	dimColor: Color3,
	panelColor: Color3,
	frame: Frame,
	scale: UIScale,
	openPosition: UDim2,
	open: boolean,
	animGen: number,
	tabs: { [string]: TextButton },
	tabUnderline: GuiObject,
	grids: { [string]: ScrollingFrame },
	cards: { Card },
	coinsLabel: TextLabel?,
}

local coins = 0
local ownedWeapons: { [string]: boolean } = {}
local ownedAbilities: { [string]: boolean } = {}
local equippedWeapon = Constants.VIEWMODEL_DEFAULT_WEAPON

local modals: { Modal } = {}
local scrim: TextButton
local scrimGen = 0
local lobbyButtons: GuiObject
local cardTemplate: Frame
local localState = Constants.STATE_LOBBY

local ShopStateRemote: RemoteEvent
local ShopPurchaseRemote: RemoteEvent
local ShopEquipRemote: RemoteEvent

local function bindLobbyButton(button: TextButton, onClick: () -> ())
	local scale = button:WaitForChild("UIScale") :: UIScale
	local hovering = false
	local pressing = false
	local function refresh()
		local targetScale = IDLE_SCALE
		if pressing then
			targetScale = PRESS_SCALE
		elseif hovering then
			targetScale = HOVER_SCALE
		end
		local targetTransparency = if hovering or pressing then HOVER_TRANSPARENCY else IDLE_TRANSPARENCY
		TweenService:Create(scale, TWEEN_INFO, { Scale = targetScale }):Play()
		TweenService:Create(button, TWEEN_INFO, { BackgroundTransparency = targetTransparency }):Play()
	end
	button.MouseEnter:Connect(function()
		hovering = true
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		pressing = false
		refresh()
	end)
	button.MouseButton1Down:Connect(function()
		pressing = true
		refresh()
	end)
	button.MouseButton1Up:Connect(function()
		pressing = false
		refresh()
	end)
	button.Activated:Connect(onClick)
end

-- Text-only buttons (tabs, close) brighten on hover; filled buttons lift their fill.
local function hoverText(button: TextButton, hover: Color3, idle: () -> Color3)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_INFO, { TextColor3 = hover }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_INFO, { TextColor3 = idle() }):Play()
	end)
end

local function itemPrice(template: Instance): number
	local price = template:GetAttribute("Price")
	if typeof(price) == "number" then
		return price
	end
	return Constants.SHOP_DEFAULT_PRICE
end

local function isOwned(item: Item): boolean
	if item.kind == KIND_WEAPON then
		return ownedWeapons[item.name] == true
	end
	return ownedAbilities[item.name] == true
end

local function loadItems(): { Item }
	local items: { Item } = {}
	for _, kind in KINDS do
		local folder = ReplicatedStorage:FindFirstChild(CATALOG_FOLDERS[kind])
		if not folder then continue end
		for _, template in folder:GetChildren() do
			local isWeapon = kind == KIND_WEAPON and template:IsA("Model")
			local isAbility = kind == KIND_ABILITY and template:IsA("Folder")
			if isWeapon or isAbility then
				table.insert(items, { kind = kind, name = template.Name, template = template })
			end
		end
	end
	return items
end

local function fillWeaponPreview(viewport: ViewportFrame, template: Model)
	local model = template:Clone()
	model.Parent = viewport
	local box, size = model:GetBoundingBox()

	-- Look along the thinnest axis so a gun shows its side profile.
	local axis = Vector3.zAxis
	if size.X <= size.Y and size.X <= size.Z then
		axis = Vector3.xAxis
	elseif size.Y <= size.Z then
		axis = Vector3.yAxis
	end
	local viewDirection = box:VectorToWorldSpace((axis + Vector3.one * PREVIEW_TILT).Unit)
	local distance = size.Magnitude * PREVIEW_DISTANCE

	local camera = Instance.new("Camera")
	camera.FieldOfView = PREVIEW_FOV
	camera.CFrame = CFrame.lookAt(box.Position + viewDirection * distance, box.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function fillAbilityIcon(icon: ImageLabel, template: Instance)
	local source = template:FindFirstChild("AbilityIcon")
	if source and source:IsA("ImageLabel") then
		icon.Image = source.Image
		icon.ImageColor3 = source.ImageColor3
	end
end

local function onCardActivated(modal: Modal, card: Card)
	local item = card.item
	if modal.mode == MODE_SHOP then
		if not isOwned(item) then
			ShopPurchaseRemote:FireServer(item.kind, item.name)
		end
		return
	end
	if item.kind == KIND_WEAPON and isOwned(item) and equippedWeapon ~= item.name then
		ShopEquipRemote:FireServer(item.name)
	end
end

local function buildCard(modal: Modal, item: Item)
	local card = cardTemplate:Clone()
	card.Name = item.name

	local inset = card:WaitForChild("Inset")
	local preview = inset:WaitForChild("Preview") :: ViewportFrame
	local icon = inset:WaitForChild("Icon") :: ImageLabel
	if item.kind == KIND_WEAPON then
		fillWeaponPreview(preview, item.template :: Model)
		icon.Visible = false
	else
		fillAbilityIcon(icon, item.template)
		preview.Visible = false
	end
	local nameLabel = card:WaitForChild("ItemName") :: TextLabel
	nameLabel.Text = item.name
	local price = card:WaitForChild("Price") :: TextLabel
	price.TextColor3 = modal.accent
	local action = card:WaitForChild("Action") :: TextButton

	local record: Card = { item = item, frame = card, price = price, action = action, cost = itemPrice(item.template), baseColor = modal.accent }
	action.Activated:Connect(function()
		onCardActivated(modal, record)
	end)
	action.MouseEnter:Connect(function()
		TweenService:Create(action, TWEEN_INFO, { BackgroundColor3 = record.baseColor:Lerp(Color3.new(1, 1, 1), HOVER_LIFT) }):Play()
	end)
	action.MouseLeave:Connect(function()
		TweenService:Create(action, TWEEN_INFO, { BackgroundColor3 = record.baseColor }):Play()
	end)
	table.insert(modal.cards, record)
	card.Parent = modal.grids[item.kind]
end

local function styleAction(card: Card, text: string, color: Color3, textColor: Color3, transparency: number)
	card.action.Text = text
	card.baseColor = color
	card.action.BackgroundColor3 = color
	card.action.TextColor3 = textColor
	card.action.BackgroundTransparency = transparency
end

local function refreshCard(modal: Modal, card: Card)
	local owned = isOwned(card.item)
	if modal.mode == MODE_SHOP then
		card.frame.Visible = true
		if owned then
			card.price.Text = "OWNED"
			styleAction(card, "OWNED", MUTED_BUTTON_COLOR, modal.dimColor, 0)
		else
			card.price.Text = card.cost .. " COINS"
			local transparency = if coins >= card.cost then 0 else UNAFFORDABLE_TRANSPARENCY
			styleAction(card, "BUY", modal.accent, modal.panelColor, transparency)
		end
		return
	end

	card.frame.Visible = owned
	card.price.Text = ""
	if card.item.kind ~= KIND_WEAPON then
		styleAction(card, "OWNED", MUTED_BUTTON_COLOR, modal.dimColor, 0)
	elseif equippedWeapon == card.item.name then
		styleAction(card, "EQUIPPED", MUTED_BUTTON_COLOR, modal.dimColor, 0)
	else
		styleAction(card, "EQUIP", modal.accent, modal.panelColor, 0)
	end
end

local function refreshAll()
	for _, modal in modals do
		if modal.coinsLabel then
			modal.coinsLabel.Text = tostring(coins)
		end
		for _, card in modal.cards do
			refreshCard(modal, card)
		end
	end
end

local function setTab(modal: Modal, kind: string)
	for _, k in KINDS do
		local active = k == kind
		modal.grids[k].Visible = active
		modal.tabs[k].TextColor3 = if active then modal.textColor else modal.dimColor
	end
	local target = UDim2.new(modal.tabs[kind].Position.X, modal.tabUnderline.Position.Y)
	TweenService:Create(modal.tabUnderline, TAB_TWEEN, { Position = target }):Play()
end

local function updateScrim()
	local anyOpen = false
	for _, modal in modals do
		if modal.open then anyOpen = true end
	end
	scrimGen += 1
	local gen = scrimGen
	if anyOpen then
		scrim.Visible = true
		TweenService:Create(scrim, MODAL_OPEN_TWEEN, { BackgroundTransparency = SCRIM_TRANSPARENCY }):Play()
		return
	end
	local tween = TweenService:Create(scrim, MODAL_CLOSE_TWEEN, { BackgroundTransparency = 1 })
	tween.Completed:Once(function()
		if gen == scrimGen then
			scrim.Visible = false
		end
	end)
	tween:Play()
end

local function setModalOpen(modal: Modal, open: boolean)
	if modal.open == open then return end
	modal.open = open
	modal.animGen += 1
	local gen = modal.animGen
	local frame = modal.frame
	updateScrim()

	if open then
		frame.Visible = true
		modal.scale.Scale = MODAL_CLOSED_SCALE
		frame.Position = modal.openPosition + MODAL_CLOSED_DRIFT
		TweenService:Create(modal.scale, MODAL_OPEN_TWEEN, { Scale = 1 }):Play()
		TweenService:Create(frame, MODAL_OPEN_TWEEN, { Position = modal.openPosition }):Play()
		return
	end

	TweenService:Create(modal.scale, MODAL_CLOSE_TWEEN, { Scale = MODAL_CLOSED_SCALE }):Play()
	local tween = TweenService:Create(frame, MODAL_CLOSE_TWEEN, { Position = modal.openPosition + MODAL_CLOSED_DRIFT })
	tween.Completed:Once(function()
		if gen == modal.animGen then
			frame.Visible = false
		end
	end)
	tween:Play()
end

local function closeAll()
	for _, modal in modals do
		setModalOpen(modal, false)
	end
end

local function openModal(target: Modal)
	for _, modal in modals do
		if modal ~= target then
			setModalOpen(modal, false)
		end
	end
	setModalOpen(target, true)
end

local function toggleModal(target: Modal)
	if target.open then
		setModalOpen(target, false)
	else
		openModal(target)
	end
end

-- The lobby UI exists only for players standing in the lobby: the state flips to
-- Lobby on elimination and after the round-end teleport, and to Safe at Reveal.
local function reconcileLobbyUI()
	local inLobby = localState == Constants.STATE_LOBBY
	lobbyButtons.Visible = inLobby
	if not inLobby then
		closeAll()
	end
end

local function resolveScrim(lobbyGui: ScreenGui)
	scrim = lobbyGui:WaitForChild("Scrim") :: TextButton
	scrim.BackgroundTransparency = 1
	scrim.Visible = false
	scrim.Activated:Connect(closeAll)
end

local function resolveModal(lobbyGui: ScreenGui, name: string, mode: string, items: { Item }): Modal
	local frame = lobbyGui:WaitForChild(name) :: Frame
	local title = frame:WaitForChild("Title") :: TextLabel
	local close = frame:WaitForChild("Close") :: TextButton
	local modal: Modal = {
		mode = mode,
		accent = (frame:WaitForChild("Accent") :: GuiObject).BackgroundColor3,
		textColor = title.TextColor3,
		dimColor = close.TextColor3,
		panelColor = frame.BackgroundColor3,
		frame = frame,
		scale = frame:WaitForChild("UIScale") :: UIScale,
		openPosition = frame.Position,
		open = false,
		animGen = 0,
		tabs = {},
		tabUnderline = frame:WaitForChild("TabUnderline") :: GuiObject,
		grids = {},
		cards = {},
		coinsLabel = frame:FindFirstChild("Coins") :: TextLabel?,
	}
	frame.Visible = false
	modal.scale.Scale = 1

	for _, kind in KINDS do
		local tab = frame:WaitForChild(TAB_NAMES[kind]) :: TextButton
		tab.Activated:Connect(function()
			setTab(modal, kind)
		end)
		hoverText(tab, modal.textColor, function()
			return if modal.grids[kind].Visible then modal.textColor else modal.dimColor
		end)
		modal.tabs[kind] = tab
		modal.grids[kind] = frame:WaitForChild(GRID_NAMES[kind]) :: ScrollingFrame
	end

	hoverText(close, modal.textColor, function()
		return modal.dimColor
	end)
	close.Activated:Connect(function()
		setModalOpen(modal, false)
	end)

	for _, item in items do
		buildCard(modal, item)
	end
	setTab(modal, KIND_WEAPON)
	table.insert(modals, modal)
	return modal
end

function ShopController.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local lobbyGui = playerGui:WaitForChild("Lobby") :: ScreenGui
	lobbyButtons = lobbyGui:WaitForChild("Buttons") :: GuiObject
	local shopButton = lobbyButtons:WaitForChild("ShopButton") :: TextButton
	local inventoryButton = lobbyButtons:WaitForChild("InventoryButton") :: TextButton
	local idObjects = lobbyGui:WaitForChild("ID_Objects")
	cardTemplate = idObjects:WaitForChild("ItemCard") :: Frame

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	ShopStateRemote = Remotes:WaitForChild("ShopState") :: RemoteEvent
	ShopPurchaseRemote = Remotes:WaitForChild("ShopPurchase") :: RemoteEvent
	ShopEquipRemote = Remotes:WaitForChild("ShopEquip") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent

	local items = loadItems()
	resolveScrim(lobbyGui)
	local shop = resolveModal(lobbyGui, "ShopModal", MODE_SHOP, items)
	local inventory = resolveModal(lobbyGui, "InventoryModal", MODE_INVENTORY, items)
	bindLobbyButton(shopButton, function()
		toggleModal(shop)
	end)
	bindLobbyButton(inventoryButton, function()
		toggleModal(inventory)
	end)
	refreshAll()

	ShopStateRemote.OnClientEvent:Connect(function(newCoins: number, weaponList: { string }, newEquipped: string, abilityList: { string })
		coins = newCoins
		ownedWeapons = {}
		for _, name in weaponList do
			ownedWeapons[name] = true
		end
		ownedAbilities = {}
		for _, name in abilityList do
			ownedAbilities[name] = true
		end
		equippedWeapon = newEquipped
		refreshAll()
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= Players.LocalPlayer then return end
		localState = state
		reconcileLobbyUI()
	end)

	ShopStateRemote:FireServer()
end

return ShopController
