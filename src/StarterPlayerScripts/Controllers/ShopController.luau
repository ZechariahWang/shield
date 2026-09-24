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

-- Modal look (matches the Studio-authored lobby buttons)
local FONT = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local PANEL_COLOR = Color3.fromRGB(20, 12, 8)
local CARD_COLOR = Color3.fromRGB(34, 22, 14)
local TEXT_COLOR = Color3.fromRGB(255, 245, 220)
local ACCENT_COLOR = Color3.fromRGB(255, 159, 80)
local DIM_COLOR = Color3.fromRGB(120, 105, 90)
local MODAL_SIZE = UDim2.fromScale(0.6, 0.65)
local MODAL_POSITION = UDim2.fromScale(0.5, 0.5)
local MODAL_CLOSED_SCALE = 0.85
local MODAL_CLOSED_DRIFT = UDim2.fromScale(0, 0.04)   -- closed pose sits slightly below the open one
local MODAL_OPEN_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local MODAL_CLOSE_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local CARD_SIZE = UDim2.fromScale(0.31, 0.5)
local CARD_PADDING = UDim2.fromScale(0.02, 0.03)

-- Weapon preview camera
local PREVIEW_FOV = 40
local PREVIEW_DISTANCE = 1.15 -- multiples of the model's bounding-box diagonal
local PREVIEW_TILT = 0.35     -- 0 = pure side profile, higher = more three-quarter view

local KIND_WEAPON = "Weapon"
local KIND_ABILITY = "Ability"
local KINDS = { KIND_WEAPON, KIND_ABILITY }
local TAB_TITLES = { [KIND_WEAPON] = "WEAPONS", [KIND_ABILITY] = "ABILITIES" }
local CATALOG_FOLDERS = { [KIND_WEAPON] = "Weapons", [KIND_ABILITY] = "Abilities" }

local MODE_SHOP = "Shop"
local MODE_INVENTORY = "Inventory"

type Item = { kind: string, name: string, template: Instance }
type Card = { item: Item, frame: Frame, price: TextLabel, action: TextButton, cost: number }
type Modal = {
	mode: string,
	frame: Frame,
	scale: UIScale,
	open: boolean,
	animGen: number,
	tabs: { [string]: TextButton },
	grids: { [string]: ScrollingFrame },
	cards: { Card },
	coinsLabel: TextLabel?,
}

local coins = 0
local ownedWeapons: { [string]: boolean } = {}
local ownedAbilities: { [string]: boolean } = {}
local equippedWeapon = Constants.VIEWMODEL_DEFAULT_WEAPON

local modals: { Modal } = {}

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

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, alignment: Enum.TextXAlignment): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.FontFace = FONT
	l.TextColor3 = TEXT_COLOR
	l.TextScaled = true
	l.TextXAlignment = alignment
	l.Text = text
	l.Parent = parent
	return l
end

local function textButton(parent: Instance, text: string, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.FontFace = FONT
	b.TextScaled = true
	b.Text = text
	b.Parent = parent
	return b
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
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

local function buildWeaponPreview(parent: Instance, template: Model)
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 0.55)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.Ambient = Color3.fromRGB(130, 130, 130)
	viewport.Parent = parent

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

local function buildAbilityPreview(parent: Instance, template: Instance)
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.28)
	icon.Size = UDim2.fromScale(0.4, 0.4)
	icon.ScaleType = Enum.ScaleType.Fit
	local source = template:FindFirstChild("AbilityIcon")
	if source and source:IsA("ImageLabel") then
		icon.Image = source.Image
		icon.ImageColor3 = source.ImageColor3
	end
	icon.Parent = parent
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
	local card = Instance.new("Frame")
	card.Name = item.name
	card.BackgroundColor3 = CARD_COLOR
	card.Parent = modal.grids[item.kind]
	corner(card, 6)

	if item.kind == KIND_WEAPON then
		buildWeaponPreview(card, item.template :: Model)
	else
		buildAbilityPreview(card, item.template)
	end
	label(card, item.name, UDim2.fromScale(0.9, 0.14), UDim2.fromScale(0.05, 0.56), Enum.TextXAlignment.Left)
	local price = label(card, "", UDim2.fromScale(0.9, 0.1), UDim2.fromScale(0.05, 0.7), Enum.TextXAlignment.Left)
	price.TextColor3 = ACCENT_COLOR

	local action = textButton(card, "", UDim2.fromScale(0.9, 0.14), UDim2.fromScale(0.05, 0.83))
	action.BackgroundColor3 = ACCENT_COLOR
	action.TextColor3 = PANEL_COLOR
	corner(action, 4)

	local record: Card = { item = item, frame = card, price = price, action = action, cost = itemPrice(item.template) }
	action.Activated:Connect(function()
		onCardActivated(modal, record)
	end)
	table.insert(modal.cards, record)
end

local function refreshCard(modal: Modal, card: Card)
	local owned = isOwned(card.item)
	if modal.mode == MODE_SHOP then
		card.frame.Visible = true
		if owned then
			card.price.Text = "OWNED"
			card.action.Text = "OWNED"
			card.action.BackgroundColor3 = DIM_COLOR
		else
			card.price.Text = card.cost .. " COINS"
			card.action.Text = "BUY"
			card.action.BackgroundColor3 = if coins >= card.cost then ACCENT_COLOR else DIM_COLOR
		end
		return
	end

	card.frame.Visible = owned
	card.price.Text = ""
	if card.item.kind ~= KIND_WEAPON then
		card.action.Text = "OWNED"
		card.action.BackgroundColor3 = DIM_COLOR
	elseif equippedWeapon == card.item.name then
		card.action.Text = "EQUIPPED"
		card.action.BackgroundColor3 = DIM_COLOR
	else
		card.action.Text = "EQUIP"
		card.action.BackgroundColor3 = ACCENT_COLOR
	end
end

local function refreshAll()
	for _, modal in modals do
		if modal.coinsLabel then
			modal.coinsLabel.Text = "COINS " .. coins
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
		modal.tabs[k].TextColor3 = if active then ACCENT_COLOR else DIM_COLOR
	end
end

local function setModalOpen(modal: Modal, open: boolean)
	if modal.open == open then return end
	modal.open = open
	modal.animGen += 1
	local gen = modal.animGen
	local frame = modal.frame

	if open then
		frame.Visible = true
		modal.scale.Scale = MODAL_CLOSED_SCALE
		frame.Position = MODAL_POSITION + MODAL_CLOSED_DRIFT
		TweenService:Create(modal.scale, MODAL_OPEN_TWEEN, { Scale = 1 }):Play()
		TweenService:Create(frame, MODAL_OPEN_TWEEN, { Position = MODAL_POSITION }):Play()
		return
	end

	TweenService:Create(modal.scale, MODAL_CLOSE_TWEEN, { Scale = MODAL_CLOSED_SCALE }):Play()
	local tween = TweenService:Create(frame, MODAL_CLOSE_TWEEN, { Position = MODAL_POSITION + MODAL_CLOSED_DRIFT })
	tween.Completed:Once(function()
		if gen == modal.animGen then
			frame.Visible = false
		end
	end)
	tween:Play()
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

local function buildModal(parent: ScreenGui, title: string, mode: string, items: { Item }): Modal
	local frame = Instance.new("Frame")
	frame.Name = title .. "Modal"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = MODAL_POSITION
	frame.Size = MODAL_SIZE
	frame.BackgroundColor3 = PANEL_COLOR
	frame.Visible = false
	frame.ZIndex = 10
	frame.Parent = parent
	corner(frame, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT_COLOR
	stroke.Thickness = 2
	stroke.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local modal: Modal = {
		mode = mode,
		frame = frame,
		scale = scale,
		open = false,
		animGen = 0,
		tabs = {},
		grids = {},
		cards = {},
		coinsLabel = nil,
	}

	label(frame, title:upper(), UDim2.fromScale(0.26, 0.1), UDim2.fromScale(0.04, 0.03), Enum.TextXAlignment.Left)

	for i, kind in KINDS do
		local tab = textButton(frame, TAB_TITLES[kind], UDim2.fromScale(0.15, 0.06), UDim2.fromScale(0.32 + (i - 1) * 0.16, 0.055))
		tab.BackgroundTransparency = 1
		tab.TextXAlignment = Enum.TextXAlignment.Left
		tab.Activated:Connect(function()
			setTab(modal, kind)
		end)
		modal.tabs[kind] = tab

		local grid = Instance.new("ScrollingFrame")
		grid.Name = kind .. "Grid"
		grid.Size = UDim2.fromScale(0.92, 0.8)
		grid.Position = UDim2.fromScale(0.04, 0.16)
		grid.BackgroundTransparency = 1
		grid.BorderSizePixel = 0
		grid.ScrollBarThickness = 4
		grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
		grid.CanvasSize = UDim2.new()
		grid.Parent = frame
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = CARD_SIZE
		layout.CellPadding = CARD_PADDING
		layout.SortOrder = Enum.SortOrder.Name
		layout.Parent = grid
		modal.grids[kind] = grid
	end

	if mode == MODE_SHOP then
		local coinsLabel = label(frame, "COINS 0", UDim2.fromScale(0.25, 0.07), UDim2.fromScale(0.64, 0.045), Enum.TextXAlignment.Right)
		coinsLabel.TextColor3 = ACCENT_COLOR
		modal.coinsLabel = coinsLabel
	end

	local close = textButton(frame, "X", UDim2.fromScale(0.06, 0.09), UDim2.fromScale(0.97, 0.03))
	close.AnchorPoint = Vector2.new(1, 0)
	close.BackgroundTransparency = 1
	close.TextColor3 = TEXT_COLOR
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
	local buttons = lobbyGui:WaitForChild("Buttons")
	local shopButton = buttons:WaitForChild("ShopButton") :: TextButton
	local inventoryButton = buttons:WaitForChild("InventoryButton") :: TextButton

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	ShopStateRemote = Remotes:WaitForChild("ShopState") :: RemoteEvent
	ShopPurchaseRemote = Remotes:WaitForChild("ShopPurchase") :: RemoteEvent
	ShopEquipRemote = Remotes:WaitForChild("ShopEquip") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	local items = loadItems()
	local shop = buildModal(lobbyGui, "Shop", MODE_SHOP, items)
	local inventory = buildModal(lobbyGui, "Inventory", MODE_INVENTORY, items)
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

	-- Combat takes the mouse, so no modal can stay open into a round.
	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		if phase == Constants.PHASE_REVEAL then
			for _, modal in modals do
				setModalOpen(modal, false)
			end
		end
	end)

	ShopStateRemote:FireServer()
end

return ShopController
