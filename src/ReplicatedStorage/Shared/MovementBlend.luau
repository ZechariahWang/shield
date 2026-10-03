local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- The movement animation blend shared by the local player's MovementController
-- and the server-side BotAnimator: six looping tracks (idle, four walks, run) at
-- Movement priority whose weights sum to 1 on the ground and all drop out in the
-- air so the stock jump and fall show.
local MovementBlend = {}

export type Weights = { Idle: number, Forward: number, Backward: number, Left: number, Right: number, Run: number }

MovementBlend.TRACKS = { "Idle", "Forward", "Backward", "Left", "Right", "Run" }

-- localMove is the move direction in root space (-Z forward, +X right), amount the
-- input magnitude 0..1.
function MovementBlend.weights(localMove: Vector3, amount: number, grounded: boolean, sprinting: boolean): Weights
	local weights: Weights = { Idle = 0, Forward = 0, Backward = 0, Left = 0, Right = 0, Run = 0 }
	if not grounded then return weights end
	amount = math.clamp(amount, 0, 1)
	weights.Forward = math.max(-localMove.Z, 0)
	weights.Backward = math.max(localMove.Z, 0)
	weights.Left = math.max(-localMove.X, 0)
	weights.Right = math.max(localMove.X, 0)
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
	return weights
end

-- Which DASH_ANIMATIONS clip a dash in this root-space move direction plays:
-- sideways when it dominates, else Forward (a standing dash goes forward too).
function MovementBlend.dashTrack(localMove: Vector3): string
	if math.abs(localMove.X) > math.abs(localMove.Z) then
		return if localMove.X > 0 then "Right" else "Left"
	end
	return if localMove.Z > 0 then "Backward" else "Forward"
end

-- Playback speed of a track from the character's horizontal speed.
function MovementBlend.playback(name: string, horizontalSpeed: number): number
	if name == "Idle" then return 1 end
	local reference = if name == "Run" then Constants.MOVEMENT_RUN_REFERENCE_SPEED else Constants.MOVEMENT_ANIM_REFERENCE_SPEED
	return math.clamp(horizontalSpeed / reference, 0.1, Constants.MOVEMENT_ANIM_MAX_PLAYBACK)
end

-- Playback speed that makes a one-shot clip of `length` seconds last `duration`.
function MovementBlend.fitSpeed(length: number, duration: number): number
	if length <= 0 or duration <= 0 then return 1 end
	return length / duration
end

-- The heaviest locomotion track (never Idle), nil when none has weight. Its stride
-- phase is the one the other walk tracks keep.
function MovementBlend.leader(weights: Weights): string?
	local best: string? = nil
	local bestWeight = 0
	for _, name in MovementBlend.TRACKS do
		local weight = (weights :: { [string]: number })[name]
		if name ~= "Idle" and weight > bestWeight then
			best = name
			bestWeight = weight
		end
	end
	return best
end

-- Playback speed for a track of `length` seconds so one cycle takes as long as the
-- leader's: clips of different lengths then stay in step while they blend.
function MovementBlend.followSpeed(leaderSpeed: number, leaderLength: number, length: number): number
	if leaderLength <= 0 or length <= 0 then return leaderSpeed end
	return leaderSpeed * length / leaderLength
end

return MovementBlend
