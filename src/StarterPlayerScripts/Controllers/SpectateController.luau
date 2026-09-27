local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ShopController = require(script.Parent.ShopController)

-- Lobby-only spectating: the stock camera follows one InRound combatant
-- (a Safe player or a live bot). The combatants form a ring sorted by name;
-- the arrows walk it, an eliminated target hands over to the next one, and
-- an empty ring ends spectating.
local SpectateController = {}

local localPlayer = Players.LocalPlayer
local lobbyButtons: GuiObject
local bar: Frame
local localState = Constants.STATE_LOBBY
local targetLabel: TextLabel
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

local function ring(): { Instance }
	local list = {}
	for _, inst in CollectionService:GetTagged(Constants.IN_ROUND_TAG) do
		if isValid(inst) then
			table.insert(list, inst)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

-- The combatant `step` places after (or before) the current target in the
-- ring. A target that has dropped out is placed by name, so the walk carries
-- on from where it stood.
local function neighbor(step: number): Instance?
	local list = ring()
	if #list == 0 then return nil end
	local index = if target then table.find(list, target) else nil
	if index then
		return list[(index - 1 + step) % #list + 1]
	end
	local currentName = if target then target.Name else ""
	local after = #list + 1
	for i, inst in list do
		if inst.Name > currentName then
			after = i
			break
		end
	end
	if step > 0 then
		return list[(after - 1) % #list + 1]
	end
	return list[(after - 2) % #list + 1]
end

local function stop()
	if loop then
		loop:Disconnect()
		loop = nil
	end
	target = nil
	bar.Visible = false
	lobbyButtons.Visible = localState == Constants.STATE_LOBBY
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
end

local function start()
	target = neighbor(1)
	if not target then return end
	ShopController.closeAll()
	lobbyButtons.Visible = false
	bar.Visible = true
	-- Re-asserted every frame: a kill cam ending in the meantime hands the camera back to the local humanoid.
	loop = RunService.RenderStepped:Connect(function()
		if not isValid(target) then
			target = neighbor(1)
			if not target then
				stop()
				return
			end
		end
		local camera = Workspace.CurrentCamera
		local humanoid = humanoidOf(target :: Instance)
		targetLabel.Text = (target :: Instance).Name
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
	lobbyButtons = lobbyGui:WaitForChild("Buttons") :: GuiObject
	local button = lobbyButtons:WaitForChild("SpectateButton") :: TextButton
	bar = lobbyGui:WaitForChild("Spectate") :: Frame
	local row = bar:WaitForChild("Row")
	targetLabel = row:WaitForChild("Target") :: TextLabel
	bar.Visible = false
	local PlayerStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerStateChanged") :: RemoteEvent

	ShopController.bindLobbyButton(button, function()
		if not loop then
			start()
		end
	end)
	ShopController.bindLobbyButton(bar:WaitForChild("Exit") :: TextButton, function()
		if loop then
			stop()
		end
	end)
	ShopController.bindLobbyButton(row:WaitForChild("Prev") :: TextButton, function()
		target = neighbor(-1) or target
	end)
	ShopController.bindLobbyButton(row:WaitForChild("Next") :: TextButton, function()
		target = neighbor(1) or target
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
		if state ~= Constants.STATE_LOBBY and loop then
			stop()
		end
	end)
end

return SpectateController
