-- Command-bar check for the shared movement animation blend: require(game.ServerScriptService.Systems.MovementBlendTest)()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local MovementBlend = require(ReplicatedStorage.Shared.MovementBlend)

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-4
end

return function()
	-- Standing still on the ground: idle only.
	local still = MovementBlend.weights(Vector3.zero, 0, true, false)
	assert(near(still.Idle, 1) and near(still.Forward, 0) and near(still.Run, 0), "still is idle")

	-- Full forward: the forward walk alone.
	local forward = MovementBlend.weights(Vector3.new(0, 0, -1), 1, true, false)
	assert(near(forward.Forward, 1) and near(forward.Idle, 0) and near(forward.Backward, 0), "forward walk")

	-- Sprinting hands the forward share to the run track.
	local run = MovementBlend.weights(Vector3.new(0, 0, -1), 1, true, true)
	assert(near(run.Run, 1) and near(run.Forward, 0), "sprint runs")

	-- Diagonal splits between the two walks and sums to the input amount.
	local diagonal = MovementBlend.weights(Vector3.new(0.7071, 0, -0.7071), 1, true, false)
	assert(near(diagonal.Forward, 0.5) and near(diagonal.Right, 0.5) and near(diagonal.Idle, 0), "diagonal")

	-- Half input walks at half weight with idle filling the rest.
	local half = MovementBlend.weights(Vector3.new(0, 0, -0.5), 0.5, true, false)
	assert(near(half.Forward, 0.5) and near(half.Idle, 0.5), "half input")

	-- Airborne drops every track so the stock fall shows.
	local air = MovementBlend.weights(Vector3.new(0, 0, -1), 1, false, false)
	for _, w in air do
		assert(near(w, 0), "airborne is empty")
	end

	-- Playback: idle is fixed, walks and run scale from their reference speeds, never below the floor.
	assert(near(MovementBlend.playback("Idle", 30), 1), "idle playback")
	assert(near(MovementBlend.playback("Forward", Constants.MOVEMENT_ANIM_REFERENCE_SPEED), 1), "walk playback")
	assert(near(MovementBlend.playback("Run", Constants.MOVEMENT_RUN_REFERENCE_SPEED), 1), "run playback")
	assert(near(MovementBlend.playback("Left", 0), 0.1), "playback floor")

	-- Dash clip: the dominant axis picks it, a standing dash is a forward one.
	assert(MovementBlend.dashTrack(Vector3.new(1, 0, 0)) == "Right", "dash right")
	assert(MovementBlend.dashTrack(Vector3.new(-0.9, 0, -0.4)) == "Left", "dash left dominates")
	assert(MovementBlend.dashTrack(Vector3.new(0.3, 0, -0.9)) == "Forward", "dash forward")
	assert(MovementBlend.dashTrack(Vector3.new(0, 0, 1)) == "Backward", "dash backward")
	assert(MovementBlend.dashTrack(Vector3.zero) == "Forward", "standing dash is forward")

	-- Playback is capped, so a dash or a grapple landing does not spin the legs.
	assert(near(MovementBlend.playback("Forward", 500), Constants.MOVEMENT_ANIM_MAX_PLAYBACK), "playback cap")
	assert(near(MovementBlend.playback("Run", 500), Constants.MOVEMENT_ANIM_MAX_PLAYBACK), "run playback cap")

	-- Fit: the playback speed that makes a one-shot clip last the move it belongs to.
	assert(near(MovementBlend.fitSpeed(1, 0.5), 2), "a clip twice as long plays twice as fast")
	assert(near(MovementBlend.fitSpeed(0.35, 0.7), 0.5), "a short clip is stretched")
	assert(near(MovementBlend.fitSpeed(0, 0.5), 1), "an unloaded clip plays as authored")
	assert(near(MovementBlend.fitSpeed(1, 0), 1), "no duration plays as authored")

	-- Leader: the heaviest locomotion track sets the stride phase the others join in on.
	assert(MovementBlend.leader(forward) == "Forward", "forward leads")
	assert(MovementBlend.leader(run) == "Run", "run leads")
	assert(MovementBlend.leader(still) == nil, "idle has no leader")
	local mostlyRight = MovementBlend.weights(Vector3.new(0.9, 0, -0.4), 1, true, false)
	assert(MovementBlend.leader(mostlyRight) == "Right", "the heavier walk leads")

	-- Follow: a track of another length plays at the speed that gives it the leader's cycle time.
	assert(near(MovementBlend.followSpeed(1, 0.8, 0.4), 0.5), "a shorter clip slows to the leader's cycle")
	assert(near(MovementBlend.followSpeed(1.5, 0.8, 0.8), 1.5), "equal lengths share the speed")
	assert(near(MovementBlend.followSpeed(1.5, 0, 0.8), 1.5), "an unloaded leader passes its speed on")

	print("MovementBlendTest: all checks passed")
end
