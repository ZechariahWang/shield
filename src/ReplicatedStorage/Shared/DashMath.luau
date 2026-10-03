local Constants = require(script.Parent.Constants)

-- Pure dash input math shared by DashController (the double tap and its
-- direction) and AbilitySystem (validating the direction the client sent).
local DashMath = {}

local SIDES = { W = "Forward", Up = "Forward", S = "Backward", Down = "Backward", A = "Left", D = "Right" }

-- The side a movement key dashes to, nil for any other key.
function DashMath.side(keyName: string): string?
	return SIDES[keyName]
end

-- True when `key` pressed at `now` is the second tap of the key last pressed at `lastAt`.
function DashMath.isDoubleTap(lastKey: string?, lastAt: number, key: string, now: number): boolean
	if lastKey ~= key then return false end
	return now - lastAt <= Constants.DASH_DOUBLE_TAP_WINDOW
end

-- A finite vector's horizontal part as a unit vector, nil when there is none.
function DashMath.horizontal(direction: any): Vector3?
	if typeof(direction) ~= "Vector3" then return nil end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local length = flat.Magnitude
	if length ~= length or length == math.huge then return nil end
	if length < 1e-3 then return nil end
	return flat / length
end

-- The level unit direction of `side` for a camera looking along `look`.
function DashMath.direction(side: string, look: Vector3): Vector3?
	local forward = DashMath.horizontal(look)
	if not forward then return nil end
	local right = forward:Cross(Vector3.yAxis)
	if side == "Forward" then return forward end
	if side == "Backward" then return -forward end
	if side == "Right" then return right end
	if side == "Left" then return -right end
	return nil
end

return DashMath
