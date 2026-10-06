local Constants = require(script.Parent.Constants)

-- Pure dash input math shared by DashController (the double tap) and
-- AbilitySystem (validating the direction the client sent).
local DashMath = {}

-- True when a tap at `now` is the second tap of the one at `lastAt`.
function DashMath.isDoubleTap(lastAt: number, now: number): boolean
	return now - lastAt <= Constants.DASH_DOUBLE_TAP_WINDOW
end

-- A finite non-zero vector as a unit vector, nil for anything else.
function DashMath.unit(direction: any): Vector3?
	if typeof(direction) ~= "Vector3" then return nil end
	local length = direction.Magnitude
	if length ~= length or length == math.huge then return nil end
	if length < 1e-3 then return nil end
	return direction / length
end

return DashMath
