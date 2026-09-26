local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- Tips every R6 combatant's torso toward its movement direction by offsetting
-- HumanoidRootPart.RootJoint.C0. Server side so the lean replicates to everyone;
-- MoveDirection already replicates from each client.
local LeanSystem = {}

local SNAP_EPSILON = 1e-3
-- The rest pose lives on the joint itself: a Lua table keyed by the Instance would
-- lose its entry whenever the Instance's proxy is collected, and re-reading a
-- leaned C0 as the base makes the lean accumulate.
local BASE_ATTRIBUTE = "LeanBaseC0"

-- The RootJoint's C0 is rotated (-90 about X, 180 about Z), so a rotation about the
-- joint's X reads as pitch on the torso and one about its Y reads as roll.
function LeanSystem._target(base: CFrame, localMove: Vector3): CFrame
	local max = math.rad(Constants.LEAN_MAX_ANGLE)
	local pitch = -localMove.Z * max
	local roll = -localMove.X * max
	return base * CFrame.Angles(pitch, roll, 0)
end

local function stepCharacter(char: Model, alpha: number)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") then return end
	local joint = root:FindFirstChild("RootJoint")
	if not joint or not joint:IsA("Motor6D") then return end

	local base = joint:GetAttribute(BASE_ATTRIBUTE)
	if typeof(base) ~= "CFrame" then
		base = joint.C0
		joint:SetAttribute(BASE_ATTRIBUTE, base)
	end

	local move = root.CFrame:VectorToObjectSpace(hum.MoveDirection)
	move = Vector3.new(move.X, 0, move.Z)
	local target = LeanSystem._target(base, move)
	local next = joint.C0:Lerp(target, alpha)
	if next:FuzzyEq(target, SNAP_EPSILON) then
		next = target
	end
	if next ~= joint.C0 then
		joint.C0 = next
	end
end

local function step(dt: number)
	local alpha = 1 - math.exp(-Constants.LEAN_RATE * dt)
	for _, player in Players:GetPlayers() do
		if player.Character then
			stepCharacter(player.Character, alpha)
		end
	end
	local bots = Workspace:FindFirstChild("Bots")
	if bots then
		for _, bot in bots:GetChildren() do
			if bot:IsA("Model") then
				stepCharacter(bot, alpha)
			end
		end
	end
end

function LeanSystem.init()
	RunService.Heartbeat:Connect(step)
end

return LeanSystem
