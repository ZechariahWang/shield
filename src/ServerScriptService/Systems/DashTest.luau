-- Command-bar check for the shared dash input math: require(game.ServerScriptService.Systems.DashTest)()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local DashMath = require(ReplicatedStorage.Shared.DashMath)

local function near(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < 1e-4
end

return function()
	local window = Constants.DASH_DOUBLE_TAP_WINDOW

	-- Double tap: the key again inside the window.
	assert(DashMath.isDoubleTap(10, 10 + window / 2), "second tap inside the window")
	assert(not DashMath.isDoubleTap(10, 10 + window * 2), "second tap too late")
	assert(not DashMath.isDoubleTap(-math.huge, 0.01), "a first tap alone")

	-- Server validation: a finite non-zero vector, returned at unit length with its height kept.
	assert(near(DashMath.unit(Vector3.new(0, 3, 4)) :: Vector3, Vector3.new(0, 0.6, 0.8)), "normalized, not flattened")
	assert(near(DashMath.unit(Vector3.new(0, 5, 0)) :: Vector3, Vector3.new(0, 1, 0)), "straight up is a direction")
	assert(near(DashMath.unit(Vector3.new(0, -2, 0)) :: Vector3, Vector3.new(0, -1, 0)), "straight down is a direction")
	assert(DashMath.unit(Vector3.zero) == nil, "zero is no direction")
	assert(DashMath.unit(Vector3.new(0 / 0, 0, 1)) == nil, "nan is refused")
	assert(DashMath.unit(Vector3.new(math.huge, 0, 1)) == nil, "infinite is refused")
	assert(DashMath.unit("left") == nil, "the wrong type is refused")
	assert(DashMath.unit(nil) == nil, "a missing direction is refused")

	print("DashTest: all checks passed")
end
