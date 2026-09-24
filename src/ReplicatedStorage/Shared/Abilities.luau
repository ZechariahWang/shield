local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(script.Parent.Constants)

export type AbilityParams = {
	cooldown: number,
	duration: number?,
	velocity: number?,
}

export type AbilityDef = {
	id: string,
	displayName: string,
	icon: string,
	iconColor: Color3,
	params: AbilityParams,
}

local Abilities = {}

Abilities.Params = {
	Dash = { cooldown = 3, duration = 0.2, velocity = 60 },
	TestAbility = { cooldown = 5 },
} :: { [string]: AbilityParams }

Abilities.DEFAULT_PARAMS = { cooldown = 3 } :: AbilityParams

Abilities.CATEGORY_SURVIVOR = "Survivor"

Abilities.Categories = {
	[Abilities.CATEGORY_SURVIVOR] = { "Dash" },
} :: { [string]: { string } }

function Abilities.params(id: string): AbilityParams
	return Abilities.Params[id] or Abilities.DEFAULT_PARAMS
end

function Abilities.get(id: string): AbilityDef?
	local root = ReplicatedStorage:FindFirstChild("Abilities")
	if not root then return nil end
	local folder = root:FindFirstChild(id)
	if not folder then return nil end

	local icon = folder:FindFirstChild("AbilityIcon")
	local image = ""
	local color = Color3.new(1, 1, 1)
	if icon and icon:IsA("ImageLabel") then
		image = icon.Image
		color = icon.ImageColor3
	end

	return {
		id = id,
		displayName = folder.Name,
		icon = image,
		iconColor = color,
		params = Abilities.params(id),
	}
end

function Abilities.primaryFor(category: string): AbilityDef?
	local ids = Abilities.Categories[category]
	if not ids or #ids == 0 then return nil end
	return Abilities.get(ids[1])
end

function Abilities.categoryForState(state: string): string?
	if state == Constants.STATE_SAFE then
		return Abilities.CATEGORY_SURVIVOR
	end
	return nil
end

return Abilities
