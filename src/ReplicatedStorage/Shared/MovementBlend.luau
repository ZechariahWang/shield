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

-- Playback speed of a track from the character's horizontal speed.
function MovementBlend.playback(name: string, horizontalSpeed: number): number
	if name == "Idle" then return 1 end
	local reference = if name == "Run" then Constants.MOVEMENT_RUN_REFERENCE_SPEED else Constants.MOVEMENT_ANIM_REFERENCE_SPEED
	return math.max(horizontalSpeed / reference, 0.1)
end

return MovementBlend
