local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)

local AbilitySystem = {}

local active = false
local lastDash: { [Player]: number } = {}
local DashRequestRemote: RemoteEvent

local function dash(player: Player)
	if not active then return end
	if PlayerState.get(player) ~= Constants.STATE_SAFE then
		return
	end

	local now = os.clock()
	if now - (lastDash[player] or 0) < Constants.DASH_COOLDOWN then
		return
	end

	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end

	-- Dash the way the player is moving (WASD, replicated via MoveDirection); forward when standing still.
	local direction = hum.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude < 0.001 then return end
	horizontal = horizontal.Unit

	lastDash[player] = now

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DashVelocity"
	lv.Attachment0 = attachment
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = horizontal * Constants.DASH_VELOCITY
	lv.Parent = root

	task.delay(Constants.DASH_DURATION, function()
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

	DashRequestRemote.OnServerEvent:Connect(function(player)
		dash(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastDash[player] = nil
	end)
end

return AbilitySystem
