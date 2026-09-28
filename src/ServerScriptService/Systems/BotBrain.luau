local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)
local CombatSystem = require(script.Parent.CombatSystem)
local MapManager = require(script.Parent.MapManager)

-- One behavior loop per bot, stepped on Heartbeat between BotSystem.start and
-- stop. Perception picks the nearest combatant in line of sight; with one in
-- view the bot faces it, strafes, holds its distance, hops, shoots with a
-- skill-based aim error and blocks when the enemy is about to fire; with none it
-- roams to where it last saw one, or a random spawn point, along a path. Every
-- shot and shield goes through CombatSystem, so the rules are the players'.
local BotBrain = {}

export type Skill = { reaction: number, aimError: number, aggression: number, shieldSense: number }

type Bot = {
	char: Model,
	hum: Humanoid,
	root: BasePart,
	head: BasePart,
	skill: Skill,
	path: Path,
	target: Model?,
	firstSeenAt: number,
	lastSeenAt: number,
	lastSeenPos: Vector3?,
	nextPerception: number,
	engaged: boolean,
	strafeDir: number,
	nextStrafeFlip: number,
	nextJump: number,
	nextShot: number,
	shieldRaiseAt: number?,
	threatRolledAt: number?,
	lastBreakAt: number,
	waypoints: { PathWaypoint },
	waypointIndex: number,
	walkingTo: PathWaypoint?,
	waypointDeadline: number,
	destination: Vector3?,
	computing: boolean,
	nextPathAt: number,
}

local bots: { [Model]: Bot } = {}

local function randomBetween(range: { number }): number
	return range[1] + math.random() * (range[2] - range[1])
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Pure helpers, checked by BotBrainTest.

function BotBrain._rollSkill(): Skill
	return {
		reaction = randomBetween(Constants.BOT_REACTION_TIME),
		aimError = randomBetween(Constants.BOT_AIM_ERROR),
		aggression = randomBetween(Constants.BOT_AGGRESSION),
		shieldSense = randomBetween(Constants.BOT_SHIELD_SENSE),
	}
end

-- Radians of aim error: the rolled base, worse with distance and target speed,
-- better the longer the target has been tracked.
function BotBrain._aimError(base: number, distance: number, targetSpeed: number, trackTime: number): number
	local range = math.sqrt(math.max(distance, 1) / Constants.BOT_AIM_REFERENCE_DISTANCE)
	local speed = 1 + targetSpeed / Constants.SAFE_WALKSPEED * Constants.BOT_AIM_SPEED_PENALTY
	local settle = 1 + math.max(trackTime, 0) * Constants.BOT_AIM_SETTLE_RATE
	return base * range * speed / settle
end

-- 1 to close in, -1 to back off, 0 to hold, from the distance to the target.
function BotBrain._holdMove(distance: number): number
	if distance > Constants.BOT_ENGAGE_DISTANCE[2] then return 1 end
	if distance < Constants.BOT_ENGAGE_DISTANCE[1] then return -1 end
	return 0
end

-- True when the enemy at enemyPos looking along enemyLook has the bot inside BOT_THREAT_ANGLE.
function BotBrain._facing(enemyPos: Vector3, enemyLook: Vector3, botPos: Vector3): boolean
	local look = flat(enemyLook)
	local toBot = flat(botPos - enemyPos)
	if look.Magnitude < 0.001 or toBot.Magnitude < 0.001 then return false end
	return look.Unit:Dot(toBot.Unit) >= math.cos(math.rad(Constants.BOT_THREAT_ANGLE))
end

-- Perception.

local function targetsFor(bot: Bot): { Model }
	local targets = {}
	for _, player in Players:GetPlayers() do
		local c = player.Character
		if c and PlayerState.get(player) == Constants.STATE_SAFE then
			table.insert(targets, c)
		end
	end
	for char in bots do
		if char ~= bot.char and char.Parent then
			table.insert(targets, char)
		end
	end
	return targets
end

local function perceive(bot: Bot, now: number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.char }

	local best: Model? = nil
	local bestDistance = Constants.PISTOL_RANGE
	local bestHead: BasePart? = nil
	for _, target in targetsFor(bot) do
		local head = target:FindFirstChild("Head") :: BasePart?
		if not head then continue end
		local offset = head.Position - bot.head.Position
		local distance = offset.Magnitude
		if distance >= bestDistance or distance < 0.01 then continue end
		local hit = Workspace:Raycast(bot.head.Position, offset, params)
		if hit and not hit.Instance:IsDescendantOf(target) then continue end
		best = target
		bestDistance = distance
		bestHead = head
	end
	if best ~= bot.target then
		bot.target = best
		bot.firstSeenAt = now
	end
	if best and bestHead then
		bot.lastSeenAt = now
		bot.lastSeenPos = bestHead.Position
	end
end

-- Engaged: face the target, strafe, hold distance, hop.

local function stepEngaged(bot: Bot, target: Model, now: number, dt: number)
	local targetRoot = (target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")) :: BasePart?
	if not targetRoot then return end
	local toTarget = flat(targetRoot.Position - bot.root.Position)
	local distance = toTarget.Magnitude
	if distance < 0.01 then return end
	local dir = toTarget.Unit

	bot.hum.AutoRotate = false
	local goal = CFrame.lookAt(bot.root.Position, bot.root.Position + dir)
	local alpha = 1 - math.exp(-Constants.BOT_TURN_RATE * dt)
	bot.root.CFrame = bot.root.CFrame:Lerp(goal, alpha)

	if now >= bot.nextStrafeFlip then
		bot.strafeDir = if math.random() < 0.5 then -1 else 1
		bot.nextStrafeFlip = now + randomBetween(Constants.BOT_STRAFE_SWITCH)
	end
	local move = goal.RightVector * bot.strafeDir + dir * BotBrain._holdMove(distance) * 0.8
	if move.Magnitude > 0.001 then
		move = move.Unit
	end
	bot.hum:Move(move, false)

	if now >= bot.nextJump then
		bot.hum.Jump = true
		bot.nextJump = now + randomBetween(Constants.BOT_JUMP_INTERVAL) / (0.5 + bot.skill.aggression)
	end

	if not CombatSystem.shieldUp(bot.char) and bot.hum.WalkSpeed ~= Constants.SAFE_WALKSPEED then
		bot.hum.WalkSpeed = Constants.SAFE_WALKSPEED
	end
end

-- Shooting.

local function jitter(direction: Vector3, error: number): Vector3
	local yaw = (math.random() - 0.5) * 2 * error
	local pitch = (math.random() - 0.5) * 2 * error
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(pitch, yaw, 0)).LookVector
end

local function stepShooting(bot: Bot, target: Model, now: number)
	if now - bot.firstSeenAt < bot.skill.reaction then return end
	if now < bot.nextShot then return end
	if CombatSystem.shieldUp(bot.char) or not CombatSystem.gunReady(bot.char) then return end
	local torso = (target:FindFirstChild("Torso") or target:FindFirstChild("Head")) :: BasePart?
	if not torso then return end
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetSpeed = if targetRoot then flat(targetRoot.AssemblyLinearVelocity).Magnitude else 0
	local offset = torso.Position - bot.head.Position
	if offset.Magnitude < 0.01 then return end
	local error = BotBrain._aimError(bot.skill.aimError, offset.Magnitude, targetSpeed, now - bot.firstSeenAt)
	CombatSystem.shoot(bot.char, bot.head.Position, jitter(offset.Unit, error))
	bot.nextShot = now + Constants.PISTOL_COOLDOWN + randomBetween(Constants.BOT_FIRE_HESITATION)
end

-- Shield: answer a threat after the reaction delay, chain after a break, drop
-- it to punish an enemy who just fired.

local function stepShield(bot: Bot, now: number)
	local me = bot.char
	local breakAt = CombatSystem.lastBreakAt(me)
	if breakAt > bot.lastBreakAt then
		bot.lastBreakAt = breakAt
		if math.random() < bot.skill.aggression then
			CombatSystem.raiseShield(me)
		end
		return
	end

	local target = bot.target
	local targetRoot = if target then target:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not target or not targetRoot then
		bot.threatRolledAt = nil
		bot.shieldRaiseAt = nil
		return
	end

	-- One roll when a threat starts and another every BOT_THREAT_REROLL while it
	-- lasts; the enemy firing or looking away ends the episode.
	local threat = CombatSystem.gunReady(target) and BotBrain._facing(targetRoot.Position, targetRoot.CFrame.LookVector, bot.root.Position)
	if threat then
		if not bot.threatRolledAt or now - bot.threatRolledAt >= Constants.BOT_THREAT_REROLL then
			bot.threatRolledAt = now
			if math.random() < bot.skill.shieldSense then
				bot.shieldRaiseAt = now + bot.skill.reaction
			end
		end
	else
		bot.threatRolledAt = nil
		bot.shieldRaiseAt = nil
	end
	if bot.shieldRaiseAt and now >= bot.shieldRaiseAt then
		bot.shieldRaiseAt = nil
		if not CombatSystem.shieldUp(me) then
			CombatSystem.raiseShield(me)
		end
	end

	if CombatSystem.shieldUp(me) and not CombatSystem.gunReady(target) and CombatSystem.gunReady(me) then
		CombatSystem.lowerShield(me)
		bot.nextShot = math.min(bot.nextShot, now + 0.15)
	end
end

-- Roaming: a path to the last sighting while it is fresh, else to a random spawn point.

local function pickDestination(bot: Bot, now: number): Vector3?
	if bot.lastSeenPos and now - bot.lastSeenAt < Constants.BOT_MEMORY_TIME and (bot.lastSeenPos - bot.root.Position).Magnitude > 6 then
		return bot.lastSeenPos
	end
	local cframe = MapManager.randomSpawnCFrame()
	return if cframe then cframe.Position else nil
end

local function computePath(bot: Bot, destination: Vector3)
	bot.computing = true
	task.spawn(function()
		local ok = pcall(function()
			bot.path:ComputeAsync(bot.root.Position, destination)
		end)
		if ok and bot.path.Status == Enum.PathStatus.Success then
			bot.waypoints = bot.path:GetWaypoints()
			bot.waypointIndex = 2
			bot.destination = destination
		else
			bot.waypoints = {}
			bot.nextPathAt = os.clock() + 0.5
		end
		bot.walkingTo = nil
		bot.computing = false
	end)
end

local function stepRoam(bot: Bot, now: number)
	bot.hum.AutoRotate = true
	if bot.computing then return end
	if bot.waypointIndex > #bot.waypoints then
		if now < bot.nextPathAt then return end
		local destination = pickDestination(bot, now)
		if destination then
			computePath(bot, destination)
		end
		return
	end

	local waypoint = bot.waypoints[bot.waypointIndex]
	if bot.walkingTo ~= waypoint then
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			bot.hum.Jump = true
		end
		bot.hum:MoveTo(waypoint.Position)
		bot.walkingTo = waypoint
		bot.waypointDeadline = now + Constants.BOT_WAYPOINT_TIMEOUT
	end

	if not CombatSystem.shieldUp(bot.char) then
		local remaining = if bot.destination then (bot.destination - bot.root.Position).Magnitude else 0
		local speed = if remaining > Constants.BOT_SPRINT_LEG then Constants.SPRINT_WALKSPEED else Constants.SAFE_WALKSPEED
		if bot.hum.WalkSpeed ~= speed then
			bot.hum.WalkSpeed = speed
		end
	end

	if flat(waypoint.Position - bot.root.Position).Magnitude < 3 then
		bot.waypointIndex += 1
		bot.walkingTo = nil
	elseif now > bot.waypointDeadline then
		-- Stuck: drop the path and pick somewhere else.
		bot.waypoints = {}
		bot.waypointIndex = 1
		bot.walkingTo = nil
	end
end

local function stepBot(bot: Bot, now: number, dt: number)
	if now >= bot.nextPerception then
		bot.nextPerception = now + Constants.BOT_PERCEPTION_INTERVAL
		perceive(bot, now)
	end
	local target = bot.target
	if target and target.Parent then
		if not bot.engaged then
			bot.engaged = true
			bot.waypoints = {}
			bot.waypointIndex = 1
			bot.walkingTo = nil
		end
		stepEngaged(bot, target, now, dt)
		stepShooting(bot, target, now)
	else
		if bot.engaged then
			bot.engaged = false
			bot.hum:Move(Vector3.zero, false)
		end
		stepRoam(bot, now)
	end
	stepShield(bot, now)
end

local function step(dt: number)
	local now = os.clock()
	for char, bot in bots do
		if not char.Parent or bot.hum.Health <= 0 then
			bots[char] = nil
		else
			stepBot(bot, now, dt)
		end
	end
end

function BotBrain.add(char: Model, skill: Skill)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = char:FindFirstChild("Head") :: BasePart?
	if not hum or not root or not head then return end
	local now = os.clock()
	bots[char] = {
		char = char,
		hum = hum,
		root = root,
		head = head,
		skill = skill,
		path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true }),
		target = nil,
		firstSeenAt = now,
		lastSeenAt = -math.huge,
		lastSeenPos = nil,
		nextPerception = now + math.random() * Constants.BOT_PERCEPTION_INTERVAL,
		engaged = false,
		strafeDir = 1,
		nextStrafeFlip = now,
		nextJump = now + randomBetween(Constants.BOT_JUMP_INTERVAL),
		nextShot = now,
		shieldRaiseAt = nil,
		threatRolledAt = nil,
		lastBreakAt = CombatSystem.lastBreakAt(char),
		waypoints = {},
		waypointIndex = 1,
		walkingTo = nil,
		waypointDeadline = 0,
		destination = nil,
		computing = false,
		nextPathAt = now,
	}
end

function BotBrain.remove(char: Model)
	local bot = bots[char]
	if not bot then return end
	bots[char] = nil
	bot.hum:Move(Vector3.zero, false)
	bot.hum.AutoRotate = true
end

function BotBrain.clear()
	for char in bots do
		BotBrain.remove(char)
	end
end

function BotBrain.init()
	RunService.Heartbeat:Connect(step)
end

return BotBrain
