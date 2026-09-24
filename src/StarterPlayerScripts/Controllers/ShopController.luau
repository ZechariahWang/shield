local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local ShopController = {}

-- Shop button feedback
local TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local IDLE_SCALE = 1
local HOVER_SCALE = 1.05
local PRESS_SCALE = 0.95
local IDLE_TRANSPARENCY = 0.25
local HOVER_TRANSPARENCY = 0.05

-- Modal look (matches the Studio-authored ShopButton)
local FONT = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local PANEL_COLOR = Color3.fromRGB(20, 12, 8)
local CARD_COLOR = Color3.fromRGB(34, 22, 14)
local TEXT_COLOR = Color3.fromRGB(255, 245, 220)
local ACCENT_COLOR = Color3.fromRGB(255, 159, 80)
local DIM_COLOR = Color3.fromRGB(120, 105, 90)
local MODAL_SIZE = UDim2.fromScale(0.6, 0.65)
local CARD_SIZE = UDim2.fromScale(0.31, 0.5)
local CARD_PADDING = UDim2.fromScale(0.02, 0.03)

-- Weapon preview camera
local PREVIEW_FOV = 40
local PREVIEW_DISTANCE = 1.15 -- multiples of the model's bounding-box diagonal
local PREVIEW_TILT = 0.35    -- 0 = pure side profile, higher = more three-quarter view

local hovering = false
local pressing = false

local coins = 0
local owned: { [string]: boolean } = {}
local equipped = Constants.VIEWMODEL_DEFAULT_WEAPON

local modal: Frame
local coinsLabel: TextLabel
local cards: { [string]: { price: TextLabel, action: TextButton, cost: number } } = {}

local ShopStateRemote: RemoteEvent
local ShopPurchaseRemote: RemoteEvent
local ShopEquipRemote: RemoteEvent

local function refreshButton(button: TextButton, scale: UIScale)
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

local function bindShopButton(button: TextButton)
	local scale = button:WaitForChild("UIScale") :: UIScale
	button.MouseEnter:Connect(function()
		hovering = true
		refreshButton(button, scale)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		pressing = false
		refreshButton(button, scale)
	end)
	button.MouseButton1Down:Connect(function()
		pressing = true
		refreshButton(button, scale)
	end)
	button.MouseButton1Up:Connect(function()
		pressing = false
		refreshButton(button, scale)
	end)
	button.Activated:Connect(function()
		modal.Visible = not modal.Visible
	end)
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

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function weaponPrice(template: Model): number
	local price = template:GetAttribute("Price")
	if typeof(price) == "number" then
		return price
	end
	return Constants.SHOP_DEFAULT_WEAPON_PRICE
end

local function buildPreview(parent: Instance, template: Model)
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

local function buildCard(parent: Instance, template: Model)
	local card = Instance.new("Frame")
	card.Name = template.Name
	card.BackgroundColor3 = CARD_COLOR
	card.Parent = parent
	corner(card, 6)

	buildPreview(card, template)
	label(card, template.Name, UDim2.fromScale(0.9, 0.14), UDim2.fromScale(0.05, 0.56), Enum.TextXAlignment.Left)
	local price = label(card, "", UDim2.fromScale(0.9, 0.1), UDim2.fromScale(0.05, 0.7), Enum.TextXAlignment.Left)
	price.TextColor3 = ACCENT_COLOR

	local action = Instance.new("TextButton")
	action.Size = UDim2.fromScale(0.9, 0.14)
	action.Position = UDim2.fromScale(0.05, 0.83)
	action.BackgroundColor3 = ACCENT_COLOR
	action.FontFace = FONT
	action.TextColor3 = PANEL_COLOR
	action.TextScaled = true
	action.Parent = card
	corner(action, 4)

	local name = template.Name
	action.Activated:Connect(function()
		if equipped == name then return end
		if owned[name] then
			ShopEquipRemote:FireServer(name)
		else
			ShopPurchaseRemote:FireServer(name)
		end
	end)

	cards[name] = { price = price, action = action, cost = weaponPrice(template) }
end

local function refreshCards()
	coinsLabel.Text = "COINS " .. coins
	for name, card in cards do
		if equipped == name then
			card.price.Text = "OWNED"
			card.action.Text = "EQUIPPED"
			card.action.BackgroundColor3 = DIM_COLOR
		elseif owned[name] then
			card.price.Text = "OWNED"
			card.action.Text = "EQUIP"
			card.action.BackgroundColor3 = ACCENT_COLOR
		else
			card.price.Text = card.cost .. " COINS"
			card.action.Text = "BUY"
			card.action.BackgroundColor3 = if coins >= card.cost then ACCENT_COLOR else DIM_COLOR
		end
	end
end

local function buildModal(parent: ScreenGui)
	modal = Instance.new("Frame")
	modal.Name = "ShopModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = MODAL_SIZE
	modal.BackgroundColor3 = PANEL_COLOR
	modal.Visible = false
	modal.ZIndex = 10
	modal.Parent = parent
	corner(modal, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT_COLOR
	stroke.Thickness = 2
	stroke.Parent = modal

	label(modal, "SHOP", UDim2.fromScale(0.3, 0.1), UDim2.fromScale(0.04, 0.03), Enum.TextXAlignment.Left)
	coinsLabel = label(modal, "COINS 0", UDim2.fromScale(0.3, 0.07), UDim2.fromScale(0.55, 0.045), Enum.TextXAlignment.Right)
	coinsLabel.TextColor3 = ACCENT_COLOR

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Size = UDim2.fromScale(0.06, 0.09)
	close.Position = UDim2.fromScale(0.97, 0.03)
	close.BackgroundTransparency = 1
	close.FontFace = FONT
	close.TextColor3 = TEXT_COLOR
	close.TextScaled = true
	close.Text = "X"
	close.Parent = modal
	close.Activated:Connect(function()
		modal.Visible = false
	end)

	local grid = Instance.new("ScrollingFrame")
	grid.Size = UDim2.fromScale(0.92, 0.8)
	grid.Position = UDim2.fromScale(0.04, 0.16)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = modal
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = CARD_SIZE
	layout.CellPadding = CARD_PADDING
	layout.SortOrder = Enum.SortOrder.Name
	layout.Parent = grid

	local weapons = ReplicatedStorage:FindFirstChild("Weapons")
	if not weapons then return end
	for _, template in weapons:GetChildren() do
		if template:IsA("Model") then
			buildCard(grid, template)
		end
	end
end

function ShopController.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local lobbyGui = playerGui:WaitForChild("Lobby") :: ScreenGui
	local button = lobbyGui:WaitForChild("ShopButton") :: TextButton

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	ShopStateRemote = Remotes:WaitForChild("ShopState") :: RemoteEvent
	ShopPurchaseRemote = Remotes:WaitForChild("ShopPurchase") :: RemoteEvent
	ShopEquipRemote = Remotes:WaitForChild("ShopEquip") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	buildModal(lobbyGui)
	bindShopButton(button)
	refreshCards()

	ShopStateRemote.OnClientEvent:Connect(function(newCoins: number, ownedList: { string }, newEquipped: string)
		coins = newCoins
		owned = {}
		for _, name in ownedList do
			owned[name] = true
		end
		equipped = newEquipped
		refreshCards()
	end)

	-- Combat takes the mouse, so the modal can't stay open into a round.
	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		if phase == Constants.PHASE_REVEAL then
			modal.Visible = false
		end
	end)

	ShopStateRemote:FireServer()
end

return ShopController
