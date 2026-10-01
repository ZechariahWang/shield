local Constants = require(script.Parent.Constants)

-- Pure grapple math shared by GrappleController (the pull) and GrappleSystem (validation).
local GrappleMath = {}

local function isFiniteVector(v: Vector3): boolean
	local components = { v.X, v.Y, v.Z }
	for _, n in components do
		if n ~= n then return false end
		if n == math.huge or n == -math.huge then return false end
	end
	return true
end

-- A finite point within GRAPPLE_RANGE plus `slack` studs of the root.
function GrappleMath.validAnchor(rootPosition: Vector3, anchor: any, slack: number): boolean
	if typeof(anchor) ~= "Vector3" then return false end
	if not isFiniteVector(anchor) then return false end
	local distance = (anchor - rootPosition).Magnitude
	return distance <= Constants.GRAPPLE_RANGE + slack
end

-- The velocity after `dt` seconds on the rope, from the velocity actually carried.
-- Speed toward the anchor is kept and grows by GRAPPLE_PULL_ACCEL; speed away from
-- it is dropped (the rope is taut); speed across the rope is kept, lightly damped,
-- so the path bends into the anchor. `direction` is the unit vector to the anchor,
-- `steerAccel` the acceleration from GrappleMath.steer.
function GrappleMath.pullVelocity(velocity: Vector3, direction: Vector3, steerAccel: Vector3, dt: number): Vector3
	local alongSpeed = velocity:Dot(direction)
	local across = velocity - direction * alongSpeed
	across = across * math.exp(-Constants.GRAPPLE_SWING_DAMPING * dt)
	alongSpeed = math.max(alongSpeed, 0) + Constants.GRAPPLE_PULL_ACCEL * dt
	local gravity = Vector3.yAxis * (-Constants.GRAPPLE_GRAVITY * dt)
	local pulled = direction * alongSpeed + across + steerAccel * dt + gravity
	return GrappleMath.clampSpeed(pulled, Constants.GRAPPLE_MAX_SPEED)
end

-- Steering acceleration from a sideways and a vertical input (-1..1 each): across
-- the rope only, since the pull owns the axis along it. `direction` is the unit
-- vector to the anchor, `right` the unit vector sideways input pushes along.
function GrappleMath.steer(direction: Vector3, right: Vector3, sideways: number, vertical: number): Vector3
	local raw = right * sideways + Vector3.yAxis * vertical
	local across = raw - direction * raw:Dot(direction)
	local amount = across.Magnitude
	if amount > 1 then
		across = across / amount
	end
	return across * Constants.GRAPPLE_STEER_ACCEL
end

-- The velocity to leave the rope with: the carried velocity plus
-- GRAPPLE_RELEASE_LIFT upward, capped at GRAPPLE_MAX_SPEED.
function GrappleMath.releaseVelocity(velocity: Vector3): Vector3
	local lifted = velocity + Vector3.yAxis * Constants.GRAPPLE_RELEASE_LIFT
	return GrappleMath.clampSpeed(lifted, Constants.GRAPPLE_MAX_SPEED)
end

-- The horizontal velocity after `dt` seconds of flight off the rope: the speed
-- carried drags off slowly and `moveDirection` (the humanoid's, horizontal) bends it.
function GrappleMath.carryVelocity(velocity: Vector3, moveDirection: Vector3, dt: number): Vector3
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local dragged = horizontal * math.exp(-Constants.GRAPPLE_CARRY_DRAG * dt)
	local steered = dragged + moveDirection * (Constants.GRAPPLE_CARRY_STEER_ACCEL * dt)
	return GrappleMath.clampSpeed(steered, Constants.GRAPPLE_MAX_SPEED)
end

-- The velocity with its speed capped; a non-finite velocity becomes zero.
function GrappleMath.clampSpeed(velocity: Vector3, maxSpeed: number): Vector3
	if not isFiniteVector(velocity) then return Vector3.zero end
	local speed = velocity.Magnitude
	if speed <= maxSpeed then return velocity end
	return velocity * (maxSpeed / speed)
end

return GrappleMath
