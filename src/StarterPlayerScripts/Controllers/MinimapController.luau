local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MinimapController = {}

local localPlayer = Players.LocalPlayer
local frame: Frame
local currentPhase = Constants.PHASE_LOBBY

local dots: { [Model]: Frame } = {}
local shotFlashUntil: { [Model]: number } = {}
local shotConnections: { [Model]: RBXScriptConnection } = {}

local function localRoot(): BasePart?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Where the player is looking, flattened to the ground plane. The camera leads
-- the character under shift lock, so it is the direction that feels like "up".
local function facing(root: BasePart): Vector3
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.001 then
		flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if flat.Magnitude < 0.001 then
		return -Vector3.zAxis
	end
	return flat.Unit
end

-- Top-down, the local player at the center and their facing direction up;
-- MINIMAP_RANGE studs reach the edge.
local function project(position: Vector3, center: Vector3, forward: Vector3): (number, number)
	local offset = position - center
	local right = forward:Cross(Vector3.yAxis)
	local u = 0.5 + offset:Dot(right) / (2 * Constants.MINIMAP_RANGE)
	local v = 0.5 - offset:Dot(forward) / (2 * Constants.MINIMAP_RANGE)
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
	if not frame.Visible then return end
	local center = localRoot()
	if not center then
		clearDots()
		return
	end
	local forward = facing(center)
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
		local u, v = project(root.Position, center.Position, forward)
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
	local show = currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND
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
