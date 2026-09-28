-- Command-bar check for the pure bot decision helpers: require(game.ServerScriptService.Systems.BotBrainTest)()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local BotBrain = require(game.ServerScriptService.Systems.BotBrain)

return function()
	-- Aim error: the rolled base at the reference distance on a still, freshly seen target.
	local base = 0.05
	local ref = Constants.BOT_AIM_REFERENCE_DISTANCE
	assert(math.abs(BotBrain._aimError(base, ref, 0, 0) - base) < 1e-6, "base error at reference")
	assert(BotBrain._aimError(base, ref * 4, 0, 0) > base, "farther is worse")
	assert(BotBrain._aimError(base, ref, Constants.SAFE_WALKSPEED, 0) > base, "moving target is worse")
	assert(BotBrain._aimError(base, ref, 0, 3) < base, "tracking for a while is better")
	assert(BotBrain._aimError(base, 0, 0, 0) > 0, "never zero")

	-- Hold distance: advance when far, back off when close, hold in the band.
	local band = Constants.BOT_ENGAGE_DISTANCE
	assert(BotBrain._holdMove(band[2] + 10) == 1, "advance when far")
	assert(BotBrain._holdMove(band[1] - 5) == -1, "retreat when close")
	assert(BotBrain._holdMove((band[1] + band[2]) / 2) == 0, "hold in band")

	-- Threat: an enemy looking at the bot within the cone, not one looking away.
	local bot = Vector3.new(0, 0, 0)
	local enemy = Vector3.new(0, 0, 30)
	assert(BotBrain._facing(enemy, Vector3.new(0, 0, -1), bot), "looking straight at the bot")
	assert(BotBrain._facing(enemy, Vector3.new(0.05, 0, -1).Unit, bot), "inside the cone")
	assert(not BotBrain._facing(enemy, Vector3.new(1, 0, 0), bot), "looking sideways")
	assert(not BotBrain._facing(enemy, Vector3.new(0, 0, 1), bot), "looking away")

	-- Skill rolls land inside their ranges.
	for _ = 1, 20 do
		local skill = BotBrain._rollSkill()
		assert(skill.reaction >= Constants.BOT_REACTION_TIME[1] and skill.reaction <= Constants.BOT_REACTION_TIME[2], "reaction in range")
		assert(skill.aimError >= Constants.BOT_AIM_ERROR[1] and skill.aimError <= Constants.BOT_AIM_ERROR[2], "aim error in range")
		assert(skill.aggression >= Constants.BOT_AGGRESSION[1] and skill.aggression <= Constants.BOT_AGGRESSION[2], "aggression in range")
		assert(skill.shieldSense >= Constants.BOT_SHIELD_SENSE[1] and skill.shieldSense <= Constants.BOT_SHIELD_SENSE[2], "shield sense in range")
	end

	print("BotBrainTest: all checks passed")
end
