local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local CombatController = require(script.Parent.CombatController)
local SettingsController = require(script.Parent.SettingsController)

-- Client-side movement extras while combat is active: hold Shift to sprint,
-- hold right click to aim (FOV zoom only), and press jump again in the air for
-- a double jump. This controller is the only writer of the camera FOV. The local
-- character is client-simulated, so WalkSpeed is set here and re-applied every
-- frame because the server rewrites it on shield changes.
local MovementController = {}

local localPlayer = Players.LocalPlayer
local shiftHeld = false
local aimHeld = false
local sprinting = false
local aiming = false
local currentFovTarget = Constants.CAMERA_FOV
local fovTween: Tween? = nil

local canDoubleJump = false
local doubleJumped = false

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
	local weights = { Idle = 0, Forward = 0, Backward = 0, Left = 0, Right = 0, Run = 0 }
	local move = localMove(hum)
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	if grounded and move then
		local amount = math.min(hum.MoveDirection.Magnitude, 1)
		weights.Forward = math.max(-move.Z, 0)
		weights.Backward = math.max(move.Z, 0)
		weights.Left = math.max(-move.X, 0)
		weights.Right = math.max(move.X, 0)
		local total = weights.Forward + weights.Backward + weights.Left + weights.Right
		if total > 0 then
			local scale = amount / total
			weights.Forward *= scale
			weights.Backward *= scale
			weights.Left *= scale
			weights.Right *= scale
		end
		if sprinting then
			weights.Run = weights.Forward
			weights.Forward = 0
		end
		weights.Idle = 1 - amount
	end

	local root = hum.RootPart
	local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local walkPlayback = math.max(horizontalSpeed / Constants.MOVEMENT_ANIM_REFERENCE_SPEED, 0.1)
	local runPlayback = math.max(horizontalSpeed / Constants.MOVEMENT_RUN_REFERENCE_SPEED, 0.1)
	for name, track in moveTracks do
		-- Applying the character's appearance after a respawn stops every track on
		-- the Animator; the stock Animate script re-plays on state events, we re-play here.
		if not track.IsPlaying then
			track:Play(0, WEIGHT_EPSILON)
		end
		track:AdjustWeight(math.max(weights[name] or 0, WEIGHT_EPSILON), Constants.MOVEMENT_ANIM_FADE)
		local playback = walkPlayback
		if name == "Idle" then
			playback = 1
		elseif name == "Run" then
			playback = runPlayback
		end
		track:AdjustSpeed(playback)
	end
end

-- Plays the sideways dash animation matching the current move direction; a forward
-- or backward dash has no animation.
function MovementController.playDashAnimation()
	local hum = getHumanoid()
	if not hum then return end
	local move = localMove(hum)
	if not move or math.abs(move.X) <= math.abs(move.Z) then return end
	local track = if move.X > 0 then dashTracks.Right else dashTracks.Left
	if track then
		track:Play()
	end
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

-- Aim wins over sprint for the FOV; sprint still applies to WalkSpeed.
local function reconcileFov()
	if aiming then
		tweenFov(Constants.AIM_FOV, Constants.AIM_FOV_TWEEN_TIME)
	elseif sprinting then
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

local function step()
	setSprinting(canSprint())
	aiming = aimHeld and CombatController.isCombatActive()
	reconcileFov()
	stepAnimations()
	if not sprinting then return end
	local hum = getHumanoid()
	if hum and hum.WalkSpeed ~= Constants.SPRINT_WALKSPEED then
		hum.WalkSpeed = Constants.SPRINT_WALKSPEED
	end
end

local function onJumpRequest()
	if not CombatController.isCombatActive() then return end
	if not canDoubleJump or doubleJumped then return end
	local hum = getHumanoid()
	if not hum or hum:GetState() ~= Enum.HumanoidStateType.Freefall then return end
	doubleJumped = true
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
end

local function bindCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum or not hum:IsA("Humanoid") then return end
	canDoubleJump = false
	doubleJumped = false
	task.spawn(bindAnimations, hum) -- preloading yields; the state wiring below must not wait on it
	hum.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Landed then
			canDoubleJump = false
			doubleJumped = false
		elseif new == Enum.HumanoidStateType.Jumping then
			if jumpTrack then
				jumpTrack:Play()
			end
		elseif new == Enum.HumanoidStateType.Freefall then
			-- Wait a beat so the first jump's own Freefall doesn't immediately count as airborne.
			task.delay(Constants.DOUBLE_JUMP_DELAY, function()
				if hum:GetState() == Enum.HumanoidStateType.Freefall then
					canDoubleJump = true
				end
			end)
		end
	end)
end

-- Touch stand-ins for holding Shift and right click.
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
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if SettingsController.matches(input, "Sprint") then
			shiftHeld = false
		elseif SettingsController.matches(input, "Aim") then
			aimHeld = false
		end
	end)
	UserInputService.JumpRequest:Connect(onJumpRequest)

	localPlayer.CharacterAdded:Connect(bindCharacter)
	if localPlayer.Character then
		bindCharacter(localPlayer.Character)
	end

	RunService.RenderStepped:Connect(step)
end

return MovementController
