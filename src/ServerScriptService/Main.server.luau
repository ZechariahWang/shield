local ServerScriptService = game:GetService("ServerScriptService")

local Systems = ServerScriptService:WaitForChild("Systems")

local PlayerState = require(Systems.PlayerState)
local MapManager = require(Systems.MapManager)
local Store = require(Systems.Store)
local AbilitySystem = require(Systems.AbilitySystem)
local CombatSystem = require(Systems.CombatSystem)
local BotSystem = require(Systems.BotSystem)
local RoundManager = require(Systems.RoundManager)

PlayerState.init()
MapManager.init()
Store.init()
AbilitySystem.init()
CombatSystem.init()
BotSystem.init()
RoundManager.init()
