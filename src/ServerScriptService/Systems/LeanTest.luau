-- Command-bar check for the lean math: require(game.ServerScriptService.Systems.LeanTest)()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
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

	-- On the rope the lean follows the velocity instead, up to GRAPPLE_LEAN_ANGLE at full grapple speed.
	local function tilt(c0: CFrame): number
		local up = torsoFor(c0).UpVector
		return math.deg(math.acos(math.clamp(up:Dot(Vector3.yAxis), -1, 1)))
	end
	local maxSpeed = Constants.GRAPPLE_MAX_SPEED
	assert(LeanSystem._grappleMove(Vector3.zero) == Vector3.zero, "hanging still stays upright")
	local flying = LeanSystem._target(R6_ROOT_C0, LeanSystem._grappleMove(Vector3.new(0, 0, -maxSpeed)))
	assert(math.abs(tilt(flying) - Constants.GRAPPLE_LEAN_ANGLE) < 0.01, "full speed leans the grapple angle, got " .. tilt(flying))
	assert(torsoFor(flying).UpVector.Z < 0, "flying forward tips forward")
	local halfSpeed = LeanSystem._target(R6_ROOT_C0, LeanSystem._grappleMove(Vector3.new(0, 0, -maxSpeed / 2)))
	assert(math.abs(tilt(halfSpeed) - Constants.GRAPPLE_LEAN_ANGLE / 2) < 0.01, "half speed leans half")
	local tooFast = LeanSystem._target(R6_ROOT_C0, LeanSystem._grappleMove(Vector3.new(0, 0, -maxSpeed * 3)))
	assert(math.abs(tilt(tooFast) - Constants.GRAPPLE_LEAN_ANGLE) < 0.01, "the lean is capped")
	assert(LeanSystem._grappleMove(Vector3.new(0, maxSpeed, 0)) == Vector3.zero, "vertical speed leans nothing")

	print("LeanTest: all passed")
end
