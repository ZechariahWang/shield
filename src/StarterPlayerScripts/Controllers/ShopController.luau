local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
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
-- Lobby.ShopModal / Lobby.InventoryModal and the Lobby.ID_Objects templates;
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

-- Equipped tag built into each card's Inset and the details preview
local TAG_SIZE = UDim2.fromScale(0.48, 0.14)
local TAG_TEXT = "EQUIPPED"

-- Weapon preview camera
local PREVIEW_FOV = 40
local PREVIEW_DISTANCE = 1.15 -- multiples of the model's bounding-box diagonal
local PREVIEW_TILT = 0.35     -- 0 = pure side profile, higher = more three-quarter view
local PREVIEW_SPIN_SPEED = 30       -- degrees per second the details preview turns on its own
local PREVIEW_DRAG_SENSITIVITY = 0.5 -- degrees per pixel dragged across the details preview

local KINDS = Catalog.KINDS
local TAB_NAMES = { [Catalog.KIND_WEAPONS] = "WeaponsTab", [Catalog.KIND_ABILITIES] = "AbilitiesTab", [Catalog.KIND_ROBUX] = "RobuxTab" }
local GRID_NAMES = { [Catalog.KIND_WEAPONS] = "WeaponGrid", [Catalog.KIND_ABILITIES] = "AbilityGrid", [Catalog.KIND_ROBUX] = "RobuxGrid" }

local MODE_SHOP = "Shop"
local MODE_INVENTORY = "Inventory"

type RobuxInfo = { price: number?, icon: string?, description: string? }
type Item = { kind: string, name: string, data: Catalog.ItemData, passId: number?, productId: number?, info: RobuxInfo? }
type Card = { item: Item, frame: GuiButton, price: TextLabel, action: TextButton, icon: ImageLabel, tag: Frame, cost: number, baseColor: Color3 }
type Spin = { focus: Vector3, baseDirection: Vector3, distance: number, angle: number, dragging: boolean }
type Panel = {
	placeholder: GuiObject,
	content: GuiObject,
	viewport: ViewportFrame,
	icon: ImageLabel,
	tag: Frame,
	name: TextLabel,
	description: TextLabel,
	stats: GuiObject,
	price: TextLabel,
	action: TextButton,
	spin: Spin?,
}
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
	kinds: { string },
	tabs: { [string]: TextButton },
	tabUnderline: GuiObject,
	grids: { [string]: ScrollingFrame },
	cards: { Card },
	coinsLabel: TextLabel?,
	panel: Panel?,
	selected: Card?,
}

local localPlayer = Players.LocalPlayer
local coins = 0
local owned: { [string]: { string } } = {}
local equipped: { [string]: string } = {}
local ownedPasses: { [number]: boolean } = {}

local modals: { Modal } = {}
local scrim: TextButton
local scrimGen = 0
local lobbyButtons: GuiObject
local cardTemplate: GuiButton
local statRowTemplate: GuiObject?
local localState = Constants.STATE_LOBBY

local ShopStateRemote: RemoteEvent
local ShopPurchaseRemote: RemoteEvent
local ShopEquipRemote: RemoteEvent

local refreshAll: () -> ()

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

local function hoverLift(button: TextButton, base: () -> Color3)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TWEEN_INFO, { BackgroundColor3 = base():Lerp(Color3.new(1, 1, 1), HOVER_LIFT) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TWEEN_INFO, { BackgroundColor3 = base() }):Play()
	end)
end

local function isOwned(item: Item): boolean
	if item.kind == Catalog.KIND_ROBUX then
		return item.passId ~= nil and ownedPasses[item.passId] == true
	end
	local list = owned[item.kind]
	return list ~= nil and table.find(list, item.name) ~= nil
end

local function isEquipped(item: Item): boolean
	return equipped[item.kind] == item.name
end

local function fetchRobuxInfo(item: Item)
	local id = item.passId or item.productId
	if not id or id <= 0 then return end
	local infoType = if item.passId then Enum.InfoType.GamePass else Enum.InfoType.Product
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
		if not ok or typeof(info) ~= "table" then return end
		local iconId = info.IconImageAssetId
		item.info = {
			price = info.PriceInRobux,
			icon = if typeof(iconId) == "number" and iconId > 0 then "rbxassetid://" .. iconId else nil,
			description = info.Description,
		}
		refreshAll()
	end)
	if item.passId then
		task.spawn(function()
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, localPlayer.UserId, item.passId)
			if ok then
				ownedPasses[item.passId :: number] = owns == true
				refreshAll()
			end
		end)
	end
end

local function loadItems(): { Item }
	local items: { Item } = {}
	for _, kind in KINDS do
		for _, entry in Catalog.items(kind) do
			local item: Item = { kind = kind, name = entry.name, data = entry.data }
			if kind == Catalog.KIND_ROBUX then
				item.passId = entry.data.gamePassId
				item.productId = entry.data.productId
				if not (item.passId or item.productId) then continue end
				fetchRobuxInfo(item)
			end
			table.insert(items, item)
		end
	end
	return items
end

-- Fills the viewport and returns the framing so the details panel can orbit it.
local function fillWeaponPreview(viewport: ViewportFrame, item: Item): Spin?
	viewport:ClearAllChildren()
	local template = Catalog.model(item.kind, item.name)
	if not template then return nil end
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
	return { focus = box.Position, baseDirection = viewDirection, distance = distance, angle = 0, dragging = false }
end

local function fillIcon(icon: ImageLabel, item: Item)
	local source = Catalog.icon(item.kind, item.name)
	if source then
		icon.Image = source.Image
		icon.ImageColor3 = source.ImageColor3
	elseif item.info and item.info.icon then
		icon.Image = item.info.icon
	end
end

local function fillPreview(viewport: ViewportFrame, icon: ImageLabel, item: Item): Spin?
	if item.kind == Catalog.KIND_WEAPONS then
		viewport.Visible = true
		icon.Visible = false
		return fillWeaponPreview(viewport, item)
	end
	viewport.Visible = false
	icon.Visible = true
	fillIcon(icon, item)
	return nil
end

local function description(item: Item): string
	if item.data.description and item.data.description ~= "" then
		return item.data.description
	end
	if item.info and item.info.description then
		return item.info.description
	end
	return ""
end

local function formatStat(value: any): string
	if typeof(value) == "number" then
		return string.format("%g", value)
	end
	if typeof(value) == "boolean" then
		return if value then "YES" else "NO"
	end
	return tostring(value)
end

local function robuxPriceText(item: Item): string
	if item.info and item.info.price then
		return "R$ " .. item.info.price
	end
	return "ROBUX"
end

local function onCardActivated(modal: Modal, card: Card)
	local item = card.item
	if item.kind == Catalog.KIND_ROBUX then
		if item.passId and item.passId > 0 and not isOwned(item) then
			MarketplaceService:PromptGamePassPurchase(localPlayer, item.passId)
		elseif item.productId and item.productId > 0 then
			MarketplaceService:PromptProductPurchase(localPlayer, item.productId)
		end
		return
	end
	if modal.mode == MODE_SHOP then
		if not isOwned(item) then
			ShopPurchaseRemote:FireServer(item.kind, item.name)
		end
		return
	end
	if isOwned(item) and not isEquipped(item) then
		ShopEquipRemote:FireServer(item.kind, item.name)
	end
end

local function styleAction(action: TextButton, text: string, color: Color3, textColor: Color3, transparency: number)
	action.Text = text
	action.BackgroundColor3 = color
	action.TextColor3 = textColor
	action.BackgroundTransparency = transparency
end

local function buildTag(parent: GuiObject, modal: Modal, fontSource: TextLabel): Frame
	local tag = Instance.new("Frame")
	tag.Name = "EquippedTag"
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.fromScale(1, 0)
	tag.Size = TAG_SIZE
	tag.BackgroundColor3 = modal.accent
	tag.BorderSizePixel = 0
	tag.ZIndex = parent.ZIndex + 2
	tag.Visible = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = fontSource.FontFace
	label.Text = TAG_TEXT
	label.TextScaled = true
	label.TextColor3 = modal.panelColor
	label.ZIndex = tag.ZIndex + 1
	label.Parent = tag
	tag.Parent = parent
	return tag
end

local function mirrorPanel(modal: Modal, card: Card)
	local panel = modal.panel
	if not panel or modal.selected ~= card then return end
	panel.price.Text = card.price.Text
	panel.description.Text = description(card.item)
	panel.tag.Visible = card.tag.Visible
	styleAction(panel.action, card.action.Text, card.action.BackgroundColor3, card.action.TextColor3, card.action.BackgroundTransparency)
	if card.item.kind == Catalog.KIND_ROBUX then
		fillIcon(panel.icon, card.item)
	end
end

local function refreshCard(modal: Modal, card: Card)
	local item = card.item
	local isOwnedNow = isOwned(item)
	card.tag.Visible = isEquipped(item)
	if item.kind == Catalog.KIND_ROBUX then
		fillIcon(card.icon, item)
		card.frame.Visible = modal.mode == MODE_SHOP
		if isOwnedNow then
			card.price.Text = "OWNED"
			card.baseColor = MUTED_BUTTON_COLOR
			styleAction(card.action, "OWNED", MUTED_BUTTON_COLOR, modal.dimColor, 0)
		else
			card.price.Text = robuxPriceText(item)
			card.baseColor = modal.accent
			styleAction(card.action, "BUY", modal.accent, modal.panelColor, 0)
		end
		mirrorPanel(modal, card)
		return
	end
	if modal.mode == MODE_SHOP then
		card.frame.Visible = true
		if isOwnedNow then
			card.price.Text = "OWNED"
			card.baseColor = MUTED_BUTTON_COLOR
			styleAction(card.action, "OWNED", MUTED_BUTTON_COLOR, modal.dimColor, 0)
		else
			card.price.Text = card.cost .. " COINS"
			local transparency = if coins >= card.cost then 0 else UNAFFORDABLE_TRANSPARENCY
			card.baseColor = modal.accent
			styleAction(card.action, "BUY", modal.accent, modal.panelColor, transparency)
		end
		mirrorPanel(modal, card)
		return
	end

	card.frame.Visible = isOwnedNow
	card.price.Text = ""
	if isEquipped(item) then
		card.baseColor = MUTED_BUTTON_COLOR
		styleAction(card.action, "EQUIPPED", MUTED_BUTTON_COLOR, modal.dimColor, 0)
	else
		card.baseColor = modal.accent
		styleAction(card.action, "EQUIP", modal.accent, modal.panelColor, 0)
	end
	mirrorPanel(modal, card)
end

local function selectCard(modal: Modal, card: Card)
	local panel = modal.panel
	modal.selected = card
	if not panel then return end
	panel.placeholder.Visible = false
	panel.content.Visible = true
	panel.spin = fillPreview(panel.viewport, panel.icon, card.item)
	panel.name.Text = card.item.data.displayName
	for _, child in panel.stats:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if statRowTemplate then
		for index, row in card.item.data.stats or {} do
			local line = statRowTemplate:Clone()
			line.LayoutOrder = index
			local nameLabel = line:WaitForChild("StatName") :: TextLabel
			local valueLabel = line:WaitForChild("StatValue") :: TextLabel
			nameLabel.Text = tostring(row[1]):upper()
			valueLabel.Text = formatStat(row[2])
			line.Visible = true
			line.Parent = panel.stats
		end
	end
	mirrorPanel(modal, card)
end

local function buildCard(modal: Modal, item: Item)
	local grid = modal.grids[item.kind]
	if not grid then return end
	local card = cardTemplate:Clone()
	card.Name = item.name

	local inset = card:WaitForChild("Inset") :: GuiObject
	local preview = inset:WaitForChild("Preview") :: ViewportFrame
	local icon = inset:WaitForChild("Icon") :: ImageLabel
	fillPreview(preview, icon, item)
	local nameLabel = card:WaitForChild("ItemName") :: TextLabel
	nameLabel.Text = item.data.displayName
	local price = card:WaitForChild("Price") :: TextLabel
	price.TextColor3 = modal.accent
	local action = card:WaitForChild("Action") :: TextButton
	local tag = buildTag(inset, modal, nameLabel)

	local record: Card = {
		item = item,
		frame = card,
		price = price,
		action = action,
		icon = icon,
		tag = tag,
		cost = item.data.price or 0,
		baseColor = modal.accent,
	}
	card.Activated:Connect(function()
		selectCard(modal, record)
	end)
	action.Activated:Connect(function()
		selectCard(modal, record)
		onCardActivated(modal, record)
	end)
	hoverLift(action, function()
		return record.baseColor
	end)
	table.insert(modal.cards, record)
	card.Parent = grid
end

refreshAll = function()
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
	for _, k in modal.kinds do
		local active = k == kind
		modal.grids[k].Visible = active
		modal.tabs[k].TextColor3 = if active then modal.textColor else modal.dimColor
	end
	local tab = modal.tabs[kind]
	local centerX = UDim.new(tab.Position.X.Scale + tab.Size.X.Scale / 2, tab.Position.X.Offset + tab.Size.X.Offset / 2)
	local target = UDim2.new(centerX, modal.tabUnderline.Position.Y)
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

-- The details preview orbits the weapon: it spins on its own and follows a horizontal drag.
local function bindSpin(panel: Panel)
	panel.viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if panel.spin then panel.spin.dragging = true end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if panel.spin then panel.spin.dragging = false end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local spin = panel.spin
		if not spin or not spin.dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			spin.angle += input.Delta.X * PREVIEW_DRAG_SENSITIVITY
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local spin = panel.spin
		local camera = panel.viewport.CurrentCamera
		if not spin or not camera or not panel.viewport.Visible then return end
		if not spin.dragging then
			spin.angle += PREVIEW_SPIN_SPEED * dt
		end
		local direction = CFrame.Angles(0, math.rad(spin.angle), 0):VectorToWorldSpace(spin.baseDirection)
		camera.CFrame = CFrame.lookAt(spin.focus + direction * spin.distance, spin.focus)
	end)
end

local function resolvePanel(modal: Modal)
	local details = modal.frame:FindFirstChild("Details")
	if not details then return end
	local content = details:WaitForChild("Content")
	local preview = content:WaitForChild("Preview") :: GuiObject
	local name = content:WaitForChild("ItemName") :: TextLabel
	local panel: Panel = {
		placeholder = details:WaitForChild("Placeholder") :: GuiObject,
		content = content :: GuiObject,
		viewport = preview:WaitForChild("Viewport") :: ViewportFrame,
		icon = preview:WaitForChild("Icon") :: ImageLabel,
		tag = buildTag(preview, modal, name),
		name = name,
		description = content:WaitForChild("Description") :: TextLabel,
		stats = content:WaitForChild("Stats") :: GuiObject,
		price = content:WaitForChild("Price") :: TextLabel,
		action = content:WaitForChild("Action") :: TextButton,
		spin = nil,
	}
	panel.placeholder.Visible = true
	panel.content.Visible = false
	panel.action.Activated:Connect(function()
		if modal.selected then
			onCardActivated(modal, modal.selected)
		end
	end)
	hoverLift(panel.action, function()
		return if modal.selected then modal.selected.baseColor else modal.accent
	end)
	bindSpin(panel)
	modal.panel = panel
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
		kinds = {},
		tabs = {},
		tabUnderline = frame:WaitForChild("TabUnderline") :: GuiObject,
		grids = {},
		cards = {},
		coinsLabel = frame:FindFirstChild("Coins") :: TextLabel?,
		panel = nil,
		selected = nil,
	}
	frame.Visible = false
	modal.scale.Scale = 1

	-- A modal lists the kinds it has a tab and grid for; the inventory has no Robux tab.
	for _, kind in KINDS do
		local tab = frame:FindFirstChild(TAB_NAMES[kind])
		local grid = frame:FindFirstChild(GRID_NAMES[kind])
		if not (tab and tab:IsA("TextButton") and grid and grid:IsA("ScrollingFrame")) then continue end
		table.insert(modal.kinds, kind)
		tab.Activated:Connect(function()
			setTab(modal, kind)
		end)
		hoverText(tab, modal.textColor, function()
			return if grid.Visible then modal.textColor else modal.dimColor
		end)
		modal.tabs[kind] = tab
		modal.grids[kind] = grid
	end

	hoverText(close, modal.textColor, function()
		return modal.dimColor
	end)
	close.Activated:Connect(function()
		setModalOpen(modal, false)
	end)

	resolvePanel(modal)
	for _, item in items do
		buildCard(modal, item)
	end
	if modal.kinds[1] then
		setTab(modal, modal.kinds[1])
	end
	table.insert(modals, modal)
	return modal
end

function ShopController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local lobbyGui = playerGui:WaitForChild("Lobby") :: ScreenGui
	lobbyButtons = lobbyGui:WaitForChild("Buttons") :: GuiObject
	local shopButton = lobbyButtons:WaitForChild("ShopButton") :: TextButton
	local inventoryButton = lobbyButtons:WaitForChild("InventoryButton") :: TextButton
	local idObjects = lobbyGui:WaitForChild("ID_Objects")
	cardTemplate = idObjects:WaitForChild("ItemCard") :: GuiButton
	statRowTemplate = idObjects:FindFirstChild("StatRow") :: GuiObject?

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

	ShopStateRemote.OnClientEvent:Connect(function(state: { coins: number, owned: { [string]: { string } }, equipped: { [string]: string } })
		coins = state.coins
		owned = state.owned
		equipped = state.equipped
		refreshAll()
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if player ~= localPlayer or not purchased then return end
		ownedPasses[passId] = true
		refreshAll()
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
		reconcileLobbyUI()
	end)

	ShopStateRemote:FireServer()
end

return ShopController
