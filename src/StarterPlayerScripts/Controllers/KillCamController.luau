local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)

local KillCamController = {}

local localPlayer = Players.LocalPlayer
local camGen = 0

local function headOf(character: Model): BasePart?
	if not character.Parent then return nil end
	return character:FindFirstChild("Head") :: BasePart?
end

-- Camera sits KILL_CAM_DISTANCE studs from the killer on the side the victim
-- died on, raised by KILL_CAM_HEIGHT, looking at the killer's head.
local function frameKiller(head: BasePart, fromPosition: Vector3): CFrame
	local toVictim = fromPosition - head.Position
	toVictim = Vector3.new(toVictim.X, 0, toVictim.Z)
	if toVictim.Magnitude < 0.001 then
		toVictim = head.CFrame.LookVector
	end
	local eye = head.Position + toVictim.Unit * Constants.KILL_CAM_DISTANCE + Vector3.new(0, Constants.KILL_CAM_HEIGHT, 0)
	return CFrame.lookAt(eye, head.Position)
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	camera.CameraType = Enum.CameraType.Custom
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

function KillCamController.play(killerCharacter: Model)
	local camera = Workspace.CurrentCamera
	local head = headOf(killerCharacter)
	if not camera or not head then return end

	camGen += 1
	local gen = camGen
	local deathPosition = camera.CFrame.Position
	local startCFrame = camera.CFrame
	local startedAt = os.clock()

	camera.CameraType = Enum.CameraType.Scriptable

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt
		local currentHead = headOf(killerCharacter)
		if gen ~= camGen or not currentHead or elapsed >= Constants.KILL_CAM_TIME then
			connection:Disconnect()
			if gen == camGen then
				restoreCamera()
			end
			return
		end

		local target = frameKiller(currentHead, deathPosition)
		local alpha = math.clamp(elapsed / Constants.KILL_CAM_TWEEN_TIME, 0, 1)
		alpha = 1 - (1 - alpha) * (1 - alpha)
		camera.CFrame = startCFrame:Lerp(target, alpha)
	end)
end

function KillCamController.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local KillFeedRemote = Remotes:WaitForChild("KillFeed") :: RemoteEvent

	KillFeedRemote.OnClientEvent:Connect(function(killerName: string?, victimName: string)
		if victimName ~= localPlayer.Name then return end
		if not killerName or killerName == localPlayer.Name then return end
		local killer = Players:FindFirstChild(killerName)
		if not killer or not killer:IsA("Player") or not killer.Character then return end
		KillCamController.play(killer.Character)
	end)
end

return KillCamController
