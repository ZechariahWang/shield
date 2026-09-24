local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MinimapController = {}

type Bounds = { centerX: number, centerZ: number, longest: number }

local localPlayer = Players.LocalPlayer
local frame: Frame
local currentPhase = Constants.PHASE_LOBBY
local bounds: Bounds? = nil

local dots: { [Model]: Frame } = {}
local shotFlashUntil: { [Model]: number } = {}
local shotConnections: { [Model]: RBXScriptConnection } = {}

-- ponytail: axis-aligned part extents, so a rotated part can pad the bounds a little.
local function computeBounds(): Bounds?
	local map = Workspace:FindFirstChild("LoadedMap")
	if not map then return nil end
	local minX, minZ = math.huge, math.huge
	local maxX, maxZ = -math.huge, -math.huge
	for _, part in map:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		local half = part.Size / 2
		local pos = part.Position
		minX = math.min(minX, pos.X - half.X)
		maxX = math.max(maxX, pos.X + half.X)
		minZ = math.min(minZ, pos.Z - half.Z)
		maxZ = math.max(maxZ, pos.Z + half.Z)
	end
	if minX == math.huge then return nil end
	return {
		centerX = (minX + maxX) / 2,
		centerZ = (minZ + maxZ) / 2,
		longest = math.max(maxX - minX, maxZ - minZ, 1),
	}
end

-- Top-down, north (-Z) up, the longer arena side fitted to the square.
local function project(position: Vector3): (number, number)
	local b = bounds :: Bounds
	local u = 0.5 + (position.X - b.centerX) / b.longest
	local v = 0.5 - (position.Z - b.centerZ) / b.longest
	return u, v
end

local function collectCombatants(): { Model }
	local list: { Model } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	local bots = Workspace:FindFirstChild("Bots")
	if bots then
		for _, bot in bots:GetChildren() do
			if bot:IsA("Model") then
				table.insert(list, bot)
			end
		end
	end
	return list
end

local function removeDot(char: Model)
	local dot = dots[char]
	if dot then dot:Destroy() end
	dots[char] = nil
	shotFlashUntil[char] = nil
	local conn = shotConnections[char]
	if conn then conn:Disconnect() end
	shotConnections[char] = nil
end

local function ensureDot(char: Model): Frame
	local dot = dots[char]
	if dot then return dot end
	dot = Instance.new("Frame")
	dot.Name = char.Name
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(Constants.MINIMAP_DOT_SIZE, Constants.MINIMAP_DOT_SIZE)
	dot.BorderSizePixel = 0
	dot.Parent = frame
	dots[char] = dot
	shotConnections[char] = char:GetAttributeChangedSignal("Shots"):Connect(function()
		shotFlashUntil[char] = os.clock() + Constants.MINIMAP_SHOT_FLASH
	end)
	return dot
end

local function dotColor(char: Model, now: number): Color3
	if char == localPlayer.Character then
		return Constants.MINIMAP_SELF_COLOR
	end
	if char:FindFirstChild("PlayerShield") then
		return Constants.MINIMAP_SHIELD_COLOR
	end
	if (shotFlashUntil[char] or 0) > now then
		return Constants.MINIMAP_SHOOTING_COLOR
	end
	return Constants.MINIMAP_ENEMY_COLOR
end

local function clearDots()
	for char in dots do
		removeDot(char)
	end
end

local function update()
	if not frame.Visible or not bounds then return end
	local now = os.clock()
	local present: { [Model]: boolean } = {}
	for _, char in collectCombatants() do
		present[char] = true
		local root = char:FindFirstChild("HumanoidRootPart")
		local dot = ensureDot(char)
		if not root or not root:IsA("BasePart") then
			dot.Visible = false
			continue
		end
		local u, v = project(root.Position)
		local inside = u >= 0 and u <= 1 and v >= 0 and v <= 1
		dot.Visible = inside
		dot.Position = UDim2.fromScale(u, v)
		dot.BackgroundColor3 = dotColor(char, now)
	end
	for char in dots do
		if not present[char] then
			removeDot(char)
		end
	end
end

local function reconcileVisibility()
	local show = currentPhase == Constants.PHASE_ROUND
	if show then
		bounds = computeBounds()
		show = bounds ~= nil
	end
	frame.Visible = show
	if not show then
		clearDots()
	end
end

function MinimapController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gameGui = playerGui:WaitForChild("Game") :: ScreenGui
	frame = gameGui:WaitForChild("Minimap") :: Frame
	frame.Visible = false

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		reconcileVisibility()
	end)

	RunService.RenderStepped:Connect(update)
end

return MinimapController
