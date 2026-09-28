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
-- like players.
local BotSystem = {}

local BOTS_FOLDER_NAME = "Bots"

local bots: { [Model]: BotBrain.Skill } = {}

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

-- Bots still standing in the current round, by model name.
function BotSystem.aliveNames(): { string }
	local names: { string } = {}
	for char in bots do
		table.insert(names, char.Name)
	end
	table.sort(names)
	return names
end

function BotSystem.remove(char: Model)
	bots[char] = nil
	BotBrain.remove(char)
	BotAnimator.detach(char)
	CombatSystem.unregisterBot(char)
	char:Destroy()
end

-- Clone the rigs onto spawn points. Called at Reveal so bots are visible during positioning.
function BotSystem.spawn()
	if BotSystem.plannedCount() == 0 then return end
	local rig = findRig()
	if not rig then
		warn("BotSystem: rig not found at ReplicatedStorage." .. table.concat(Constants.BOT_RIG_PATH, "."))
		return
	end
	local folder = getFolder()
	local taken: { [string]: boolean } = {}
	for _ = 1, BotSystem.plannedCount() do
		local cframe = MapManager.randomSpawnCFrame()
		if not cframe then break end
		local char = rig:Clone()
		local name = BotAppearance.randomName(taken)
		taken[name] = true
		char.Name = name
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.BreakJointsOnDeath = false
			hum.WalkSpeed = Constants.SAFE_WALKSPEED
			hum.DisplayName = name
		end
		char:PivotTo(cframe + Vector3.new(0, 4, 0))
		CollectionService:AddTag(char, Constants.IN_ROUND_TAG)
		char.Parent = folder
		bots[char] = BotBrain._rollSkill()
		CombatSystem.registerBot(char)
		WeaponModel.attach(char, Constants.VIEWMODEL_DEFAULT_WEAPON)
		BotAnimator.attach(char)
		BotAppearance.apply(char)
	end
end

function BotSystem.start()
	for char, skill in bots do
		BotBrain.add(char, skill)
	end
end

-- Stops the brains but leaves the models standing so a victim's kill cam can
-- keep tracking its bot through the arena freeze; despawn() removes them.
function BotSystem.stop()
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
