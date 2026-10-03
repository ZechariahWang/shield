-- Command-bar check for the shared dash input math: require(game.ServerScriptService.Systems.DashTest)()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local DashMath = require(ReplicatedStorage.Shared.DashMath)

local function near(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < 1e-4
end

return function()
	local window = Constants.DASH_DOUBLE_TAP_WINDOW

	-- Double tap: the same key again inside the window.
	assert(DashMath.isDoubleTap("W", 10, "W", 10 + window / 2), "second tap inside the window")
	assert(not DashMath.isDoubleTap("W", 10, "W", 10 + window * 2), "second tap too late")
	assert(not DashMath.isDoubleTap("A", 10, "D", 10 + window / 2), "another key is not a double tap")
	assert(not DashMath.isDoubleTap(nil, 0, "W", 0.01), "a first tap alone")

	-- Which way a movement key points.
	assert(DashMath.side("W") == "Forward" and DashMath.side("S") == "Backward", "forward and back keys")
	assert(DashMath.side("A") == "Left" and DashMath.side("D") == "Right", "side keys")
	assert(DashMath.side("Up") == "Forward" and DashMath.side("Down") == "Backward", "arrow keys")
	assert(DashMath.side("E") == nil, "not a movement key")

	-- Direction: the side relative to the camera, flattened onto the ground.
	local look = Vector3.new(0, 0, -1)
	assert(near(DashMath.direction("Forward", look) :: Vector3, Vector3.new(0, 0, -1)), "forward")
	assert(near(DashMath.direction("Backward", look) :: Vector3, Vector3.new(0, 0, 1)), "backward")
	assert(near(DashMath.direction("Right", look) :: Vector3, Vector3.new(1, 0, 0)), "right")
	assert(near(DashMath.direction("Left", look) :: Vector3, Vector3.new(-1, 0, 0)), "left")
	local down = Vector3.new(0, -0.8, -0.6)
	assert(near(DashMath.direction("Forward", down) :: Vector3, Vector3.new(0, 0, -1)), "a tilted camera still dashes level")
	assert(DashMath.direction("Forward", Vector3.new(0, -1, 0)) == nil, "a camera looking straight down has no forward")

	-- Server validation: a finite vector with a horizontal part, returned level and unit length.
	assert(near(DashMath.horizontal(Vector3.new(3, 5, 4)) :: Vector3, Vector3.new(0.6, 0, 0.8)), "flattened and normalized")
	assert(DashMath.horizontal(Vector3.new(0, 1, 0)) == nil, "straight up is no direction")
	assert(DashMath.horizontal(Vector3.zero) == nil, "zero is no direction")
	assert(DashMath.horizontal(Vector3.new(0 / 0, 0, 1)) == nil, "nan is refused")
	assert(DashMath.horizontal(Vector3.new(math.huge, 0, 1)) == nil, "infinite is refused")
	assert(DashMath.horizontal("left") == nil, "the wrong type is refused")
	assert(DashMath.horizontal(nil) == nil, "a missing direction is refused")

	print("DashTest: all checks passed")
end
