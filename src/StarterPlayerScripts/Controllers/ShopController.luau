local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
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

-- Weapon preview camera
local PREVIEW_FOV = 40
local PREVIEW_DISTANCE = 1.15 -- multiples of the model's bounding-box diagonal
local PREVIEW_TILT = 0.35     -- 0 = pure side profile, higher = more three-quarter view

local KIND_WEAPON = "Weapon"
local KIND_ABILITY = "Ability"
local KIND_ROBUX = "Robux"
local KINDS = { KIND_WEAPON, KIND_ABILITY, KIND_ROBUX }
local TAB_NAMES = { [KIND_WEAPON] = "WeaponsTab", [KIND_ABILITY] = "AbilitiesTab", [KIND_ROBUX] = "RobuxTab" }
local GRID_NAMES = { [KIND_WEAPON] = "WeaponGrid", [KIND_ABILITY] = "AbilityGrid", [KIND_ROBUX] = "RobuxGrid" }
local CATALOG_FOLDERS = { [KIND_WEAPON] = "Weapons", [KIND_ABILITY] = "Abilities", [KIND_ROBUX] = "Robux" }
-- Attributes that configure an item rather than describe it; everything else is a stat row.
local HIDDEN_ATTRIBUTES = { Price = true, Description = true, GamePassId = true, ProductId = true }

local MODE_SHOP = "Shop"
local MODE_INVENTORY = "Inventory"

type RobuxInfo = { price: number?, icon: string?, description: string? }
type Item = { kind: string, name: string, template: Instance, passId: number?, productId: number?, info: RobuxInfo? }
type Card = { item: Item, frame: GuiButton, price: TextLabel, action: TextButton, icon: ImageLabel, cost: number, baseColor: Color3 }
type Panel = {
	placeholder: GuiObject,
	content: GuiObject,
	viewport: ViewportFrame,
	icon: ImageLabel,
	name: TextLabel,
	description: TextLabel,
	stats: GuiObject,
	price: TextLabel,
	action: TextButton,
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
local ownedWeapons: { [string]: boolean } = {}
local ownedAbilities: { [string]: boolean } = {}
local ownedPasses: { [number]: boolean } = {}
local equippedWeapon = Constants.VIEWMODEL_DEFAULT_WEAPON

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
	if item.kind == KIND_ABILITY then
		return ownedAbilities[item.name] == true
	end
	if item.passId then
		return ownedPasses[item.passId] == true
	end
	return false
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
		local folder = ReplicatedStorage:FindFirstChild(CATALOG_FOLDERS[kind])
		if not folder then continue end
		for _, template in folder:GetChildren() do
			if kind == KIND_WEAPON and template:IsA("Model") then
				table.insert(items, { kind = kind, name = template.Name, template = template })
			elseif kind == KIND_ABILITY and template:IsA("Folder") then
				table.insert(items, { kind = kind, name = template.Name, template = template })
			elseif kind == KIND_ROBUX then
				local passId = template:GetAttribute("GamePassId")
				local productId = template:GetAttribute("ProductId")
				local item: Item = {
					kind = kind,
					name = template.Name,
					template = template,
					passId = if typeof(passId) == "number" then passId else nil,
					productId = if typeof(productId) == "number" then productId else nil,
				}
				if item.passId or item.productId then
					table.insert(items, item)
					fetchRobuxInfo(item)
				end
			end
		end
	end
	return items
end

local function fillWeaponPreview(viewport: ViewportFrame, template: Model)
	viewport:ClearAllChildren()
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

-- A Robux item's icon is a child ImageLabel named Icon if authored, else the marketplace icon.
local function fillRobuxIcon(icon: ImageLabel, item: Item)
	local source = item.template:FindFirstChild("Icon")
	if source and source:IsA("ImageLabel") then
		icon.Image = source.Image
		icon.ImageColor3 = source.ImageColor3
	elseif item.info and item.info.icon then
		icon.Image = item.info.icon
	end
end

local function fillPreview(viewport: ViewportFrame, icon: ImageLabel, item: Item)
	if item.kind == KIND_WEAPON then
		fillWeaponPreview(viewport, item.template :: Model)
		viewport.Visible = true
		icon.Visible = false
		return
	end
	viewport.Visible = false
	icon.Visible = true
	if item.kind == KIND_ABILITY then
		fillAbilityIcon(icon, item.template)
	else
		fillRobuxIcon(icon, item)
	end
end

local function description(item: Item): string
	local text = item.template:GetAttribute("Description")
	if typeof(text) == "string" and text ~= "" then
		return text
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

-- Every attribute that isn't configuration is a stat; abilities also list their params.
local function statRows(item: Item): { { name: string, value: string } }
	local rows: { { name: string, value: string } } = {}
	for name, value in item.template:GetAttributes() do
		if not HIDDEN_ATTRIBUTES[name] then
			table.insert(rows, { name = name, value = formatStat(value) })
		end
	end
	if item.kind == KIND_ABILITY then
		for name, value in Abilities.params(item.name) :: any do
			table.insert(rows, { name = name, value = formatStat(value) })
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	return rows
end

local function robuxPriceText(item: Item): string
	if item.info and item.info.price then
		return "R$ " .. item.info.price
	end
	return "ROBUX"
end

local function onCardActivated(modal: Modal, card: Card)
	local item = card.item
	if item.kind == KIND_ROBUX then
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
	if item.kind == KIND_WEAPON and isOwned(item) and equippedWeapon ~= item.name then
		ShopEquipRemote:FireServer(item.name)
	end
end

local function styleAction(action: TextButton, text: string, color: Color3, textColor: Color3, transparency: number)
	action.Text = text
	action.BackgroundColor3 = color
	action.TextColor3 = textColor
	action.BackgroundTransparency = transparency
end

local function mirrorPanel(modal: Modal, card: Card)
	local panel = modal.panel
	if not panel or modal.selected ~= card then return end
	panel.price.Text = card.price.Text
	panel.description.Text = description(card.item)
	styleAction(panel.action, card.action.Text, card.action.BackgroundColor3, card.action.TextColor3, card.action.BackgroundTransparency)
	if card.item.kind == KIND_ROBUX then
		fillRobuxIcon(panel.icon, card.item)
	end
end

local function refreshCard(modal: Modal, card: Card)
	local item = card.item
	local owned = isOwned(item)
	if item.kind == KIND_ROBUX then
		fillRobuxIcon(card.icon, item)
		card.frame.Visible = modal.mode == MODE_SHOP
		if owned then
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
		if owned then
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

	card.frame.Visible = owned
	card.price.Text = ""
	if item.kind ~= KIND_WEAPON then
		card.baseColor = MUTED_BUTTON_COLOR
		styleAction(card.action, "OWNED", MUTED_BUTTON_COLOR, modal.dimColor, 0)
	elseif equippedWeapon == item.name then
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
	fillPreview(panel.viewport, panel.icon, card.item)
	panel.name.Text = card.item.name
	for _, child in panel.stats:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if statRowTemplate then
		for index, row in statRows(card.item) do
			local line = statRowTemplate:Clone()
			line.LayoutOrder = index
			local nameLabel = line:WaitForChild("StatName") :: TextLabel
			local valueLabel = line:WaitForChild("StatValue") :: TextLabel
			nameLabel.Text = row.name:upper()
			valueLabel.Text = row.value
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

	local inset = card:WaitForChild("Inset")
	local preview = inset:WaitForChild("Preview") :: ViewportFrame
	local icon = inset:WaitForChild("Icon") :: ImageLabel
	fillPreview(preview, icon, item)
	local nameLabel = card:WaitForChild("ItemName") :: TextLabel
	nameLabel.Text = item.name
	local price = card:WaitForChild("Price") :: TextLabel
	price.TextColor3 = modal.accent
	local action = card:WaitForChild("Action") :: TextButton

	local record: Card = { item = item, frame = card, price = price, action = action, icon = icon, cost = itemPrice(item.template), baseColor = modal.accent }
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

local function resolvePanel(modal: Modal)
	local details = modal.frame:FindFirstChild("Details")
	if not details then return end
	local content = details:WaitForChild("Content")
	local preview = content:WaitForChild("Preview")
	local panel: Panel = {
		placeholder = details:WaitForChild("Placeholder") :: GuiObject,
		content = content :: GuiObject,
		viewport = preview:WaitForChild("Viewport") :: ViewportFrame,
		icon = preview:WaitForChild("Icon") :: ImageLabel,
		name = content:WaitForChild("ItemName") :: TextLabel,
		description = content:WaitForChild("Description") :: TextLabel,
		stats = content:WaitForChild("Stats") :: GuiObject,
		price = content:WaitForChild("Price") :: TextLabel,
		action = content:WaitForChild("Action") :: TextButton,
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
