-- Command-bar check for the lean math: require(game.ServerScriptService.Systems.LeanTest)()
local LeanSystem = require(script.Parent.LeanSystem)

local R6_ROOT_C0 = CFrame.Angles(-math.pi / 2, 0, math.pi) -- stock RootJoint C0 and C1

-- Torso frame for an identity root: Root * C0 * C1:Inverse().
local function torsoFor(c0: CFrame): CFrame
	return c0 * R6_ROOT_C0:Inverse()
end

return function()
	local upright = torsoFor(LeanSystem._target(R6_ROOT_C0, Vector3.zero))
	assert(upright.UpVector:FuzzyEq(Vector3.yAxis), "no input keeps the torso upright")

	-- Root space: -Z is forward, +X is right. The torso's up vector should tip that way.
	local forward = torsoFor(LeanSystem._target(R6_ROOT_C0, Vector3.new(0, 0, -1)))
	assert(forward.UpVector.Z < -0.05, "running forward tips the torso forward")
	assert(math.abs(forward.UpVector.X) < 0.01, "forward lean has no sideways tilt")

	local back = torsoFor(LeanSystem._target(R6_ROOT_C0, Vector3.new(0, 0, 1)))
	assert(back.UpVector.Z > 0.05, "backpedalling tips the torso back")

	local right = torsoFor(LeanSystem._target(R6_ROOT_C0, Vector3.new(1, 0, 0)))
	assert(right.UpVector.X > 0.05, "strafing right tips the torso right")
	assert(math.abs(right.UpVector.Z) < 0.01, "side lean has no forward tilt")

	local left = torsoFor(LeanSystem._target(R6_ROOT_C0, Vector3.new(-1, 0, 0)))
	assert(left.UpVector.X < -0.05, "strafing left tips the torso left")

	-- The lean stays within LEAN_MAX_ANGLE and keeps the torso facing forward.
	local angle = math.deg(math.acos(math.clamp(forward.UpVector:Dot(Vector3.yAxis), -1, 1)))
	assert(angle > 1 and angle <= 8.01, "forward lean is the configured angle, got " .. angle)
	assert(forward.LookVector.Z < -0.9, "leaning does not turn the torso")

	print("LeanTest: all passed")
end
