local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local KillCamController = require(script.Parent.KillCamController)
local ShopController = require(script.Parent.ShopController)
local SpectateController = require(script.Parent.SpectateController)

-- The lobby as a menu: while the local player waits in the lobby the camera is
-- parked on a Workspace.MenuScenes view (Main, or the open modal's: Shop,
-- Inventory, Settings), each an invisible part whose CFrame is the camera pose,
-- and the movement controls are off so the character stays put off screen. The
-- kill cam and spectating take priority; a spawn hands the stock camera back.
local MenuCameraController = {}

local localPlayer = Players.LocalPlayer
local localState: string = Constants.STATE_LOBBY
local currentView = "Main"
local active = false
local tween: Tween?
local controls: any = nil

local TWEEN_INFO = TweenInfo.new(Constants.MENU_CAMERA_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local function viewCFrame(name: string): CFrame?
	local scenes = Workspace:FindFirstChild("MenuScenes")
	local part = if scenes then scenes:FindFirstChild(name) else nil
	if part and part:IsA("BasePart") then
		return part.CFrame
	end
	if name ~= "Main" then
		return viewCFrame("Main")
	end
	return nil
end

local function shouldBeActive(): boolean
	if localState ~= Constants.STATE_LOBBY then return false end
	if SpectateController.isSpectating() then return false end
	return not KillCamController.isPlaying()
end

local function goTo(name: string, instant: boolean)
	currentView = name
	local camera = Workspace.CurrentCamera
	local target = viewCFrame(name)
	if not camera or not target then return end
	if tween then
		tween:Cancel()
		tween = nil
	end
	if instant then
		camera.CFrame = target
		return
	end
	tween = TweenService:Create(camera, TWEEN_INFO, { CFrame = target })
	tween:Play()
end

local function setControlsEnabled(on: boolean)
	if not controls then return end
	if on then
		controls:Enable()
	else
		controls:Disable()
	end
end

local function activate()
	active = true
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	goTo(currentView, true)
	setControlsEnabled(false)
end

local function deactivate()
	active = false
	if tween then
		tween:Cancel()
		tween = nil
	end
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	setControlsEnabled(true)
end

-- The stock camera and the kill cam both set Custom when they let go, so the type is re-asserted per frame.
local function step()
	local want = shouldBeActive()
	if want and not active then
		activate()
	elseif not want and active then
		deactivate()
	end
	if active then
		local camera = Workspace.CurrentCamera
		if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
	end
end

function MenuCameraController.init()
	local PlayerStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerStateChanged") :: RemoteEvent
	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player == localPlayer then
			localState = state
		end
	end)

	ShopController.ModalChanged.Event:Connect(function(modalName: string?)
		local view = if modalName then string.gsub(modalName, "Modal$", "") else "Main"
		if active then
			goTo(view, false)
		else
			currentView = view
		end
	end)

	task.spawn(function()
		local ok, module = pcall(function()
			return require(localPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		end)
		if ok and module and module.GetControls then
			controls = module:GetControls()
			if active then
				setControlsEnabled(false)
			end
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return MenuCameraController
