local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- Leaves a ragdolled corpse where a combatant was eliminated. The real character
-- is untouched (it still teleports to the lobby); the corpse is a stripped clone
-- under Workspace.Ragdolls that shots and touches ignore, cleared at round end.
local RagdollSystem = {}

local FOLDER_NAME = "Ragdolls"

local function folder(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	return created
end

local function isBodyJoint(model: Model, joint: Motor6D): boolean
	local part0 = joint.Part0
	local part1 = joint.Part1
	if not part0 or not part1 then return false end
	return part0.Parent == model and part1.Parent == model
end

-- Turns a character-shaped model into a ragdoll in place. Returns the number of
-- body joints converted. Exposed for RagdollTest.
function RagdollSystem._build(model: Model): number
	for _, child in model:GetDescendants() do
		if child:IsA("Humanoid") or child:IsA("LuaSourceContainer") or child:IsA("ForceField") or child.Name == "PlayerShield" then
			child:Destroy()
		end
	end

	local limit = Constants.RAGDOLL_JOINT_LIMIT
	local converted = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CustomPhysicalProperties = PhysicalProperties.new(Constants.RAGDOLL_DENSITY, 0.5, 0.2)
			if descendant.Parent == model then
				descendant.CanCollide = descendant.Name ~= "HumanoidRootPart"
			end
		elseif descendant:IsA("Motor6D") and isBodyJoint(model, descendant) then
			local part0 = descendant.Part0 :: BasePart
			local part1 = descendant.Part1 :: BasePart
			local attachment0 = Instance.new("Attachment")
			attachment0.CFrame = descendant.C0
			attachment0.Parent = part0
			local attachment1 = Instance.new("Attachment")
			attachment1.CFrame = descendant.C1
			attachment1.Parent = part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = descendant.Name
			socket.Attachment0 = attachment0
			socket.Attachment1 = attachment1
			socket.LimitsEnabled = true
			socket.UpperAngle = limit
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -limit
			socket.TwistUpperAngle = limit
			socket.Parent = part1
			descendant:Destroy()
			converted += 1
		end
	end
	return converted
end

function RagdollSystem.spawn(victim: Model, killer: Model?): Model?
	local root = victim:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return nil end

	local wasArchivable = victim.Archivable
	victim.Archivable = true
	local corpse = victim:Clone()
	victim.Archivable = wasArchivable
	corpse.Name = victim.Name .. "Ragdoll"
	RagdollSystem._build(corpse)

	-- Keep the pose the victim died in: cloned joints reset to their rest offsets.
	for _, part in victim:GetChildren() do
		if part:IsA("BasePart") then
			local twin = corpse:FindFirstChild(part.Name)
			if twin and twin:IsA("BasePart") then
				twin.CFrame = part.CFrame
			end
		end
	end
	corpse.Parent = folder()

	local velocity = root.AssemblyLinearVelocity
	local killerRoot = killer and killer:FindFirstChild("HumanoidRootPart")
	if killerRoot and killerRoot:IsA("BasePart") then
		local away = root.Position - killerRoot.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 0.01 then
			velocity += away.Unit * Constants.RAGDOLL_IMPULSE
		end
	end
	for _, part in corpse:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = velocity
		end
	end

	return corpse
end

function RagdollSystem.clear()
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:ClearAllChildren()
	end
end

function RagdollSystem.init()
	folder()
end

return RagdollSystem
