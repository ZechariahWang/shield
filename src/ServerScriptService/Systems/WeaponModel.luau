local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)

-- The third-person weapon model welded to a character's right arm. Server side
-- so it replicates to every observer; used for players (RoundManager, with the
-- equipped weapon) and bots (BotSystem, with the default one).
local WeaponModel = {}

local MODEL_NAME = "EquippedWeapon"

-- Read the grip CFrame and motor name from the third-person rig's Right-Arm motor.
-- This lets the user author the grip in Studio (via the rig's pre-rigged weapon)
-- and have it pick up automatically. Without a rig, falls back to the item
-- module's `grip` (identity if absent) + "Weapon".
local function extractGrip(weaponName: string): (CFrame, string)
	local data = Catalog.get(Catalog.KIND_WEAPONS, weaponName)
	local fallbackGrip = (data and data.grip) or CFrame.new()
	local rigsFolder = ReplicatedStorage:FindFirstChild("ThirdPersonRigs")
	if not rigsFolder then return fallbackGrip, "Weapon" end
	local rig = rigsFolder:FindFirstChild(weaponName)
	if not rig or not rig:IsA("Model") then return fallbackGrip, "Weapon" end
	local rightArm = rig:FindFirstChild("Right Arm")
	if not rightArm then return fallbackGrip, "Weapon" end
	for _, m in ipairs(rig:GetDescendants()) do
		if m:IsA("Motor6D") and m.Part0 == rightArm and m.Part1 then
			return m.C0, m.Name
		end
	end
	return fallbackGrip, "Weapon"
end

function WeaponModel.detach(char: Model)
	local existing = char:FindFirstChild(MODEL_NAME)
	if existing then existing:Destroy() end
	local rightArm = char:FindFirstChild("Right Arm")
	if not rightArm then return end
	for _, c in ipairs(rightArm:GetChildren()) do
		if c:IsA("Motor6D") and c.Part1 == nil then
			c:Destroy()
		end
	end
end

function WeaponModel.attach(char: Model, weaponName: string)
	WeaponModel.detach(char)
	local rightArm = char:FindFirstChild("Right Arm")
	if not rightArm then return end

	local template = Catalog.model(Catalog.KIND_WEAPONS, weaponName)
	if not template then return end

	local clone = template:Clone()
	clone.Name = MODEL_NAME
	local primary: BasePart? = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	if not primary then
		clone:Destroy()
		return
	end
	clone.PrimaryPart = primary

	-- Weld every part to the primary with its authored offset so models built from
	-- loose parts hold together. An explicit C0 avoids WeldConstraint capturing the
	-- offset after the Motor6D has already snapped the primary to the arm.
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			if d ~= primary then
				local weld = Instance.new("Weld")
				weld.Part0 = primary
				weld.Part1 = d
				weld.C0 = primary.CFrame:ToObjectSpace(d.CFrame)
				weld.Parent = d
			end
		end
	end

	local grip, motorName = extractGrip(weaponName)

	local motor = Instance.new("Motor6D")
	motor.Name = motorName
	motor.Part0 = rightArm
	motor.Part1 = primary
	motor.C0 = grip
	motor.Parent = rightArm

	clone.Parent = char
end

return WeaponModel
