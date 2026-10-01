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
-- Speed away from the anchor is dropped (the rope is taut). The pull then follows
-- `guide` (GrappleMath.guide: the rope direction, leaned by the steering input):
-- speed along it is kept and grows by GRAPPLE_PULL_ACCEL, speed across it decays
-- at GRAPPLE_SWING_DAMPING, so the path bends onto the guide. Over the last studs
-- the whole speed brakes down to GRAPPLE_ARRIVE_SPEED, so the character arrives at
-- the anchor instead of flying past it. `direction` is the unit vector to the
-- anchor, `distance` the studs to it.
function GrappleMath.pullVelocity(velocity: Vector3, direction: Vector3, guide: Vector3, distance: number, dt: number): Vector3
	local awaySpeed = -velocity:Dot(direction)
	if awaySpeed > 0 then
		velocity = velocity + direction * awaySpeed
	end
	local alongSpeed = velocity:Dot(guide)
	local across = velocity - guide * alongSpeed
	across = across * math.exp(-Constants.GRAPPLE_SWING_DAMPING * dt)
	alongSpeed = math.max(alongSpeed, 0) + Constants.GRAPPLE_PULL_ACCEL * dt
	local gravity = Vector3.yAxis * (-Constants.GRAPPLE_GRAVITY * dt)
	local pulled = guide * alongSpeed + across + gravity
	local left = math.max(distance - Constants.GRAPPLE_ARRIVE_DISTANCE, 0)
	local brakeSpeed = Constants.GRAPPLE_ARRIVE_SPEED + left * Constants.GRAPPLE_BRAKE_RATE
	local maxSpeed = math.min(Constants.GRAPPLE_MAX_SPEED, brakeSpeed)
	return GrappleMath.clampSpeed(pulled, maxSpeed)
end

-- The unit direction the pull follows: the rope direction leaned toward the
-- steering input (sideways and vertical, -1..1 each) by up to GRAPPLE_ARC_ANGLE.
-- Heading a fixed angle off the anchor bows the path out to that side, and the
-- lean fades to nothing over the last GRAPPLE_ARC_FULL_DISTANCE studs, so the arc
-- curves back and meets the anchor head-on. `direction` is the unit vector to the
-- anchor, `right` the unit vector sideways input leans along, `distance` the studs left.
function GrappleMath.guide(direction: Vector3, right: Vector3, sideways: number, vertical: number, distance: number): Vector3
	local raw = right * sideways + Vector3.yAxis * vertical
	local across = raw - direction * raw:Dot(direction)
	local amount = across.Magnitude
	if amount < 1e-4 then return direction end
	local side = across / amount
	local input = math.min(amount, 1)
	local fade = math.clamp(distance / Constants.GRAPPLE_ARC_FULL_DISTANCE, 0, 1)
	local angle = math.rad(Constants.GRAPPLE_ARC_ANGLE) * input * fade
	return direction * math.cos(angle) + side * math.sin(angle)
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
