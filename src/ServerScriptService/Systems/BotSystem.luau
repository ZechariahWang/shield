local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local CombatSystem = require(script.Parent.CombatSystem)
local MapManager = require(script.Parent.MapManager)
local WeaponModel = require(script.Parent.WeaponModel)
local BotAppearance = require(script.Parent.BotAppearance)
local BotAnimator = require(script.Parent.BotAnimator)
local BotBrain = require(script.Parent.BotBrain)

-- Server-driven combatants that count as players. Each bot is a clone of the NPC
-- rig with a generated name, a random avatar, the default pistol, the players'
-- movement animations (BotAnimator) and a per-bot skill roll driving BotBrain.
-- All combat goes through CombatSystem, so bots take and deal damage exactly
-- like players. A bot is an identity (name and skill) that lasts the match: an
-- eliminated bot's model is destroyed and a new one spawns RESPAWN_DELAY later
-- under the same name, so its score carries on.
local BotSystem = {}

local BOTS_FOLDER_NAME = "Bots"

type Identity = { name: string, skill: BotBrain.Skill }

local bots: { [Model]: Identity } = {}
local running = false
-- Bumped at every stop, so a respawn scheduled in one match never lands in the next.
local generation = 0

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

function BotSystem.isBot(char: Model): boolean
	return bots[char] ~= nil
end

-- How many bots a round fields; 0 when disabled.
function BotSystem.plannedCount(): number
	if not Constants.BOTS_ENABLED then return 0 end
	return Constants.BOT_COUNT
end

-- One life of a bot: a fresh model on the spawn point farthest from everyone,
-- spawn protected, with a brain at once when the match is already running.
local function spawnBot(identity: Identity)
	local rig = findRig()
	local cframe = MapManager.spawnCFrameAwayFrom(nil)
	if not rig or not cframe then return end
	local char = rig:Clone()
	char.Name = identity.name
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.BreakJointsOnDeath = false
		hum.WalkSpeed = Constants.SAFE_WALKSPEED
		hum.DisplayName = identity.name
	end
	char:PivotTo(cframe + Vector3.new(0, 4, 0))
	CollectionService:AddTag(char, Constants.IN_ROUND_TAG)
	char.Parent = getFolder()
	bots[char] = identity
	CombatSystem.registerBot(char)
	CombatSystem.protect(char)
	WeaponModel.attach(char, Constants.VIEWMODEL_DEFAULT_WEAPON)
	BotAnimator.attach(char)
	BotAppearance.apply(char)
	if running then
		BotBrain.add(char, identity.skill)
	end
end

-- An eliminated bot: the model goes, the identity comes back after RESPAWN_DELAY.
function BotSystem.remove(char: Model)
	local identity = bots[char]
	bots[char] = nil
	BotBrain.remove(char)
	BotAnimator.detach(char)
	CombatSystem.unregisterBot(char)
	char:Destroy()
	if not identity or not running then return end

	local scheduledIn = generation
	task.delay(Constants.RESPAWN_DELAY, function()
		if running and generation == scheduledIn then
			spawnBot(identity)
		end
	end)
end

-- Rolls the match's bots (names and skills) and spawns each one's first life.
function BotSystem.spawn()
	if BotSystem.plannedCount() == 0 then return end
	if not findRig() then
		warn("BotSystem: rig not found at ReplicatedStorage." .. table.concat(Constants.BOT_RIG_PATH, "."))
		return
	end
	local taken: { [string]: boolean } = {}
	for _ = 1, BotSystem.plannedCount() do
		local name = BotAppearance.randomName(taken)
		taken[name] = true
		spawnBot({ name = name, skill = BotBrain._rollSkill() })
	end
end

function BotSystem.start()
	running = true
	for char, identity in bots do
		BotBrain.add(char, identity.skill)
	end
end

-- Stops the brains but leaves the models standing so a victim's kill cam can
-- keep tracking its bot through the arena freeze; despawn() removes them.
function BotSystem.stop()
	running = false
	generation += 1
	BotBrain.clear()
	for char in bots do
		CombatSystem.unregisterBot(char)
	end
	table.clear(bots)
end

function BotSystem.despawn()
	BotAnimator.clear()
	local folder = Workspace:FindFirstChild(BOTS_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
end

function BotSystem.init()
	BotAnimator.init()
	BotBrain.init()
	BotSystem.stop()
	if BotSystem.plannedCount() > 0 and not findRig() then
		warn("BotSystem: rig not found at ReplicatedStorage." .. table.concat(Constants.BOT_RIG_PATH, ".") .. ": no bots will spawn")
	end
end

return BotSystem
