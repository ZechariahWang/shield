local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)
local CombatSystem = require(script.Parent.CombatSystem)
local MapManager = require(script.Parent.MapManager)

-- Server-driven combatants for solo playtesting. Each bot is a clone of the NPC
-- rig that wanders between spawn points via PathfindingService, fires at the
-- nearest visible combatant on a random timer, and raises its shield on another.
-- All combat goes through CombatSystem, so bots take and deal damage exactly
-- like players.
local BotSystem = {}

local BOTS_FOLDER_NAME = "Bots"

local bots: { [Model]: boolean } = {}
local running = false
local generation = 0

local function randomBetween(range: { number }): number
	return range[1] + math.random() * (range[2] - range[1])
end

local function getFolder(): Folder
	local existing = Workspace:FindFirstChild(BOTS_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = BOTS_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function findRig(): Model?
	local current: Instance = ReplicatedStorage
	for _, name in Constants.BOT_RIG_PATH do
		local next = current:FindFirstChild(name)
		if not next then return nil end
		current = next
	end
	if current:IsA("Model") then
		return current
	end
	return nil
end

local function isAlive(char: Model): boolean
	if not running or not bots[char] or not char.Parent then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Every combatant other than the bot itself: Safe players plus other live bots.
local function targetsFor(char: Model): { Model }
	local targets = {}
	for _, player in Players:GetPlayers() do
		local c = player.Character
		if c and PlayerState.get(player) == Constants.STATE_SAFE then
			table.insert(targets, c)
		end
	end
	for other in bots do
		if other ~= char and other.Parent then
			table.insert(targets, other)
		end
	end
	return targets
end

local function nearestVisibleTarget(char: Model, head: BasePart): BasePart?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local best: BasePart? = nil
	local bestDistance = Constants.PISTOL_RANGE
	for _, target in targetsFor(char) do
		local targetHead = target:FindFirstChild("Head") :: BasePart?
		if not targetHead then continue end
		local offset = targetHead.Position - head.Position
		local distance = offset.Magnitude
		if distance >= bestDistance or distance < 0.01 then continue end
		local hit = Workspace:Raycast(head.Position, offset, params)
		if hit and not hit.Instance:IsDescendantOf(target) then continue end
		best = targetHead
		bestDistance = distance
	end
	return best
end

local function jitter(direction: Vector3): Vector3
	local yaw = (math.random() - 0.5) * 2 * Constants.BOT_AIM_JITTER
	local pitch = (math.random() - 0.5) * 2 * Constants.BOT_AIM_JITTER
	local frame = CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(pitch, yaw, 0)
	return frame.LookVector
end

local function randomDirection(): Vector3
	local yaw = math.random() * math.pi * 2
	local pitch = (math.random() - 0.5) * 0.3
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0).LookVector
end

local function fire(char: Model)
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then return end
	local targetHead = nearestVisibleTarget(char, head)
	local direction: Vector3
	if targetHead then
		direction = jitter((targetHead.Position - head.Position).Unit)
	else
		direction = randomDirection()
	end
	CombatSystem.shoot(char, head.Position, direction)
end

local function combatLoop(char: Model, gen: number)
	local nextShot = os.clock() + randomBetween(Constants.BOT_SHOOT_INTERVAL)
	local nextShield = os.clock() + randomBetween(Constants.BOT_SHIELD_INTERVAL)
	while gen == generation and isAlive(char) do
		task.wait(0.2)
		local now = os.clock()
		if now >= nextShield then
			nextShield = now + randomBetween(Constants.BOT_SHIELD_INTERVAL)
			CombatSystem.raiseShield(char)
		end
		if now >= nextShot then
			nextShot = now + randomBetween(Constants.BOT_SHOOT_INTERVAL)
			fire(char)
		end
	end
end

-- Returns false if the bot got stuck before reaching the waypoint.
local function walkToWaypoint(char: Model, hum: Humanoid, root: BasePart, waypoint: PathWaypoint, gen: number): boolean
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		hum.Jump = true
	end
	hum:MoveTo(waypoint.Position)
	local deadline = os.clock() + Constants.BOT_WAYPOINT_TIMEOUT
	while gen == generation and isAlive(char) do
		if horizontalDistance(root.Position, waypoint.Position) < 3 then
			return true
		end
		if os.clock() > deadline then
			return false
		end
		task.wait(0.1)
	end
	return false
end

local function walkLoop(char: Model, gen: number)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then return end

	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
	while gen == generation and isAlive(char) do
		local destination = MapManager.randomSpawnCFrame()
		if not destination then
			task.wait(1)
			continue
		end

		local ok = pcall(function()
			path:ComputeAsync(root.Position, destination.Position)
		end)
		if not ok or path.Status ~= Enum.PathStatus.Success then
			task.wait(0.5)
			continue
		end

		for _, waypoint in path:GetWaypoints() do
			local reached = walkToWaypoint(char, hum, root, waypoint, gen)
			if not reached then break end
		end
	end
end

function BotSystem.isBot(char: Model): boolean
	return bots[char] == true
end

function BotSystem.remove(char: Model)
	bots[char] = nil
	CombatSystem.unregisterBot(char)
	char:Destroy()
end

-- Clone the rigs onto spawn points. Called at Reveal so bots are visible during positioning.
function BotSystem.spawn()
	local rig = findRig()
	if not rig then
		warn("BotSystem: rig not found at ReplicatedStorage." .. table.concat(Constants.BOT_RIG_PATH, "."))
		return
	end
	local folder = getFolder()
	for i = 1, Constants.BOT_COUNT do
		local cframe = MapManager.randomSpawnCFrame()
		if not cframe then break end
		local char = rig:Clone()
		char.Name = "Bot" .. i
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.BreakJointsOnDeath = false
			hum.WalkSpeed = Constants.SAFE_WALKSPEED
		end
		char:PivotTo(cframe + Vector3.new(0, 4, 0))
		char.Parent = folder
		bots[char] = true
		CombatSystem.registerBot(char)
	end
end

function BotSystem.start()
	running = true
	generation += 1
	for char in bots do
		task.spawn(walkLoop, char, generation)
		task.spawn(combatLoop, char, generation)
	end
end

-- Stops the loops but leaves the models standing so a victim's kill cam can
-- keep tracking its bot through the arena freeze; despawn() removes them.
function BotSystem.stop()
	running = false
	generation += 1
	for char in bots do
		CombatSystem.unregisterBot(char)
	end
	table.clear(bots)
end

function BotSystem.despawn()
	local folder = Workspace:FindFirstChild(BOTS_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
end

function BotSystem.init()
	BotSystem.stop()
	if Constants.BOT_COUNT > 0 and not findRig() then
		warn("BotSystem: rig not found at ReplicatedStorage." .. table.concat(Constants.BOT_RIG_PATH, ".") .. ": no bots will spawn")
	end
end

return BotSystem
