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

-- Speed along the rope: ramps from the speed already carried toward the anchor
-- up to GRAPPLE_SPEED, and brakes to GRAPPLE_ARRIVE_SPEED over the last studs.
function GrappleMath.pullSpeed(startSpeed: number, elapsed: number, distance: number): number
	local ramp = math.max(startSpeed, 0) + Constants.GRAPPLE_ACCEL * elapsed
	ramp = math.min(ramp, Constants.GRAPPLE_SPEED)
	local left = math.max(distance - Constants.GRAPPLE_ARRIVE_DISTANCE, 0)
	local brake = Constants.GRAPPLE_ARRIVE_SPEED + left * Constants.GRAPPLE_BRAKE_RATE
	return math.min(ramp, brake)
end

-- Steering velocity from a sideways and a vertical input (-1..1 each): across the
-- rope only, since the pull owns the axis along it. `direction` is the unit
-- vector to the anchor, `right` the unit vector sideways input pushes along.
function GrappleMath.steer(direction: Vector3, right: Vector3, sideways: number, vertical: number): Vector3
	local raw = right * sideways + Vector3.yAxis * vertical
	local across = raw - direction * raw:Dot(direction)
	local amount = across.Magnitude
	if amount > 1 then
		across = across / amount
	end
	return across * Constants.GRAPPLE_STEER_SPEED
end

-- The velocity with its speed capped; a non-finite velocity becomes zero.
function GrappleMath.clampSpeed(velocity: Vector3, maxSpeed: number): Vector3
	if not isFiniteVector(velocity) then return Vector3.zero end
	local speed = velocity.Magnitude
	if speed <= maxSpeed then return velocity end
	return velocity * (maxSpeed / speed)
end

return GrappleMath
