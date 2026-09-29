local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local ChangeIndicatorController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local frame: Frame?
local titleLabel: TextLabel?
local infoLabel: TextLabel?
local frameScale: UIScale?
local cachedInfoPosition: UDim2? = nil

local activeKind: string? = nil
local gen = 0
local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY

local ENTRANCE_TIME = 0.3
local EXIT_TIME = 0.5
local TOTAL_ON_SCREEN = 5.0

local function ensureScale(parent: GuiObject): UIScale
	local existing = parent:FindFirstChildOfClass("UIScale")
	if existing then return existing end
	local scale = Instance.new("UIScale")
	scale.Parent = parent
	return scale
end

local function resolveElements(): boolean
	if frame and frame.Parent and titleLabel and titleLabel.Parent and infoLabel and infoLabel.Parent then
		return true
	end
	if not playerGui then return false end

	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return false end

	local f = gameGui:FindFirstChild("ChangeIndicator")
	if not f or not f:IsA("Frame") then return false end
	frame = f

	local t = f:FindFirstChild("Title")
	if not t or not t:IsA("TextLabel") then return false end
	titleLabel = t

	local i = f:FindFirstChild("UpdatedInfo")
	if not i or not i:IsA("TextLabel") then return false end
	infoLabel = i

	frameScale = ensureScale(f)
	if not cachedInfoPosition then
		cachedInfoPosition = i.Position
	end

	if not t.RichText then t.RichText = true end
	if not i.RichText then i.RichText = true end

	f.Visible = false
	frameScale.Scale = 0
	return true
end

local function tween(obj: Instance, info: TweenInfo, props: { [string]: any })
	TweenService:Create(obj, info, props):Play()
end

local function isStillActive(myGen: number): boolean
	return myGen == gen and activeKind ~= nil
end

local function finishAnimation(myGen: number)
	if myGen ~= gen then return end
	activeKind = nil
	if frame then frame.Visible = false end
	if frameScale then frameScale.Scale = 0 end
	if infoLabel and cachedInfoPosition then
		infoLabel.Position = cachedInfoPosition
		infoLabel.TextTransparency = 0
	end
end

local function playEliminated()
	gen += 1
	activeKind = "eliminated"
	local myGen = gen

	if not resolveElements() then
		activeKind = nil
		return
	end
	assert(frame and titleLabel and infoLabel and frameScale and cachedInfoPosition)

	titleLabel.Text = "ELIMINATED"
	titleLabel.TextColor3 = Constants.WHITE
	infoLabel.Text = "PRESS SPAWN"
	infoLabel.TextColor3 = Constants.TAGGER_COLOR
	infoLabel.Position = cachedInfoPosition
	infoLabel.TextTransparency = 0

	frameScale.Scale = 0
	frame.Visible = true

	tween(frameScale,
		TweenInfo.new(ENTRANCE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	task.wait(ENTRANCE_TIME)
	if not isStillActive(myGen) then return end

	local hold = TOTAL_ON_SCREEN - ENTRANCE_TIME - EXIT_TIME
	if hold > 0 then
		task.wait(hold)
		if not isStillActive(myGen) then return end
	end

	tween(frameScale,
		TweenInfo.new(EXIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	)
	task.wait(EXIT_TIME)
	finishAnimation(myGen)
end

function ChangeIndicatorController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")
	resolveElements()

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
	end)

	-- Every death during a match plays the banner: the match goes on and the player can spawn back in.
	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		local prev = localState
		localState = state
		if prev ~= Constants.STATE_SAFE or state == Constants.STATE_SAFE then return end
		if currentPhase ~= Constants.PHASE_ROUND then return end

		task.spawn(playEliminated)
	end)
end

return ChangeIndicatorController
