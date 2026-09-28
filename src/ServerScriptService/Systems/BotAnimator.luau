local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MovementBlend = require(ReplicatedStorage.Shared.MovementBlend)

-- Server-side movement animations for bots: the same six looping clips the
-- local player's MovementController blends, plus the jump clip on every Jumping
-- state, driven by the same MovementBlend math so bots walk, strafe and run like
-- players. Tracks loaded on the server replicate to every client.
local BotAnimator = {}

local WEIGHT_EPSILON = 0.001

type Entry = { hum: Humanoid, tracks: { [string]: AnimationTrack }, connection: RBXScriptConnection }
local entries: { [Model]: Entry } = {}

local function makeAnimation(id: string): Animation
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	return animation
end

-- Call once the model is in Workspace; LoadAnimation needs it in the DataModel.
function BotAnimator.attach(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local tracks: { [string]: AnimationTrack } = {}
	for name, id in Constants.MOVEMENT_ANIMATIONS do
		local track = animator:LoadAnimation(makeAnimation(id))
		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = true
		track:Play(0, WEIGHT_EPSILON)
		tracks[name] = track
	end
	local jump = animator:LoadAnimation(makeAnimation(Constants.JUMP_ANIMATION))
	jump.Priority = Enum.AnimationPriority.Action
	local connection = hum.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Jumping then
			jump:Play()
		end
	end)
	entries[char] = { hum = hum, tracks = tracks, connection = connection }
end

function BotAnimator.detach(char: Model)
	local entry = entries[char]
	if not entry then return end
	entry.connection:Disconnect()
	entries[char] = nil
end

function BotAnimator.clear()
	for char in entries do
		BotAnimator.detach(char)
	end
end

local function stepEntry(char: Model, entry: Entry)
	local hum = entry.hum
	local root = hum.RootPart
	if not root then return end
	local move = root.CFrame:VectorToObjectSpace(hum.MoveDirection)
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local sprinting = hum.WalkSpeed >= Constants.SPRINT_WALKSPEED
	local weights = MovementBlend.weights(move, hum.MoveDirection.Magnitude, grounded, sprinting)
	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	for name, track in entry.tracks do
		-- The clip's authored priority and loop flag replace what attach set once its
		-- data arrives (the client preloads to dodge this; the server just re-asserts).
		if track.Priority ~= Enum.AnimationPriority.Movement then
			track.Priority = Enum.AnimationPriority.Movement
		end
		if not track.Looped then
			track.Looped = true
		end
		if not track.IsPlaying then
			track:Play(0, WEIGHT_EPSILON)
		end
		track:AdjustWeight(math.max(weights[name] or 0, WEIGHT_EPSILON), Constants.MOVEMENT_ANIM_FADE)
		track:AdjustSpeed(MovementBlend.playback(name, horizontalSpeed))
	end
end

local function step()
	for char, entry in entries do
		if not char.Parent then
			BotAnimator.detach(char)
		else
			stepEntry(char, entry)
		end
	end
end

function BotAnimator.init()
	RunService.Heartbeat:Connect(step)
end

return BotAnimator
