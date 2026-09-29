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

	-- Pull speed far from the anchor: ramps from the starting speed up to the cap.
	local far = Constants.GRAPPLE_RANGE
	assert(near(GrappleMath.pullSpeed(20, 0, far), 20), "starts at the current speed")
	assert(near(GrappleMath.pullSpeed(0, 0.1, far), Constants.GRAPPLE_ACCEL * 0.1), "ramps with time")
	assert(near(GrappleMath.pullSpeed(0, 100, far), Constants.GRAPPLE_SPEED), "capped at the grapple speed")
	assert(near(GrappleMath.pullSpeed(500, 0, far), Constants.GRAPPLE_SPEED), "a fast start is capped too")
	assert(near(GrappleMath.pullSpeed(-30, 0, far), 0), "moving away starts from rest")

	-- Near the anchor the pull brakes so the character meets the wall slowly.
	local arrive = Constants.GRAPPLE_ARRIVE_DISTANCE
	assert(near(GrappleMath.pullSpeed(0, 100, arrive), Constants.GRAPPLE_ARRIVE_SPEED), "arrival speed at the anchor")
	assert(near(GrappleMath.pullSpeed(0, 100, 0), Constants.GRAPPLE_ARRIVE_SPEED), "never below the arrival speed")
	local closing = GrappleMath.pullSpeed(0, 100, arrive + 5)
	assert(closing > Constants.GRAPPLE_ARRIVE_SPEED and closing < Constants.GRAPPLE_SPEED, "brakes on approach")

	-- Steering: across the rope only, at most GRAPPLE_STEER_SPEED.
	local steerSpeed = Constants.GRAPPLE_STEER_SPEED
	local ahead = Vector3.new(0, 0, -1)
	local right = Vector3.new(1, 0, 0)
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

	print("GrappleTest: all checks passed")
end
