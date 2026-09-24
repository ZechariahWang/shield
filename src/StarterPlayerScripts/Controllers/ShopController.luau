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

-- Modal look: the same flat, sharp slab as the Studio-authored lobby buttons
-- (dark warm panel, orange accent bar beside the text, heavy italic type, no strokes).
local FONT = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local PANEL_COLOR = Color3.fromRGB(20, 12, 8)
local PANEL_TRANSPARENCY = 0.05
local CARD_COLOR = Color3.fromRGB(36, 24, 16)
local INSET_COLOR = Color3.fromRGB(14, 9, 6)
local TEXT_COLOR = Color3.fromRGB(255, 245, 220)
local ACCENT_COLOR = Color3.fromRGB(255, 159, 80)             -- shop, matches the SHOP lobby button
local INVENTORY_ACCENT_COLOR = Color3.fromRGB(80, 255, 60)    -- matches the INVENTORY lobby button
local DIM_COLOR = Color3.fromRGB(120, 105, 90)
local MUTED_BUTTON_COLOR = Color3.fromRGB(52, 40, 32)
local UNAFFORDABLE_TRANSPARENCY = 0.55
local SCRIM_TRANSPARENCY = 0.45
local HOVER_LIFT = 0.15 -- how far a hovered button's color moves toward white
local ACCENT_BAR_WIDTH = 4
local MODAL_SIZE = UDim2.fromScale(0.6, 0.65)
local MODAL_POSITION = UDim2.fromScale(0.5, 0.5)
local MODAL_CLOSED_SCALE = 0.85
local MODAL_CLOSED_DRIFT = UDim2.fromScale(0, 0.04)   -- closed pose sits slightly below the open one
local MODAL_OPEN_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local MODAL_CLOSE_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TAB_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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
local TAB_X = { [KIND_WEAPON] = 0.34, [KIND_ABILITY] = 0.5 }
local CATALOG_FOLDERS = { [KIND_WEAPON] = "Weapons", [KIND_ABILITY] = "Abilities" }

local MODE_SHOP = "Shop"
local MODE_INVENTORY = "Inventory"

type Item = { kind: string, name: string, template: Instance }
type Card = { item: Item, frame: Frame, price: TextLabel, action: TextButton, cost: number, baseColor: Color3 }
type Modal = {
	mode: string,
	accent: Color3,
	frame: Frame,
	scale: UIScale,
	open: boolean,
	animGen: number,
	tabs: { [string]: TextButton },
	tabUnderline: Frame,
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
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.FontFace = FONT
	b.TextScaled = true
	b.Text = text
	b.Parent = parent
	return b
end

local function block(parent: Instance, color: Color3, size: UDim2, position: UDim2): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Size = size
	f.Position = position
	f.Parent = parent
	return f
end

-- Text-only buttons (tabs, close) brighten on hover; filled buttons lift their fill.
local function hoverText(button: TextButton, idle: () -> Color3)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_INFO, { TextColor3 = TEXT_COLOR }):Play()
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

local function buildWeaponPreview(parent: Instance, template: Model)
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
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
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.7, 0.7)
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
	local card = block(modal.grids[item.kind], CARD_COLOR, UDim2.new(), UDim2.new())
	card.Name = item.name

	local inset = block(card, INSET_COLOR, UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.05, 0.05))
	if item.kind == KIND_WEAPON then
		buildWeaponPreview(inset, item.template :: Model)
	else
		buildAbilityPreview(inset, item.template)
	end
	label(card, item.name, UDim2.fromScale(0.9, 0.13), UDim2.fromScale(0.05, 0.58), Enum.TextXAlignment.Left)
	local price = label(card, "", UDim2.fromScale(0.9, 0.09), UDim2.fromScale(0.05, 0.71), Enum.TextXAlignment.Left)
	price.TextColor3 = modal.accent

	local action = textButton(card, "", UDim2.fromScale(0.9, 0.13), UDim2.fromScale(0.05, 0.83))
	action.TextColor3 = PANEL_COLOR

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
			styleAction(card, "OWNED", MUTED_BUTTON_COLOR, DIM_COLOR, 0)
		else
			card.price.Text = card.cost .. " COINS"
			local transparency = if coins >= card.cost then 0 else UNAFFORDABLE_TRANSPARENCY
			styleAction(card, "BUY", modal.accent, PANEL_COLOR, transparency)
		end
		return
	end

	card.frame.Visible = owned
	card.price.Text = ""
	if card.item.kind ~= KIND_WEAPON then
		styleAction(card, "OWNED", MUTED_BUTTON_COLOR, DIM_COLOR, 0)
	elseif equippedWeapon == card.item.name then
		styleAction(card, "EQUIPPED", MUTED_BUTTON_COLOR, DIM_COLOR, 0)
	else
		styleAction(card, "EQUIP", modal.accent, PANEL_COLOR, 0)
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
		modal.tabs[k].TextColor3 = if active then TEXT_COLOR else DIM_COLOR
	end
	TweenService:Create(modal.tabUnderline, TAB_TWEEN, { Position = UDim2.fromScale(TAB_X[kind], 0.125) }):Play()
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

local function buildScrim(parent: ScreenGui)
	scrim = textButton(parent, "", UDim2.fromScale(1, 1), UDim2.new())
	scrim.Name = "Scrim"
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 1
	scrim.Visible = false
	scrim.ZIndex = 0 -- under the lobby buttons so they still toggle, above everything else
	scrim.Activated:Connect(closeAll)
end

local function buildModal(parent: ScreenGui, title: string, mode: string, items: { Item }, accent: Color3): Modal
	local frame = block(parent, PANEL_COLOR, MODAL_SIZE, MODAL_POSITION)
	frame.Name = title .. "Modal"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = PANEL_TRANSPARENCY
	frame.Visible = false
	frame.ZIndex = 10
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local underline = block(frame, accent, UDim2.new(0.08, 0, 0, 3), UDim2.fromScale(TAB_X[KIND_WEAPON], 0.125))
	local modal: Modal = {
		mode = mode,
		accent = accent,
		frame = frame,
		scale = scale,
		open = false,
		animGen = 0,
		tabs = {},
		tabUnderline = underline,
		grids = {},
		cards = {},
		coinsLabel = nil,
	}

	block(frame, accent, UDim2.new(0, ACCENT_BAR_WIDTH, 0.08, 0), UDim2.fromScale(0.04, 0.045))
	label(frame, title:upper(), UDim2.fromScale(0.24, 0.08), UDim2.fromScale(0.055, 0.045), Enum.TextXAlignment.Left)

	for _, kind in KINDS do
		local tab = textButton(frame, TAB_TITLES[kind], UDim2.fromScale(0.14, 0.055), UDim2.fromScale(TAB_X[kind], 0.06))
		tab.BackgroundTransparency = 1
		tab.TextXAlignment = Enum.TextXAlignment.Left
		tab.Activated:Connect(function()
			setTab(modal, kind)
		end)
		hoverText(tab, function()
			return if modal.grids[kind].Visible then TEXT_COLOR else DIM_COLOR
		end)
		modal.tabs[kind] = tab

		local grid = Instance.new("ScrollingFrame")
		grid.Name = kind .. "Grid"
		grid.Size = UDim2.fromScale(0.92, 0.78)
		grid.Position = UDim2.fromScale(0.04, 0.17)
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
		local coinsLabel = label(frame, "0", UDim2.fromScale(0.14, 0.06), UDim2.fromScale(0.74, 0.055), Enum.TextXAlignment.Right)
		coinsLabel.TextColor3 = accent
		modal.coinsLabel = coinsLabel
		local coin = block(frame, accent, UDim2.fromOffset(10, 10), UDim2.fromScale(0.89, 0.085))
		coin.AnchorPoint = Vector2.new(0, 0.5)
	end

	local close = textButton(frame, "X", UDim2.fromScale(0.05, 0.07), UDim2.fromScale(0.965, 0.05))
	close.AnchorPoint = Vector2.new(1, 0)
	close.BackgroundTransparency = 1
	close.TextColor3 = DIM_COLOR
	hoverText(close, function()
		return DIM_COLOR
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
	local buttons = lobbyGui:WaitForChild("Buttons")
	local shopButton = buttons:WaitForChild("ShopButton") :: TextButton
	local inventoryButton = buttons:WaitForChild("InventoryButton") :: TextButton

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	ShopStateRemote = Remotes:WaitForChild("ShopState") :: RemoteEvent
	ShopPurchaseRemote = Remotes:WaitForChild("ShopPurchase") :: RemoteEvent
	ShopEquipRemote = Remotes:WaitForChild("ShopEquip") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	local items = loadItems()
	buildScrim(lobbyGui)
	local shop = buildModal(lobbyGui, "Shop", MODE_SHOP, items, ACCENT_COLOR)
	local inventory = buildModal(lobbyGui, "Inventory", MODE_INVENTORY, items, INVENTORY_ACCENT_COLOR)
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
			closeAll()
		end
	end)

	ShopStateRemote:FireServer()
end

return ShopController
