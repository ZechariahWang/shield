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

	print("MovementBlendTest: all checks passed")
end
