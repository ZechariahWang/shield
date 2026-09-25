local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ShiftLockController = require(script.Parent.ShiftLockController)

local CombatController = {}

local localPlayer = Players.LocalPlayer
local ShootRequestRemote: RemoteEvent
local ShieldRequestRemote: RemoteEvent
local ShieldChangedRemote: RemoteEvent

local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY
local shieldStatus: string = Constants.SHIELD_READY
local lastShotAt = -math.huge

-- Public: the crosshair punch in CombatFeedbackController listens here.
local shotFiredEvent = Instance.new("BindableEvent")
CombatController.ShotFired = shotFiredEvent.Event

function CombatController.getShieldStatus(): string
	return shieldStatus
end

function CombatController.isCombatActive(): boolean
	if localState ~= Constants.STATE_SAFE then
		return false
	end
	return currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND
end

type Meter = { fill: GuiObject?, overlay: GuiObject?, tween: Tween? }

local playerGui: PlayerGui
local container: GuiObject?
local shieldMeter: Meter = {}
local gunMeter: Meter = {}

-- Each meter layer (BarBG, Fill, EmptyOverlay) is two halves named Left and
-- Right, each with a "Slant" UIGradient. The gradient cuts one corner off its
-- half (top-left of Left, bottom-right of Right) along a line at the authored
-- Rotation, so the halves together form a parallelogram. Roblox spans a rotated
-- gradient only across the chord through the object's center, so the cut is
-- recomputed from AbsoluteSize whenever the half resizes, and a half wider than
-- about 3.5x its height at 20 degrees puts the corner out of reach (no cut).
local function applySlant(piece: GuiObject)
	local gradient = piece:FindFirstChild("Slant")
	if not gradient or not gradient:IsA("UIGradient") then return end
	local cutsLeft = piece.Name == "Left"
	local function update()
		local w, h = piece.AbsoluteSize.X, piece.AbsoluteSize.Y
		local angle = math.rad(gradient.Rotation)
		local cos, sin = math.cos(angle), math.sin(angle)
		if w <= 0 or h <= 0 or cos <= 0 or sin <= 0 then return end
		local chord = math.min(w / cos, h / sin)
		local corner = 0.5 - (w * cos - h * sin) / (2 * chord)
		local keypoints
		if cutsLeft then
			if corner <= 0.001 then
				keypoints = { NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0) }
			elseif corner >= 0.999 then
				keypoints = { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 1) }
			else
				keypoints = {
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(corner - 0.001, 1),
					NumberSequenceKeypoint.new(corner, 0),
					NumberSequenceKeypoint.new(1, 0),
				}
			end
		else
			local cut = 1 - corner
			if cut >= 0.999 then
				keypoints = { NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0) }
			elseif cut <= 0.001 then
				keypoints = { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 1) }
			else
				keypoints = {
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(cut, 0),
					NumberSequenceKeypoint.new(cut + 0.001, 1),
					NumberSequenceKeypoint.new(1, 1),
				}
			end
		end
		gradient.Transparency = NumberSequence.new(keypoints)
	end
	piece:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

local function slantHalves(layer: Instance)
	for _, child in layer:GetChildren() do
		if child:IsA("GuiObject") and (child.Name == "Left" or child.Name == "Right") then
			applySlant(child)
		end
	end
end

local function resolveMeter(meter: Meter, name: string)
	meter.fill = nil
	meter.overlay = nil
	if not container then return end

	local meters = container:FindFirstChild("Meters")
	if not meters then return end
	local frame = meters:FindFirstChild(name)
	if not frame then return end
	local barBg = frame:FindFirstChild("BarBG")
	if not barBg then return end

	slantHalves(barBg)
	local fill = barBg:FindFirstChild("Fill")
	if fill and fill:IsA("GuiObject") then
		meter.fill = fill
		slantHalves(fill)
	end
	local overlay = barBg:FindFirstChild("EmptyOverlay")
	if overlay and overlay:IsA("GuiObject") then
		meter.overlay = overlay
		slantHalves(overlay)
	end
end

local function resolveElements()
	if container and container.Parent then return end
	container = nil

	if not playerGui then return end
	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return end

	local actions = gameGui:FindFirstChild("Actions")
	if actions and actions:IsA("GuiObject") then
		container = actions
	end
	resolveMeter(shieldMeter, "ShieldMeter")
	resolveMeter(gunMeter, "GunMeter")
end

-- Snaps the fill to fromScale, then sweeps it to toScale over duration.
-- The overlay hides by itself once a refill (toScale == 1) completes.
local function setMeter(meter: Meter, fromScale: number, toScale: number, duration: number, overlayVisible: boolean)
	resolveElements()
	if meter.tween then
		meter.tween:Cancel()
		meter.tween = nil
	end
	local fill = meter.fill
	if not fill then return end
	local overlay = meter.overlay

	if overlay then overlay.Visible = overlayVisible end
	if duration <= 0 then
		fill.Size = UDim2.fromScale(toScale, 1)
		return
	end

	fill.Size = UDim2.fromScale(fromScale, 1)
	local tween = TweenService:Create(
		fill,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(toScale, 1) }
	)
	meter.tween = tween
	tween.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed then return end
		if toScale == 1 and overlay then
			overlay.Visible = false
		end
	end)
	tween:Play()
end

local function applyShieldMeter(status: string, duration: number)
	if status == Constants.SHIELD_UP then
		setMeter(shieldMeter, 1, 0, duration, false)
	elseif status == Constants.SHIELD_COOLDOWN_STATUS then
		setMeter(shieldMeter, 0, 1, duration, true)
	else
		setMeter(shieldMeter, 1, 1, 0, false)
	end
end

local function resetGunMeter()
	setMeter(gunMeter, 1, 1, 0, false)
end

local function reconcileMeterVisibility()
	resolveElements()
	if not container then return end
	local visible = CombatController.isCombatActive()
	if container.Visible == visible then return end
	container.Visible = visible
end

local function getAimDirection(headPosition: Vector3): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then return nil end

	-- Under shift lock the aim point is the screen center regardless of what the OS cursor reports.
	local point = if ShiftLockController.isLocked() then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(point.X, point.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * Constants.PISTOL_RANGE, params)
	local aimPoint = ray.Origin + ray.Direction * Constants.PISTOL_RANGE
	if result then
		aimPoint = result.Position
	end

	local offset = aimPoint - headPosition
	if offset.Magnitude < 0.001 then return nil end
	return offset.Unit
end

local function tryShoot()
	if localState ~= Constants.STATE_SAFE then return end
	if currentPhase ~= Constants.PHASE_ROUND then return end
	if shieldStatus == Constants.SHIELD_UP then return end

	local now = os.clock()
	if now - lastShotAt < Constants.PISTOL_COOLDOWN then return end

	local character = localPlayer.Character
	if not character then return end
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return end

	local direction = getAimDirection(head.Position)
	if not direction then return end

	lastShotAt = now
	ShootRequestRemote:FireServer(head.Position, direction)
	shotFiredEvent:Fire()
	setMeter(gunMeter, 0, 1, Constants.PISTOL_COOLDOWN, true)
end

local function tryToggleShield()
	if localState ~= Constants.STATE_SAFE then return end
	if currentPhase ~= Constants.PHASE_ROUND then return end

	if shieldStatus == Constants.SHIELD_READY then
		ShieldRequestRemote:FireServer(true)
	elseif shieldStatus == Constants.SHIELD_UP then
		ShieldRequestRemote:FireServer(false)
	end
end

function CombatController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	resolveElements()
	applyShieldMeter(Constants.SHIELD_READY, 0)
	resetGunMeter()
	if container then
		container.Visible = false
	end

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	ShootRequestRemote = Remotes:WaitForChild("ShootRequest") :: RemoteEvent
	ShieldRequestRemote = Remotes:WaitForChild("ShieldRequest") :: RemoteEvent
	ShieldChangedRemote = Remotes:WaitForChild("ShieldChanged") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	ShieldChangedRemote.OnClientEvent:Connect(function(status: string, duration: number, _breaksInChain: number)
		shieldStatus = status
		applyShieldMeter(status, duration or 0)
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
		reconcileMeterVisibility()
	end)

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		resetGunMeter()
		reconcileMeterVisibility()
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryShoot()
		elseif input.KeyCode == Enum.KeyCode.E then
			tryToggleShield()
		end
	end)
end

return CombatController
