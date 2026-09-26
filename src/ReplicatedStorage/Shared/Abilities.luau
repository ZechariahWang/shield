local Catalog = require(script.Parent.Catalog)

export type AbilityParams = Catalog.AbilityParams

export type AbilityDef = {
	id: string,
	displayName: string,
	icon: string,
	iconColor: Color3,
	params: AbilityParams,
}

local Abilities = {}

Abilities.DEFAULT_PARAMS = { cooldown = 3 } :: AbilityParams

function Abilities.params(id: string): AbilityParams
	local data = Catalog.get(Catalog.KIND_ABILITIES, id)
	if data and data.params then
		return data.params
	end
	return Abilities.DEFAULT_PARAMS
end

function Abilities.get(id: string): AbilityDef?
	local data = Catalog.get(Catalog.KIND_ABILITIES, id)
	if not data then return nil end

	local icon = Catalog.icon(Catalog.KIND_ABILITIES, id)
	local image = ""
	local color = Color3.new(1, 1, 1)
	if icon then
		image = icon.Image
		color = icon.ImageColor3
	end

	return {
		id = id,
		displayName = data.displayName,
		icon = image,
		iconColor = color,
		params = Abilities.params(id),
	}
end

return Abilities
