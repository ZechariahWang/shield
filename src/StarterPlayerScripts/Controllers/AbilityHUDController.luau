local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Abilities = require(ReplicatedStorage.Shared.Abilities)

local AbilityHUDController = {}

local localPlayer = Players.LocalPlayer
local PlayerStateRemote: RemoteEvent
local RoundStateRemote: RemoteEvent

local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY
local activeAbilityId: string? = nil

local cooldownGen = 0
local activeTween: Tween? = nil

local playerGui: PlayerGui
local container: GuiObject?
local iconLabel: ImageLabel?
local titleLabel: TextLabel?
local overlay: GuiObject?
local overlayNormalized = false

local function resolveElements()
	if container and container.Parent then return end
	container = nil
	iconLabel = nil
	titleLabel = nil
	overlay = nil
	overlayNormalized = false

	if not playerGui then return end
	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return end

	local actions = gameGui:FindFirstChild("Actions")
	if not actions then return end
	local ability = actions:FindFirstChild("AbilityAction")
	if not ability or not ability:IsA("GuiObject") then return end
	container = ability

	local icon = ability:FindFirstChild("AbilityIcon")
	if icon and icon:IsA("ImageLabel") then
		iconLabel = icon
	end

	local title = ability:FindFirstChild("AbilityTitle")
	if title and title:IsA("TextLabel") then
		titleLabel = title
	end

	local ov = ability:FindFirstChild("Overlay")
	if ov and ov:IsA("GuiObject") then
		overlay = ov
	end
end

local function normalizeOverlay()
	if not overlay or overlayNormalized then return end
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.new(0, 0, 1, 0)
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlayNormalized = true
end

local function cancelCooldownTween()
	cooldownGen += 1
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	if overlay then
		overlay.Visible = false
		overlay.Size = UDim2.new(1, 0, 1, 0)
	end
end

local function applyAbility(ability: Abilities.AbilityDef)
	resolveElements()
	if iconLabel then
		iconLabel.Image = ability.icon
		iconLabel.ImageColor3 = ability.iconColor
	end
	if titleLabel then
		titleLabel.Text = ability.displayName
	end
end

function AbilityHUDController.setActiveAbility(abilityId: string?)
	if activeAbilityId == abilityId then return end
	activeAbilityId = abilityId

	resolveElements()
	cancelCooldownTween()

	if not container then return end

	if not abilityId then
		container.Visible = false
		return
	end

	local ability = Abilities.get(abilityId)
	if not ability then
		container.Visible = false
		return
	end

	applyAbility(ability)
	normalizeOverlay()
	container.Visible = true
end

function AbilityHUDController.triggerCooldown(abilityId: string)
	local ability = Abilities.get(abilityId)
	if not ability then return end

	resolveElements()
	if not overlay then return end
	normalizeOverlay()

	cooldownGen += 1
	local gen = cooldownGen
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end

	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundTransparency = 0.2
	overlay.Visible = true

	local tween = TweenService:Create(
		overlay,
		TweenInfo.new(ability.params.cooldown, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, 0, 0) }
	)
	activeTween = tween
	tween.Completed:Connect(function()
		if gen ~= cooldownGen then return end
		if overlay then
			overlay.Visible = false
			overlay.Size = UDim2.new(1, 0, 1, 0)
		end
		activeTween = nil
	end)
	tween:Play()
end

local function isInGame(): boolean
	if currentPhase ~= Constants.PHASE_ROUND then return false end
	return localState == Constants.STATE_SAFE
end

local function resolveAbilityForRole(): Abilities.AbilityDef?
	local category = Abilities.categoryForState(localState)
	if not category then return nil end
	return Abilities.primaryFor(category)
end

local function reconcileVisibility()
	if not isInGame() then
		AbilityHUDController.setActiveAbility(nil)
		return
	end

	local ability = resolveAbilityForRole()
	if not ability then
		AbilityHUDController.setActiveAbility(nil)
		return
	end

	AbilityHUDController.setActiveAbility(ability.id)
end

function AbilityHUDController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	resolveElements()
	normalizeOverlay()
	if container then
		container.Visible = false
	end

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		localState = state
		reconcileVisibility()
	end)

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		reconcileVisibility()
	end)
end

return AbilityHUDController
