-- Command-bar check for the shared grapple math: require(game.ServerScriptService.Systems.GrappleTest)()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local GrappleMath = require(ReplicatedStorage.Shared.GrappleMath)

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-4
end

return function()
	local root = Vector3.new(10, 5, 10)

	-- Anchor: a finite point within range of the root, with the given slack on top.
	assert(GrappleMath.validAnchor(root, root + Vector3.new(0, Constants.GRAPPLE_RANGE, 0), 0), "anchor at range")
	assert(not GrappleMath.validAnchor(root, root + Vector3.new(0, Constants.GRAPPLE_RANGE + 1, 0), 0), "anchor past range")
	assert(GrappleMath.validAnchor(root, root + Vector3.new(0, Constants.GRAPPLE_RANGE + 1, 0), 2), "slack extends range")
	assert(not GrappleMath.validAnchor(root, Vector3.new(0 / 0, 0, 0), 0), "nan anchor")
	assert(not GrappleMath.validAnchor(root, Vector3.new(math.huge, 0, 0), 0), "infinite anchor")
	assert(not GrappleMath.validAnchor(root, "wall", 0), "anchor of the wrong type")
	assert(not GrappleMath.validAnchor(root, nil, 0), "missing anchor")

	local ahead = Vector3.new(0, 0, -1)
	local right = Vector3.new(1, 0, 0)
	local dt = 0.1
	local pullStep = Constants.GRAPPLE_PULL_ACCEL * dt
	local gravityStep = Constants.GRAPPLE_GRAVITY * dt

	-- Pull from rest: speeds up toward the anchor and sags under the reduced gravity.
	local fromRest = GrappleMath.pullVelocity(Vector3.zero, ahead, Vector3.zero, dt)
	assert(near(fromRest.Z, -pullStep), "accelerates toward the anchor")
	assert(near(fromRest.Y, -gravityStep), "gravity keeps acting on the rope")
	assert(near(fromRest.X, 0), "nothing sideways from rest")

	-- Momentum carries through: speed toward the anchor is added to, speed across the rope bends the path.
	local carried = GrappleMath.pullVelocity(Vector3.new(0, 0, -30), ahead, Vector3.zero, dt)
	assert(near(carried.Z, -(30 + pullStep)), "speed toward the anchor is kept")
	local swinging = GrappleMath.pullVelocity(Vector3.new(20, 0, 0), ahead, Vector3.zero, dt)
	assert(near(swinging.X, 20 * math.exp(-Constants.GRAPPLE_SWING_DAMPING * dt)), "sideways speed is kept, lightly damped")
	assert(swinging.X > 0 and swinging.X < 20, "damping only slows the swing")

	-- Taut rope: speed away from the anchor is dropped.
	local leaving = GrappleMath.pullVelocity(Vector3.new(0, 0, 40), ahead, Vector3.zero, dt)
	assert(near(leaving.Z, -pullStep), "moving away starts from rest")

	local tooFast = GrappleMath.pullVelocity(Vector3.new(0, 0, -500), ahead, Vector3.zero, dt)
	assert(near(tooFast.Magnitude, Constants.GRAPPLE_MAX_SPEED), "capped at the max speed")
	local steered = GrappleMath.pullVelocity(Vector3.zero, ahead, Vector3.new(50, 0, 0), dt)
	assert(near(steered.X, 50 * dt), "steering accelerates")
	assert(GrappleMath.pullVelocity(Vector3.new(0 / 0, 0, 0), ahead, Vector3.zero, dt) == Vector3.zero, "nan velocity pulls nothing")

	-- Steering: across the rope only, at most GRAPPLE_STEER_ACCEL.
	local steerSpeed = Constants.GRAPPLE_STEER_ACCEL
	assert(GrappleMath.steer(ahead, right, 0, 0) == Vector3.zero, "no input, no steering")
	local sideways = GrappleMath.steer(ahead, right, 1, 0)
	assert(near(sideways.X, steerSpeed) and near(sideways.Y, 0) and near(sideways.Z, 0), "steer right")
	local left = GrappleMath.steer(ahead, right, -1, 0)
	assert(near(left.X, -steerSpeed), "steer left")
	local up = GrappleMath.steer(ahead, right, 0, 1)
	assert(near(up.Y, steerSpeed) and near(up.X, 0), "steer up")
	local down = GrappleMath.steer(ahead, right, 0, -1)
	assert(near(down.Y, -steerSpeed), "steer down")
	local both = GrappleMath.steer(ahead, right, 1, 1)
	assert(near(both.Magnitude, steerSpeed), "diagonal is not faster")
	assert(both.X > 0 and both.Y > 0, "diagonal direction")
	-- Input along the rope adds nothing: the pull owns that axis.
	assert(near(GrappleMath.steer(right, right, 1, 0).Magnitude, 0), "sideways along the rope is dropped")
	local climbing = Vector3.new(0, 0.6, -0.8)
	local lift = GrappleMath.steer(climbing, right, 0, 1)
	assert(near(lift:Dot(climbing), 0), "steering stays across a climbing rope")
	assert(lift.Y > 0 and lift.Magnitude <= steerSpeed + 1e-4, "lift on a climbing rope")

	-- Release clamp: direction kept, speed capped.
	local slow = Vector3.new(3, 4, 0)
	assert(GrappleMath.clampSpeed(slow, 10) == slow, "slow velocity untouched")
	local fast = GrappleMath.clampSpeed(Vector3.new(300, 400, 0), 50)
	assert(near(fast.Magnitude, 50), "fast velocity capped")
	assert(near(fast.X, 30) and near(fast.Y, 40), "direction kept")
	assert(GrappleMath.clampSpeed(Vector3.zero, 50) == Vector3.zero, "zero velocity")
	assert(GrappleMath.clampSpeed(Vector3.new(0 / 0, 0, 0), 50) == Vector3.zero, "nan velocity is dropped")

	-- Release: the carried velocity is kept, with a hop on top.
	local released = GrappleMath.releaseVelocity(Vector3.new(0, 0, -50))
	assert(near(released.Z, -50), "momentum kept on release")
	assert(near(released.Y, Constants.GRAPPLE_RELEASE_LIFT), "hop on release")
	assert(near(released.X, 0), "nothing sideways")
	local capped = GrappleMath.releaseVelocity(Vector3.new(0, 0, -500))
	assert(near(capped.Magnitude, Constants.GRAPPLE_MAX_SPEED), "release speed is capped")
	assert(GrappleMath.releaseVelocity(Vector3.new(0 / 0, 0, 0)) == Vector3.zero, "nan velocity releases nothing")

	-- Carry after the release: horizontal only, slowly dragging, steered by the movement input.
	local coasting = GrappleMath.carryVelocity(Vector3.new(100, -50, 0), Vector3.zero, dt)
	assert(near(coasting.X, 100 * math.exp(-Constants.GRAPPLE_CARRY_DRAG * dt)), "drag slows the carry")
	assert(coasting.X > 90, "most of the speed survives a step")
	assert(near(coasting.Y, 0), "the carry leaves the vertical axis alone")
	local turned = GrappleMath.carryVelocity(Vector3.new(100, 0, 0), ahead, dt)
	assert(near(turned.Z, -Constants.GRAPPLE_CARRY_STEER_ACCEL * dt), "movement input steers the carry")
	local overCap = GrappleMath.carryVelocity(Vector3.new(500, 0, 0), Vector3.zero, dt)
	assert(overCap.Magnitude <= Constants.GRAPPLE_MAX_SPEED + 1e-4, "carry speed is capped")
	assert(GrappleMath.carryVelocity(Vector3.new(0 / 0, 0, 0), Vector3.zero, dt) == Vector3.zero, "nan velocity carries nothing")

	print("GrappleTest: all checks passed")
end
