local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local CombatController = require(script.Parent.CombatController)
local ShiftLockController = require(script.Parent.ShiftLockController)
local CombatFeedbackController = {}
local localPlayer = Players.LocalPlayer

-- need to update these later, i dont have the sounds rn
local SOUND_IDS = {
	hitConfirm = "",     -- short tick when the local player lands a shot on a victim
	sizzleLoop = "",     -- looping crackle while local player is taking damage
	grunt75 = "",        -- HP crossed below 75%
	grunt50 = "",        -- HP crossed below 50%
	grunt25 = "",        -- HP crossed below 25%
	killWhoosh = "",     -- victim was just eliminated by the local player
	convertImpact = "",  -- local player was just eliminated
	shotBlocked = "",    -- a shield absorbed a shot the local player fired or took
}

local screenGui: ScreenGui
local vignette: Frame
local crosshair: Frame
local damageNumberTemplate: BillboardGui

local sizzleSound: Sound

local lastDamageTakenAt = -math.huge
local sizzlePlaying = false
local SIZZLE_GRACE = 0.18 

local lastKnownHP = math.huge
local HP_THRESHOLDS = { { hp = 75, key = "grunt75" }, { hp = 50, key = "grunt50" }, { hp = 25, key = "grunt25" } }

local shakeIntensity = 0
local SHAKE_DECAY = 5.0

local function initHUD()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	screenGui = playerGui:WaitForChild("Game") :: ScreenGui
	vignette = screenGui:WaitForChild("Vignette") :: Frame
	crosshair = screenGui:WaitForChild("Crosshair") :: Frame
	damageNumberTemplate = ReplicatedStorage:FindFirstChild("Assets"):FindFirstChild("UI"):WaitForChild("DamageNumber") :: BillboardGui

	sizzleSound = Instance.new("Sound")
	sizzleSound.Name = "SizzleLoop"
	sizzleSound.SoundId = SOUND_IDS.sizzleLoop
	sizzleSound.Looped = true
	sizzleSound.Parent = SoundService
end

local function playSound(id: string, volume: number?)
	if id == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Cleanup if Ended never fires (e.g., bad ID)
	task.delay(5, function()
		if sound and sound.Parent then sound:Destroy() end
	end)
end

local function pulseVignette(intensity: number)
	-- intensity 0..1. Higher = darker, faster.
	local target = math.clamp(0.85 - intensity * 0.55, 0.3, 0.85)
	TweenService:Create(
		vignette,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = target }
	):Play()
	task.delay(0.1, function()
		TweenService:Create(
			vignette,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end)
end

-- Four arms around an empty center; the Studio Frame is only the anchor that
-- follows the mouse. A punch scales the whole crosshair (arms spread) and flashes
-- the arm color.
local CROSSHAIR_IDLE_SIZE = UDim2.fromOffset(24, 24)
local CROSSHAIR_PUNCH_SIZE = UDim2.fromOffset(36, 36)
local CROSSHAIR_ARM_LENGTH = 0.34   -- fraction of the crosshair size per arm; the rest is the center gap
local CROSSHAIR_ARM_THICKNESS = 2   -- px
local CROSSHAIR_IDLE_COLOR = Color3.fromRGB(255, 159, 80)
local CROSSHAIR_PUNCH_COLOR = Color3.fromRGB(255, 80, 30)
local CROSSHAIR_IDLE_TRANSPARENCY = 0
local CROSSHAIR_PUNCH_TRANSPARENCY = 0
local CROSSHAIR_OUTLINE_COLOR = Color3.fromRGB(20, 12, 8)
local CROSSHAIR_TWEEN_TIME = 0.12

local crosshairArms: { Frame } = {}

local function buildCrosshair()
	crosshair.BackgroundTransparency = 1
	for _, child in crosshair:GetChildren() do
		if child:IsA("UIStroke") then
			child.Enabled = false
		end
	end

	local horizontal = UDim2.new(CROSSHAIR_ARM_LENGTH, 0, 0, CROSSHAIR_ARM_THICKNESS)
	local vertical = UDim2.new(0, CROSSHAIR_ARM_THICKNESS, CROSSHAIR_ARM_LENGTH, 0)
	local arms = {
		{ anchor = Vector2.new(0, 0.5), position = UDim2.fromScale(0, 0.5), size = horizontal },
		{ anchor = Vector2.new(1, 0.5), position = UDim2.fromScale(1, 0.5), size = horizontal },
		{ anchor = Vector2.new(0.5, 0), position = UDim2.fromScale(0.5, 0), size = vertical },
		{ anchor = Vector2.new(0.5, 1), position = UDim2.fromScale(0.5, 1), size = vertical },
	}
	for _, spec in arms do
		local arm = Instance.new("Frame")
		arm.Name = "Arm"
		arm.AnchorPoint = spec.anchor
		arm.Position = spec.position
		arm.Size = spec.size
		arm.BorderSizePixel = 0
		arm.BackgroundColor3 = CROSSHAIR_IDLE_COLOR
		arm.ZIndex = crosshair.ZIndex
		local outline = Instance.new("UIStroke")
		outline.Thickness = 1
		outline.Color = CROSSHAIR_OUTLINE_COLOR
		outline.Parent = arm
		arm.Parent = crosshair
		table.insert(crosshairArms, arm)
	end
end

local localState: string = Constants.STATE_LOBBY
local combatModeActive = false
local currentPhase: string = Constants.PHASE_LOBBY

local function shouldCombatModeBeActive(): boolean
	if localState ~= Constants.STATE_SAFE then return false end
	return currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND
end

local function resetCrosshair()
	if not crosshair then return end
	crosshair.Size = CROSSHAIR_IDLE_SIZE
	for _, arm in crosshairArms do
		arm.BackgroundColor3 = CROSSHAIR_IDLE_COLOR
		arm.BackgroundTransparency = CROSSHAIR_IDLE_TRANSPARENCY
	end
end

local function punchCrosshair()
	if not crosshair or not crosshair.Visible then return end
	-- Reverses = true plays the punch out and back without a second tween.
	local info = TweenInfo.new(CROSSHAIR_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(crosshair, info, { Size = CROSSHAIR_PUNCH_SIZE }):Play()
	for _, arm in crosshairArms do
		TweenService:Create(arm, info, {
			BackgroundColor3 = CROSSHAIR_PUNCH_COLOR,
			BackgroundTransparency = CROSSHAIR_PUNCH_TRANSPARENCY,
		}):Play()
	end
end

local function getLocalHumanoid(): Humanoid?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function crosshairFollowStep()
	if not crosshair then return end
	-- Under shift lock the crosshair sits at the screen center regardless of what the OS cursor reports.
	local camera = Workspace.CurrentCamera
	local mouse = if ShiftLockController.isLocked() and camera then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local inset = if screenGui.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset()
	crosshair.Position = UDim2.fromOffset(mouse.X - inset.X, mouse.Y - inset.Y)
end

local function setCombatMode(active: boolean)
	resetCrosshair()
	if crosshair then
		crosshair.Visible = active
	end
	-- The crosshair replaces the system cursor while combat is active.
	UserInputService.MouseIconEnabled = not active
end


local DAMAGE_FLUSH_INTERVAL = 0.25
local pendingDamage: { [Player]: { total: number, nextFlushAt: number } } = {}
local HIT_CONFIRM_THROTTLE = 0.08
local lastHitConfirmAt = -math.huge

local function colorForDamage(dmg: number): (Color3, Color3)
	if dmg >= 12 then
		return Color3.fromRGB(255, 70, 30), Color3.fromRGB(60, 0, 0)
	elseif dmg >= 5 then
		return Color3.fromRGB(255, 150, 30), Color3.fromRGB(40, 5, 0)
	else
		return Color3.fromRGB(255, 220, 90), Color3.fromRGB(40, 20, 0)
	end
end

local function spawnDamageNumber(victim: Player | Model, dmg: number)
	local char: Model? = if victim:IsA("Player") then victim.Character else victim
	if not char then return end
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then return end

	local gui = damageNumberTemplate:Clone()
	local hOffset = (math.random() - 0.5) * 1.6
	gui.StudsOffset = Vector3.new(hOffset, 1.2, 0)
	gui.Parent = head

	local label = gui:FindFirstChild("Label") :: TextLabel?
	if not label then
		gui:Destroy()
		return
	end

	label.Text = string.format("%d", math.ceil(dmg))
	label.TextTransparency = 0

	local fillColor, strokeColor = colorForDamage(dmg)
	label.TextColor3 = fillColor

	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = strokeColor
		stroke.Transparency = 0
	end

	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end
	scale.Scale = 1.5
	TweenService:Create(
		scale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.0 }
	):Play()

	local riseTarget = gui.StudsOffset + Vector3.new(hOffset * 0.6, 2.4, 0)
	TweenService:Create(
		gui,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = riseTarget }
	):Play()

	task.delay(0.3, function()
		if not gui.Parent then return end
		TweenService:Create(
			label,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }
		):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		TweenService:Create(scale, TweenInfo.new(0.4), { Scale = 0.85 }):Play()
	end)

	task.delay(0.75, function()
		if gui and gui.Parent then gui:Destroy() end
	end)
end

local function damageNumberStep(_dt: number)
	-- Flush each victim's accumulated damage at a fixed interval 
	local now = os.clock()
	for victim, entry in pendingDamage do
		if now < entry.nextFlushAt then continue end
		if entry.total > 0 then
			if victim.Parent then
				spawnDamageNumber(victim, entry.total)
			end
			entry.total = 0
			entry.nextFlushAt = now + DAMAGE_FLUSH_INTERVAL
		else
			pendingDamage[victim] = nil
		end
	end
end

local function startSizzle()
	if not sizzleSound then return end
	if sizzlePlaying or sizzleSound.SoundId == "" then return end
	sizzlePlaying = true
	sizzleSound.Volume = 0
	sizzleSound:Play()
	TweenService:Create(sizzleSound, TweenInfo.new(0.08), { Volume = 0.7 }):Play()
end

local function stopSizzle()
	if not sizzleSound then return end
	if not sizzlePlaying then return end
	sizzlePlaying = false
	local tween = TweenService:Create(sizzleSound, TweenInfo.new(0.18), { Volume = 0 })
	tween:Play()
	tween.Completed:Once(function()
		if not sizzlePlaying then sizzleSound:Stop() end
	end)
end

local function checkHpThresholds(currentHP: number)
	for _, t in HP_THRESHOLDS do
		if lastKnownHP > t.hp and currentHP <= t.hp then
			playSound(SOUND_IDS[t.key], 0.9)
		end
	end
	lastKnownHP = currentHP
end

local function shake(intensity: number)
	shakeIntensity = math.max(shakeIntensity, intensity)
end

local function shakeStep(dt: number)
	local hum = getLocalHumanoid()
	if not hum then return end

	-- Shake is additive on top of the shift-lock shoulder offset, and settles back to it.
	local base = ShiftLockController.baseCameraOffset()
	if shakeIntensity <= 0.001 then
		if (hum.CameraOffset - base).Magnitude > 0.001 then
			hum.CameraOffset = base
		end
		return
	end

	local i = shakeIntensity
	hum.CameraOffset = base + Vector3.new(
		(math.random() - 0.5) * 2 * i,
		(math.random() - 0.5) * 2 * i,
		(math.random() - 0.5) * 2 * i
	)

	shakeIntensity = math.max(0, shakeIntensity - SHAKE_DECAY * dt)
end

local function sizzleStep(_dt: number)
	if (os.clock() - lastDamageTakenAt) < SIZZLE_GRACE then
		startSizzle()
	else
		stopSizzle()
	end
end

local function onDamageDealt(victim: Player | Model, dmg: number, _victimHP: number)
	-- Only the shooter who landed the hit receives this.
	if not victim or not victim.Parent then return end

	local now = os.clock()
	if now - lastHitConfirmAt >= HIT_CONFIRM_THROTTLE then
		playSound(SOUND_IDS.hitConfirm, 0.6)
		lastHitConfirmAt = now
	end

	local entry = pendingDamage[victim]
	if entry then
		entry.total += dmg
	else
		pendingDamage[victim] = { total = dmg, nextFlushAt = now + DAMAGE_FLUSH_INTERVAL }
	end
end

local function onDamageTaken(_attacker: Player?, dmg: number, currentHP: number)
	-- Only the victim receives this.
	lastDamageTakenAt = os.clock()
	pulseVignette(math.clamp(dmg * 0.06, 0.3, 1))
	shake(0.18)
	checkHpThresholds(currentHP)
end

local function onKillFeed(killerName: string?, victimName: string)
	if killerName == localPlayer.Name then
		playSound(SOUND_IDS.killWhoosh, 1)
		shake(0.35)
	elseif victimName == localPlayer.Name then
		pulseVignette(1)
		shake(0.5)
		playSound(SOUND_IDS.convertImpact, 1)
		lastKnownHP = math.huge
	end
end

local function onShotBlocked(_other: Player?)
	playSound(SOUND_IDS.shotBlocked, 0.8)
end

local function onCharacterAdded(char: Model)
	lastKnownHP = math.huge
	shakeIntensity = 0
end

local function reconcileCombatMode()
	local desired = shouldCombatModeBeActive()
	if desired == combatModeActive then return end
	combatModeActive = desired
	setCombatMode(desired)
end

function CombatFeedbackController.init()

	initHUD()
	if crosshair then
		buildCrosshair()
	end
	setCombatMode(false)

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local DamageDealtRemote = Remotes:WaitForChild("DamageDealt") :: RemoteEvent
	local DamageTakenRemote = Remotes:WaitForChild("DamageTaken") :: RemoteEvent
	local KillFeedRemote = Remotes:WaitForChild("KillFeed") :: RemoteEvent
	local ShotBlockedRemote = Remotes:WaitForChild("ShotBlocked") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	DamageDealtRemote.OnClientEvent:Connect(onDamageDealt)
	DamageTakenRemote.OnClientEvent:Connect(onDamageTaken)
	KillFeedRemote.OnClientEvent:Connect(onKillFeed)
	ShotBlockedRemote.OnClientEvent:Connect(onShotBlocked)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
		reconcileCombatMode()
	end)

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		reconcileCombatMode()
	end)

	CombatController.ShotFired:Connect(punchCrosshair)

	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end

	RunService.RenderStepped:Connect(function(dt)
		if combatModeActive then
			crosshairFollowStep()
		end
		shakeStep(dt)
		sizzleStep(dt)
		damageNumberStep(dt)
	end)
end

return CombatFeedbackController
