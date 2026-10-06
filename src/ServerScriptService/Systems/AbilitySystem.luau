local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local DashMath = require(ReplicatedStorage.Shared.DashMath)
local PlayerState = require(script.Parent.PlayerState)
local Store = require(script.Parent.Store)

local AbilitySystem = {}

AbilitySystem.DASH = "Dash"

local active = false
local lastDash: { [Player]: number } = {}
local DashRequestRemote: RemoteEvent

local function dash(player: Player, direction: any)
	if not active then return end
	if PlayerState.get(player) ~= Constants.STATE_SAFE then
		return
	end
	-- Only Dash has behavior; any other equipped ability is inert.
	if Store.equipped(player, Catalog.KIND_ABILITIES) ~= AbilitySystem.DASH then
		return
	end

	local params = Abilities.params(AbilitySystem.DASH)
	local now = os.clock()
	if now - (lastDash[player] or 0) < params.cooldown then
		return
	end

	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end

	-- The client names the direction: where its crosshair points, up or down included.
	local unit = DashMath.unit(direction)
	if not unit then return end

	lastDash[player] = now

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root

	-- All three axes, so the dash holds its line against gravity. The force is
	-- finite: a wall or the floor stops the dash instead of the solver launching
	-- the character off it.
	local lv = Instance.new("LinearVelocity")
	lv.Name = "DashVelocity"
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = root.AssemblyMass * Constants.PUSH_MAX_ACCEL
	lv.VectorVelocity = unit * (params.velocity or 0)
	lv.Parent = root

	task.delay(params.duration or 0, function()
		if lv and lv.Parent then lv:Destroy() end
		if attachment and attachment.Parent then attachment:Destroy() end
	end)
end

function AbilitySystem.start()
	active = true
	-- Stale cooldowns from a previous round shouldn't carry over.
	table.clear(lastDash)
end

function AbilitySystem.stop()
	active = false
end

function AbilitySystem.init()
	DashRequestRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DashRequest") :: RemoteEvent

	DashRequestRemote.OnServerEvent:Connect(dash)

	Players.PlayerRemoving:Connect(function(player)
		lastDash[player] = nil
	end)
end

return AbilitySystem
