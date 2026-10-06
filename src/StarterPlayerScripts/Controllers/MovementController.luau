local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MovementBlend = require(ReplicatedStorage.Shared.MovementBlend)
local CombatController = require(script.Parent.CombatController)
local GrappleController = require(script.Parent.GrappleController)
local SettingsController = require(script.Parent.SettingsController)
local ShiftLockController = require(script.Parent.ShiftLockController)

-- Client-side movement extras while combat is active: hold Shift to sprint,
-- hold the Aim key to aim (FOV zoom only), and press the Slide key while moving
-- on the ground to slide. This
-- controller is the only writer of the camera FOV. The local character is
-- client-simulated, so WalkSpeed is set here and re-applied every frame because
-- the server rewrites it on shield changes, and the slide drives the root's
-- horizontal velocity through a LinearVelocity constraint (the humanoid re-drives
-- the velocity every physics step, so a plain write would not hold).
local MovementController = {}

local localPlayer = Players.LocalPlayer
local shiftHeld = false
local aimHeld = false
local sprinting = false
local aiming = false
local currentFovTarget = Constants.CAMERA_FOV
local fovTween: Tween? = nil

local slideTrack: AnimationTrack? = nil
local slideDirection: Vector3? = nil
local slideVelocity: LinearVelocity? = nil
local slideStartedAt = 0
local lastSlideEndedAt = -math.huge
local cameraDrop = 0

-- Movement animations: five looping tracks (idle plus four walk directions) at
-- Movement priority share weights that sum to 1 while grounded, replacing the stock
-- Animate walk; airborne they all drop out so the stock jump and fall show.
local WEIGHT_EPSILON = 0.001 -- a track at exactly 0 weight can be dropped from the blend
local moveTracks: { [string]: AnimationTrack } = {}
local dashTracks: { [string]: AnimationTrack } = {}
local jumpTrack: AnimationTrack? = nil

local function getHumanoid(): Humanoid?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function makeAnimation(id: string): Animation
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	return animation
end

local function loadTrack(animator: Animator, animation: Animation, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped
	return track
end

-- The clips are preloaded before any track is created: a track takes the asset's
-- authored priority and loop flag when its data arrives, which on a live client
-- is after LoadAnimation returns and would overwrite what is set here.
local function bindAnimations(hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5)
	if not animator or not animator:IsA("Animator") then return end

	local moveAnimations: { [string]: Animation } = {}
	local dashAnimations: { [string]: Animation } = {}
	local toPreload: { Instance } = {}
	for name, id in Constants.MOVEMENT_ANIMATIONS do
		moveAnimations[name] = makeAnimation(id)
		table.insert(toPreload, moveAnimations[name])
	end
	for name, id in Constants.DASH_ANIMATIONS do
		dashAnimations[name] = makeAnimation(id)
		table.insert(toPreload, dashAnimations[name])
	end
	local jumpAnimation = makeAnimation(Constants.JUMP_ANIMATION)
	table.insert(toPreload, jumpAnimation)
	local slideAnimation = makeAnimation(Constants.SLIDE_ANIMATION)
	table.insert(toPreload, slideAnimation)
	ContentProvider:PreloadAsync(toPreload)
	if hum.Parent ~= localPlayer.Character then return end

	moveTracks = {}
	for name, animation in moveAnimations do
		local track = loadTrack(animator, animation, Enum.AnimationPriority.Movement, true)
		track:Play(0, WEIGHT_EPSILON)
		moveTracks[name] = track
	end
	dashTracks = {}
	for name, animation in dashAnimations do
		dashTracks[name] = loadTrack(animator, animation, Enum.AnimationPriority.Action, false)
	end
	jumpTrack = loadTrack(animator, jumpAnimation, Enum.AnimationPriority.Action, false)
	slideTrack = loadTrack(animator, slideAnimation, Enum.AnimationPriority.Action, false)
end

-- Root-space move direction: -Z forward, +X right.
local function localMove(hum: Humanoid): Vector3?
	local root = hum.RootPart
	if not root then return nil end
	return root.CFrame:VectorToObjectSpace(hum.MoveDirection)
end

local function stepAnimations()
	local hum = getHumanoid()
	if not hum or not moveTracks.Idle then return end
	local move = localMove(hum)
	local grounded = move ~= nil and hum.FloorMaterial ~= Enum.Material.Air and not GrappleController.isGrappling()
	-- The fade restarts every frame, which stretches it; the ground fade would
	-- leave the legs running for a moment after takeoff.
	local fade = if grounded then Constants.MOVEMENT_ANIM_FADE else Constants.MOVEMENT_AIR_FADE
	local weights = MovementBlend.weights(move or Vector3.zero, hum.MoveDirection.Magnitude, grounded, sprinting)

	local root = hum.RootPart
	local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	-- The walk and run clips differ in length. Each plays at the speed that gives it
	-- the leading track's cycle time, and one that is faded out is put on the
	-- leader's stride phase, so a blend never has the feet out of step.
	local leaderName = MovementBlend.leader(weights)
	local leader = if leaderName then moveTracks[leaderName] else nil
	local leaderSpeed = 1
	local leaderPhase: number? = nil
	if leaderName and leader then
		leaderSpeed = MovementBlend.playback(leaderName, horizontalSpeed)
		if leader.Length > 0 then
			leaderPhase = leader.TimePosition / leader.Length
		end
	end
	for name, track in moveTracks do
		-- Applying the character's appearance after a respawn stops every track on
		-- the Animator; the stock Animate script re-plays on state events, we re-play here.
		if not track.IsPlaying then
			track:Play(0, WEIGHT_EPSILON)
		end
		track:AdjustWeight(math.max(weights[name] or 0, WEIGHT_EPSILON), fade)
		if name == "Idle" or not leader or track == leader then
			track:AdjustSpeed(MovementBlend.playback(name, horizontalSpeed))
		else
			track:AdjustSpeed(MovementBlend.followSpeed(leaderSpeed, leader.Length, track.Length))
			if leaderPhase and track.WeightCurrent < Constants.MOVEMENT_SYNC_WEIGHT then
				track.TimePosition = leaderPhase * track.Length
			end
		end
	end
end

-- Plays the dash animation matching the dash's world direction.
function MovementController.playDashAnimation(direction: Vector3)
	local hum = getHumanoid()
	local root = hum and hum.RootPart
	if not root then return end
	local move = root.CFrame:VectorToObjectSpace(direction)
	local track = dashTracks[MovementBlend.dashTrack(move)]
	if track then
		local speed = MovementBlend.fitSpeed(track.Length, Constants.DASH_ANIM_TIME)
		track:Play(Constants.ACTION_ANIM_FADE, 1, speed)
	end
end

-- Slide: the move direction at the key press carries the character for
-- SLIDE_DURATION, easing from SLIDE_SPEED to walk speed, keys released or not.

local function endSlide()
	if not slideDirection then return end
	slideDirection = nil
	lastSlideEndedAt = os.clock()
	if slideVelocity then
		slideVelocity:Destroy()
		slideVelocity = nil
	end
	if slideTrack and slideTrack.IsPlaying then
		slideTrack:Stop(Constants.MOVEMENT_ANIM_FADE)
	end
end

-- Eases from SLIDE_SPEED to `endSpeed`, the pace the character walks or runs on at.
local function slideSpeed(t: number, endSpeed: number): number
	return Constants.SLIDE_SPEED + (endSpeed - Constants.SLIDE_SPEED) * t * t
end

-- Constrains only the horizontal plane so gravity and slopes still apply.
local function makeSlideVelocity(root: BasePart, direction: Vector3): LinearVelocity
	local attachment = root:FindFirstChild("RootAttachment") :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "RootAttachment"
		attachment.Parent = root
	end
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "SlideVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.MaxForce = math.huge
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Constants.SLIDE_SPEED
	velocity.Parent = root
	return velocity
end

local function trySlide()
	if slideDirection then return end
	-- On the rope the Slide key and jump steer instead.
	if GrappleController.isGrappling() then return end
	if not CombatController.isCombatActive() then return end
	if CombatController.getShieldStatus() == Constants.SHIELD_UP then return end
	if os.clock() - lastSlideEndedAt < Constants.SLIDE_COOLDOWN then return end
	local hum = getHumanoid()
	if not hum or hum.FloorMaterial == Enum.Material.Air then return end
	local root = hum.RootPart
	local move = hum.MoveDirection
	if not root or move.Magnitude < 0.1 then return end
	slideDirection = Vector3.new(move.X, 0, move.Z).Unit
	slideStartedAt = os.clock()
	slideVelocity = makeSlideVelocity(root, slideDirection)
	if slideTrack then
		local speed = MovementBlend.fitSpeed(slideTrack.Length, Constants.SLIDE_DURATION)
		slideTrack:Play(Constants.ACTION_ANIM_FADE, 1, speed)
	end
end

local function stepSlide()
	local direction = slideDirection
	if not direction then return end
	local hum = getHumanoid()
	local root = hum and hum.RootPart
	local elapsed = os.clock() - slideStartedAt
	if not hum or not root or hum.FloorMaterial == Enum.Material.Air or elapsed >= Constants.SLIDE_DURATION then
		endSlide()
		return
	end
	if slideVelocity then
		local speed = slideSpeed(elapsed / Constants.SLIDE_DURATION, hum.WalkSpeed)
		slideVelocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * speed
	end
end

local function stepCameraDrop(dt: number)
	local target = if slideDirection then Constants.SLIDE_CAMERA_DROP else 0
	local maxStep = Constants.SLIDE_CAMERA_DROP * dt / Constants.SLIDE_CAMERA_DROP_TIME
	cameraDrop += math.clamp(target - cameraDrop, -maxStep, maxStep)
	ShiftLockController.setCameraDrop(cameraDrop)
end

local function tweenFov(target: number, duration: number)
	if target == currentFovTarget then return end
	currentFovTarget = target
	local camera = Workspace.CurrentCamera
	if not camera then return end
	if fovTween then fovTween:Cancel() end
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = target }
	)
	fovTween:Play()
end

-- Faster than anything on foot: the grapple pull and the fling after it.
function MovementController.isMovingFast(): boolean
	if not CombatController.isCombatActive() then return false end
	local hum = getHumanoid()
	local root = hum and hum.RootPart
	if not root then return false end
	return root.AssemblyLinearVelocity.Magnitude >= Constants.SPEED_FOV_MIN_SPEED
end

-- Aim wins over speed and sprint for the FOV; sprint still applies to WalkSpeed.
local function reconcileFov()
	if aiming then
		tweenFov(Constants.AIM_FOV, Constants.AIM_FOV_TWEEN_TIME)
	elseif MovementController.isMovingFast() then
		tweenFov(Constants.SPEED_FOV, Constants.SPRINT_FOV_TWEEN_TIME)
	elseif sprinting or slideDirection then
		tweenFov(Constants.SPRINT_FOV, Constants.SPRINT_FOV_TWEEN_TIME)
	else
		local duration = if currentFovTarget == Constants.AIM_FOV then Constants.AIM_FOV_TWEEN_TIME else Constants.SPRINT_FOV_TWEEN_TIME
		tweenFov(Constants.CAMERA_FOV, duration)
	end
end

local function canSprint(): boolean
	if not shiftHeld then return false end
	if not CombatController.isCombatActive() then return false end
	return CombatController.getShieldStatus() ~= Constants.SHIELD_UP
end

local function setSprinting(on: boolean)
	if on == sprinting then return end
	sprinting = on
	local hum = getHumanoid()
	if hum then
		hum.WalkSpeed = if on then Constants.SPRINT_WALKSPEED else Constants.SAFE_WALKSPEED
	end
end

-- The aim sensitivity multiplies the mouse delta only while aiming; otherwise
-- the stock camera turns on the player's own Roblox sensitivity alone.
local function reconcileSensitivity()
	local target = if aiming then SettingsController.get().sensitivity else 1
	if UserInputService.MouseDeltaSensitivity ~= target then
		UserInputService.MouseDeltaSensitivity = target
	end
end

local function step(dt: number)
	setSprinting(canSprint())
	aiming = aimHeld and CombatController.isCombatActive()
	reconcileFov()
	reconcileSensitivity()
	stepSlide()
	stepCameraDrop(dt)
	stepAnimations()
	if not sprinting then return end
	local hum = getHumanoid()
	if hum and hum.WalkSpeed ~= Constants.SPRINT_WALKSPEED then
		hum.WalkSpeed = Constants.SPRINT_WALKSPEED
	end
end

local function bindCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum or not hum:IsA("Humanoid") then return end
	slideDirection = nil
	task.spawn(bindAnimations, hum) -- preloading yields; the state wiring below must not wait on it
	hum.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Jumping then
			endSlide()
			if jumpTrack then
				jumpTrack:Play()
			end
		end
	end)
end

-- Touch stand-ins for holding the Sprint and Aim keys.
function MovementController.setSprintHeld(on: boolean)
	shiftHeld = on
end

function MovementController.setAimHeld(on: boolean)
	aimHeld = on
end

function MovementController.isSprinting(): boolean
	return sprinting
end

function MovementController.isAiming(): boolean
	return aiming
end

function MovementController.init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if SettingsController.matches(input, "Sprint") then
			shiftHeld = true
		elseif SettingsController.matches(input, "Aim") then
			aimHeld = true
		elseif SettingsController.matches(input, "Slide") then
			trySlide()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if SettingsController.matches(input, "Sprint") then
			shiftHeld = false
		elseif SettingsController.matches(input, "Aim") then
			aimHeld = false
		end
	end)
	localPlayer.CharacterAdded:Connect(bindCharacter)
	if localPlayer.Character then
		bindCharacter(localPlayer.Character)
	end

	RunService.RenderStepped:Connect(step)
end

return MovementController
