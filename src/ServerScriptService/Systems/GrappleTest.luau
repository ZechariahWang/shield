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
	local far = Constants.GRAPPLE_RANGE

	-- Pull from rest: speeds up toward the anchor and sags under the reduced gravity.
	local fromRest = GrappleMath.pullVelocity(Vector3.zero, ahead, ahead, far, dt)
	assert(near(fromRest.Z, -pullStep), "accelerates toward the anchor")
	assert(near(fromRest.Y, -gravityStep), "gravity keeps acting on the rope")
	assert(near(fromRest.X, 0), "nothing sideways from rest")

	-- Momentum carries through: speed toward the anchor is added to, speed across the rope bends the path.
	local carried = GrappleMath.pullVelocity(Vector3.new(0, 0, -30), ahead, ahead, far, dt)
	assert(near(carried.Z, -(30 + pullStep)), "speed toward the anchor is kept")
	local swinging = GrappleMath.pullVelocity(Vector3.new(20, 0, 0), ahead, ahead, far, dt)
	assert(near(swinging.X, 20 * math.exp(-Constants.GRAPPLE_SWING_DAMPING * dt)), "sideways speed decays at the swing damping")
	assert(swinging.X > 0 and swinging.X < 20, "damping only slows the swing")

	-- Taut rope: speed away from the anchor is dropped.
	local leaving = GrappleMath.pullVelocity(Vector3.new(0, 0, 40), ahead, ahead, far, dt)
	assert(near(leaving.Z, -pullStep), "moving away starts from rest")

	local tooFast = GrappleMath.pullVelocity(Vector3.new(0, 0, -500), ahead, ahead, far, dt)
	assert(near(tooFast.Magnitude, Constants.GRAPPLE_MAX_SPEED), "capped at the max speed")
	assert(GrappleMath.pullVelocity(Vector3.new(0 / 0, 0, 0), ahead, ahead, far, dt) == Vector3.zero, "nan velocity pulls nothing")

	-- Near the anchor the pull brakes, so the character arrives at it instead of flying past.
	local arrive = Constants.GRAPPLE_ARRIVE_DISTANCE
	local fullSpeed = Vector3.new(0, 0, -Constants.GRAPPLE_MAX_SPEED)
	local arriving = GrappleMath.pullVelocity(fullSpeed, ahead, ahead, arrive, dt)
	assert(near(arriving.Magnitude, Constants.GRAPPLE_ARRIVE_SPEED), "arrival speed at the anchor")
	local closing = GrappleMath.pullVelocity(fullSpeed, ahead, ahead, arrive + 5, dt)
	assert(closing.Magnitude > Constants.GRAPPLE_ARRIVE_SPEED and closing.Magnitude < Constants.GRAPPLE_MAX_SPEED, "brakes on approach")
	local drifting = GrappleMath.pullVelocity(Vector3.new(90, 0, 0), ahead, ahead, arrive, dt)
	assert(drifting.Magnitude <= Constants.GRAPPLE_ARRIVE_SPEED + 1e-4, "sideways speed is braked too")

	-- The pull follows the guide, not the rope: a guide leaning off the rope bends the path that way.
	local leanRight = (ahead + right).Unit
	local guided = GrappleMath.pullVelocity(Vector3.zero, ahead, leanRight, far, dt)
	assert(guided.X > 0 and guided.Z < 0, "the pull follows the guide")
	local turning = GrappleMath.pullVelocity(Vector3.new(0, 0, -100), ahead, leanRight, far, dt)
	assert(turning.X > 0, "speed toward the anchor turns toward the guide")
	local leavingGuided = GrappleMath.pullVelocity(Vector3.new(0, 0, 40), ahead, leanRight, far, dt)
	assert(leavingGuided.Z < 0, "the rope stays taut under a leaning guide")

	-- Guide: a steering input leans it off the rope by up to GRAPPLE_ARC_ANGLE toward
	-- that side, fading to head-on over the last GRAPPLE_ARC_FULL_DISTANCE studs.
	local arcAngle = math.rad(Constants.GRAPPLE_ARC_ANGLE)
	local function angleBetween(a: Vector3, b: Vector3): number
		return math.acos(math.clamp(a:Dot(b), -1, 1))
	end
	assert(GrappleMath.guide(ahead, right, 0, 0, far) == ahead, "no input: straight at the anchor")
	local arcRight = GrappleMath.guide(ahead, right, 1, 0, far)
	assert(near(angleBetween(arcRight, ahead), arcAngle), "full input leans by the arc angle")
	assert(arcRight.X > 0 and near(arcRight.Y, 0), "arc right")
	assert(near(arcRight.Magnitude, 1), "the guide is a unit vector")
	local arcLeft = GrappleMath.guide(ahead, right, -1, 0, far)
	assert(arcLeft.X < 0 and near(arcLeft.Y, 0), "arc left")
	local arcUp = GrappleMath.guide(ahead, right, 0, 1, far)
	assert(arcUp.Y > 0 and near(arcUp.X, 0), "arc up")
	local arcDown = GrappleMath.guide(ahead, right, 0, -1, far)
	assert(arcDown.Y < 0 and near(arcDown.X, 0), "arc down")
	local arcBoth = GrappleMath.guide(ahead, right, 1, 1, far)
	assert(near(angleBetween(arcBoth, ahead), arcAngle), "diagonal leans no further")
	assert(arcBoth.X > 0 and arcBoth.Y > 0, "diagonal direction")
	local halfway = GrappleMath.guide(ahead, right, 1, 0, Constants.GRAPPLE_ARC_FULL_DISTANCE / 2)
	assert(near(angleBetween(halfway, ahead), arcAngle / 2), "the lean fades on approach")
	assert(GrappleMath.guide(ahead, right, 1, 0, 0) == ahead, "head-on at the anchor")
	assert(GrappleMath.guide(right, right, 1, 0, far) == right, "input along the rope leans nothing")
	local climbing = Vector3.new(0, 0.6, -0.8)
	local lifted = GrappleMath.guide(climbing, right, 0, 1, far)
	assert(near(angleBetween(lifted, climbing), arcAngle * 0.8), "only the share of the input across the rope leans")
	assert(lifted.Y > climbing.Y, "arc up on a climbing rope")

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

	-- Hook flight: the hook takes time to reach the anchor, capped so a long shot still latches quickly.
	assert(near(GrappleMath.hookTime(0), 0), "no distance, no flight")
	local shortFlight = Constants.GRAPPLE_HOOK_MAX_TIME / 2
	assert(near(GrappleMath.hookTime(Constants.GRAPPLE_HOOK_SPEED * shortFlight), shortFlight), "flight time is distance over hook speed")
	assert(near(GrappleMath.hookTime(1e6), Constants.GRAPPLE_HOOK_MAX_TIME), "flight time is capped")
	assert(near(GrappleMath.hookProgress(0, 0.2), 0), "the hook starts at the hand")
	assert(near(GrappleMath.hookProgress(0.1, 0.2), 0.5), "halfway through the flight")
	assert(near(GrappleMath.hookProgress(1, 0.2), 1), "latched after the flight")
	assert(near(GrappleMath.hookProgress(0, 0), 1), "no flight time latches at once")

	print("GrappleTest: all checks passed")
end
