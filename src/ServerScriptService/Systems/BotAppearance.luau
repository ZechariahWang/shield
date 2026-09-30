local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- A bot's look and name. The name is generated from word parts so it reads like
-- a player without being anyone's; the look is a random real avatar fetched by
-- user id in the background, over random body colors that stay if every fetch
-- fails (no web access, deleted account).
local BotAppearance = {}

local function pick(list: { string }): string
	return list[math.random(1, #list)]
end

-- Unique against the names already taken this round and the players on the server.
function BotAppearance.randomName(taken: { [string]: boolean }): string
	for _ = 1, 50 do
		local adjective = pick(Constants.BOT_NAME_ADJECTIVES)
		local noun = pick(Constants.BOT_NAME_NOUNS)
		local style = math.random(1, 4)
		local name: string
		if style == 1 then
			name = adjective .. noun
		elseif style == 2 then
			name = adjective .. noun .. tostring(math.random(1, 99))
		elseif style == 3 then
			name = adjective .. "_" .. noun .. tostring(math.random(2005, 2015))
		else
			name = "xX" .. adjective .. noun .. "Xx"
		end
		if not taken[name] and not Players:FindFirstChild(name) then
			return name
		end
	end
	return "Player" .. tostring(math.random(1000, 9999))
end

local function randomBodyColors(char: Model)
	local colors = char:FindFirstChildOfClass("BodyColors")
	if not colors then
		colors = Instance.new("BodyColors")
		colors.Parent = char
	end
	local skin = Color3.fromHSV(0.05 + math.random() * 0.05, 0.3 + math.random() * 0.4, 0.4 + math.random() * 0.5)
	local shirt = Color3.fromHSV(math.random(), 0.5 + math.random() * 0.5, 0.4 + math.random() * 0.5)
	local pants = Color3.fromHSV(math.random(), 0.4 + math.random() * 0.4, 0.2 + math.random() * 0.5)
	colors.HeadColor3 = skin
	colors.LeftArmColor3 = skin
	colors.RightArmColor3 = skin
	colors.TorsoColor3 = shirt
	colors.LeftLegColor3 = pants
	colors.RightLegColor3 = pants
end

local function randomUserId(): number
	local range = Constants.BOT_AVATAR_USER_ID_RANGE
	return math.floor(range[1] + math.random() * (range[2] - range[1]))
end

-- Colors now, the fetched avatar whenever it lands; call once the model is in Workspace.
function BotAppearance.apply(char: Model)
	randomBodyColors(char)
	task.spawn(function()
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		for _ = 1, Constants.BOT_AVATAR_TRIES do
			local userId = randomUserId()
			local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
			if ok and description then
				if not char.Parent then return end
				local applied = pcall(hum.ApplyDescription, hum, description)
				if applied then
					char:SetAttribute("AvatarUserId", userId)
					return
				end
			end
		end
	end)
end

return BotAppearance
