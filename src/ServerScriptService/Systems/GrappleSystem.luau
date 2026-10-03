local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local GrappleMath = require(ReplicatedStorage.Shared.GrappleMath)
local CombatSystem = require(script.Parent.CombatSystem)
local PlayerState = require(script.Parent.PlayerState)

-- The server side of the grapple: validates the request and owns the rope, one
-- Beam from the right hand to the anchor, so every client sees it. The hook end
-- flies from the hand to the anchor over GrappleMath.hookTime with the rope
-- sagging behind it, and the rope is straight once it lands. The pull itself runs
-- on the owner's client (GrappleController), which simulates the character.
local GrappleSystem = {}

type Rope = {
	beam: Beam,
	hand: Attachment,
	anchor: Attachment,
	target: Vector3,
	firedAt: number,
	flightTime: number,
	latched: boolean,
	expiresAt: number,
}

local active = false
local ropes: { [Player]: Rope } = {}
local lastReleaseAt: { [Player]: number } = {}

local GrappleRequestRemote: RemoteEvent
local GrappleReleaseRemote: RemoteEvent

local function ensureRemote(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function release(player: Player)
	local rope = ropes[player]
	if not rope then return end
	ropes[player] = nil
	lastReleaseAt[player] = os.clock()
	rope.beam:Destroy()
	rope.hand:Destroy()
	rope.anchor:Destroy()
end

local function makeRope(char: Model, root: BasePart, anchorPoint: Vector3, flightTime: number): Rope
	local hand = Instance.new("Attachment")
	hand.Name = "GrappleHand"
	local arm = char:FindFirstChild("Right Arm")
	if arm and arm:IsA("BasePart") then
		hand.Position = Vector3.new(0, -arm.Size.Y / 2, 0)
		hand.Parent = arm
	else
		hand.Parent = root
	end

	-- An Attachment needs a part; Terrain is the one that is always there.
	local anchor = Instance.new("Attachment")
	anchor.Name = "GrappleAnchor"
	anchor.Parent = Workspace.Terrain
	-- The hook starts at the hand. Its X axis points up: a Beam bends along that
	-- axis, so CurveSize1 makes the rope sag.
	anchor.WorldCFrame = CFrame.new(hand.WorldPosition) * CFrame.Angles(0, 0, math.rad(90))

	local beam = Instance.new("Beam")
	beam.Name = "GrappleRope"
	beam.Attachment0 = hand
	beam.Attachment1 = anchor
	beam.Width0 = Constants.GRAPPLE_ROPE_WIDTH
	beam.Width1 = Constants.GRAPPLE_ROPE_WIDTH
	beam.Color = ColorSequence.new(Constants.GRAPPLE_ROPE_COLOR)
	beam.FaceCamera = true
	beam.Segments = 10
	beam.CurveSize1 = Constants.GRAPPLE_ROPE_SLACK
	beam.Parent = char

	local now = os.clock()
	return {
		beam = beam,
		hand = hand,
		anchor = anchor,
		target = anchorPoint,
		firedAt = now,
		flightTime = flightTime,
		latched = false,
		expiresAt = now + Constants.GRAPPLE_MAX_TIME,
	}
end

local function stepFlight(rope: Rope, now: number)
	if rope.latched then return end
	local progress = GrappleMath.hookProgress(now - rope.firedAt, rope.flightTime)
	rope.anchor.WorldPosition = rope.hand.WorldPosition:Lerp(rope.target, progress)
	rope.beam.CurveSize1 = Constants.GRAPPLE_ROPE_SLACK * (1 - progress)
	if progress >= 1 then
		rope.latched = true
	end
end

local function grapple(player: Player, anchorPoint: any)
	if not active then return end
	if PlayerState.get(player) ~= Constants.STATE_SAFE then return end
	if ropes[player] then return end

	local now = os.clock()
	local since = now - (lastReleaseAt[player] or -math.huge)
	if since < Constants.GRAPPLE_COOLDOWN - Constants.GRAPPLE_COOLDOWN_TOLERANCE then return end

	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then return end
	if CombatSystem.shieldUp(char) then return end
	if not GrappleMath.validAnchor(root.Position, anchorPoint, Constants.PISTOL_ORIGIN_TOLERANCE) then return end

	local flightTime = GrappleMath.hookTime((anchorPoint - root.Position).Magnitude)
	ropes[player] = makeRope(char, root, anchorPoint, flightTime)
end

local function step()
	local now = os.clock()
	for player, rope in ropes do
		local char = player.Character
		local gone = char == nil or not rope.beam:IsDescendantOf(Workspace)
		local notSafe = PlayerState.get(player) ~= Constants.STATE_SAFE
		if gone or notSafe or now >= rope.expiresAt or CombatSystem.shieldUp(char :: Model) then
			release(player)
		else
			stepFlight(rope, now)
		end
	end
end

function GrappleSystem.start()
	table.clear(lastReleaseAt)
	active = true
end

function GrappleSystem.stop()
	active = false
	for player in ropes do
		release(player)
	end
end

function GrappleSystem.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	GrappleRequestRemote = ensureRemote(Remotes, "GrappleRequest")
	GrappleReleaseRemote = ensureRemote(Remotes, "GrappleRelease")

	GrappleRequestRemote.OnServerEvent:Connect(grapple)
	GrappleReleaseRemote.OnServerEvent:Connect(release)

	Players.PlayerRemoving:Connect(function(player)
		release(player)
		lastReleaseAt[player] = nil
	end)

	RunService.Heartbeat:Connect(step)
end

return GrappleSystem
