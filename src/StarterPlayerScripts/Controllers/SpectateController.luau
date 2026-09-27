local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ShopController = require(script.Parent.ShopController)

-- Lobby-only spectating: the stock camera follows one InRound combatant
-- (a Safe player or a live bot), hops to another when that one drops the tag,
-- and stops when nobody is left.
local SpectateController = {}

local localPlayer = Players.LocalPlayer
local button: TextButton
local target: Instance?
local loop: RBXScriptConnection?

local function humanoidOf(inst: Instance): Humanoid?
	local model = if inst:IsA("Player") then inst.Character else inst
	if not model or not model:IsDescendantOf(Workspace) then return nil end
	return model:FindFirstChildOfClass("Humanoid")
end

local function isValid(inst: Instance?): boolean
	return inst ~= nil and CollectionService:HasTag(inst, Constants.IN_ROUND_TAG) and humanoidOf(inst) ~= nil
end

local function nextTarget(): Instance?
	for _, inst in CollectionService:GetTagged(Constants.IN_ROUND_TAG) do
		if inst ~= target and isValid(inst) then
			return inst
		end
	end
	return nil
end

local function stop()
	if loop then
		loop:Disconnect()
		loop = nil
	end
	target = nil
	button.Text = "SPECTATE"
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
end

local function start()
	target = nextTarget()
	if not target then return end
	button.Text = "STOP"
	-- Re-asserted every frame: a kill cam ending in the meantime hands the camera back to the local humanoid.
	loop = RunService.RenderStepped:Connect(function()
		if not isValid(target) then
			target = nextTarget()
			if not target then
				stop()
				return
			end
		end
		local camera = Workspace.CurrentCamera
		local humanoid = humanoidOf(target :: Instance)
		if camera and humanoid then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
		end
	end)
end

function SpectateController.isSpectating(): boolean
	return loop ~= nil
end

function SpectateController.init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local lobbyGui = playerGui:WaitForChild("Lobby") :: ScreenGui
	button = lobbyGui:WaitForChild("Buttons"):WaitForChild("SpectateButton") :: TextButton
	local PlayerStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerStateChanged") :: RemoteEvent

	ShopController.bindLobbyButton(button, function()
		if loop then
			stop()
		else
			start()
		end
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player == localPlayer and state ~= Constants.STATE_LOBBY and loop then
			stop()
		end
	end)
end

return SpectateController
