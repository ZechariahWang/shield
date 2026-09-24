local ServerScriptService = game:GetService("ServerScriptService")

local Systems = ServerScriptService:WaitForChild("Systems")

local PlayerState = require(Systems.PlayerState)
local MapManager = require(Systems.MapManager)
local WeaponStore = require(Systems.WeaponStore)
local AbilitySystem = require(Systems.AbilitySystem)
local CombatSystem = require(Systems.CombatSystem)
local BotSystem = require(Systems.BotSystem)
local RoundManager = require(Systems.RoundManager)

PlayerState.init()
MapManager.init()
WeaponStore.init()
AbilitySystem.init()
CombatSystem.init()
BotSystem.init()
RoundManager.init()
