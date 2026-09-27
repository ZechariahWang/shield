-- Command-bar check: require(game.ServerScriptService.Systems.RagdollTest)()
-- Builds a ragdoll from the bot rig; nothing it creates is left behind.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RagdollSystem = require(script.Parent.RagdollSystem)

local function bodyMotorCount(model: Model): number
	local count = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 and d.Part0.Parent == model and d.Part1.Parent == model then
			count += 1
		end
	end
	return count
end

local function countClass(model: Model, className: string): number
	local count = 0
	for _, d in model:GetDescendants() do
		if d:IsA(className) then count += 1 end
	end
	return count
end

return function()
	local rigTemplate = ReplicatedStorage:FindFirstChild("Assets")
	rigTemplate = rigTemplate and rigTemplate:FindFirstChild("Rigs")
	rigTemplate = rigTemplate and rigTemplate:FindFirstChild("NPC")
	assert(rigTemplate and rigTemplate:IsA("Model"), "needs ReplicatedStorage.Assets.Rigs.NPC")

	local rig = rigTemplate:Clone()
	local motorsBefore = bodyMotorCount(rig)
	assert(motorsBefore >= 5, "rig has body joints, got " .. motorsBefore)
	local sticker = Instance.new("Script")
	sticker.Parent = rig
	local weapon = Instance.new("Model")
	weapon.Name = "EquippedWeapon"
	local handle = Instance.new("Part")
	handle.Parent = weapon
	weapon.Parent = rig
	local weaponMotor = Instance.new("Motor6D")
	weaponMotor.Name = "Weapon"
	weaponMotor.Part0 = rig:FindFirstChild("Right Arm") :: BasePart
	weaponMotor.Part1 = handle
	weaponMotor.Parent = rig:FindFirstChild("Right Arm")

	local converted = RagdollSystem._build(rig)
	assert(converted == motorsBefore, "converted every body joint")
	assert(bodyMotorCount(rig) == 0, "no body Motor6D remains")
	assert(countClass(rig, "BallSocketConstraint") == motorsBefore, "one ball socket per joint")
	assert(weaponMotor.Parent ~= nil, "weapon motor is kept rigid")
	local corpseHum = rig:FindFirstChildOfClass("Humanoid")
	assert(corpseHum and corpseHum.Health <= 0, "humanoid kept but dead")
	assert(corpseHum.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.None, "no name tag")
	assert(countClass(rig, "Animator") == 0, "animator removed")
	assert(countClass(rig, "LuaSourceContainer") == 0, "scripts removed")
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			assert(not d.CanQuery and not d.CanTouch, d.Name .. " ignores rays and touches")
			assert(not d.Anchored, d.Name .. " unanchored")
		end
	end
	assert((rig:FindFirstChild("Torso") :: BasePart).CanCollide, "torso collides with the floor")
	assert(not (rig:FindFirstChild("HumanoidRootPart") :: BasePart).CanCollide, "invisible root does not collide")
	rig:Destroy()

	-- spawn() leaves the victim alone and parents the corpse under Workspace.Ragdolls.
	local victim = rigTemplate:Clone()
	victim.Parent = Workspace
	local corpse = RagdollSystem.spawn(victim, nil)
	assert(corpse and corpse.Parent == Workspace:FindFirstChild("Ragdolls"), "corpse under Workspace.Ragdolls")
	assert((corpse:FindFirstChild("Torso") :: BasePart):GetNetworkOwner() == nil, "server owns the corpse physics")
	assert(victim:FindFirstChildOfClass("Humanoid"), "victim keeps its humanoid")
	assert(bodyMotorCount(victim) == motorsBefore, "victim keeps its joints")
	RagdollSystem.clear()
	assert(corpse.Parent == nil, "clear() removes corpses")
	victim:Destroy()

	print("RagdollTest: all passed")
end
