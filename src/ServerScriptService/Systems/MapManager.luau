local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MapManager = {}

local LOADED_MAP_FOLDER_NAME = "LoadedMap"

local currentMap: Model? = nil
local lobbySpawn: SpawnLocation? = nil

local function findLobbySpawn(): SpawnLocation?
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then return nil end
	for _, child in lobby:GetChildren() do
		if child:IsA("SpawnLocation") then
			return child
		end
	end
	return nil
end

local function getLoadedMapFolder(): Folder
	local existing = Workspace:FindFirstChild(LOADED_MAP_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = LOADED_MAP_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function getCurrentSpawnPoints(): { BasePart }
	local result = {}
	if not currentMap or not currentMap.Parent then return result end
	local folder = currentMap:FindFirstChild("SpawnPoints")
	if not folder then return result end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child.Name == "SpawnPoint" then
			table.insert(result, child)
		end
	end
	return result
end

local function teleportTo(player: Player, cframe: CFrame)
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	root.CFrame = cframe
end

function MapManager.loadRandomMap(): boolean
	MapManager.unloadMap()

	local mapsFolder = ServerStorage:FindFirstChild("Maps")
	if not mapsFolder then
		warn("MapManager: ServerStorage.Maps folder is missing")
		return false
	end

	local maps: { Model } = {}
	for _, child in mapsFolder:GetChildren() do
		if child:IsA("Model") then
			table.insert(maps, child)
		end
	end

	if #maps == 0 then
		warn("MapManager: no Models found in ServerStorage.Maps")
		return false
	end

	local picked = maps[math.random(1, #maps)]
	local clone = picked:Clone()
	clone.Parent = getLoadedMapFolder()
	currentMap = clone
	return true
end

function MapManager.unloadMap()
	currentMap = nil
	local folder = Workspace:FindFirstChild(LOADED_MAP_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
end

function MapManager.hasMap(): boolean
	return currentMap ~= nil and currentMap.Parent ~= nil
end

function MapManager.randomSpawnCFrame(): CFrame?
	local spawns = getCurrentSpawnPoints()
	if #spawns == 0 then return nil end
	return spawns[math.random(1, #spawns)].CFrame
end

-- Index of the spawn point whose nearest enemy is farthest away; any point
-- when there are no enemies, nil when there are no spawn points.
function MapManager._pickSpawn(spawns: { Vector3 }, enemies: { Vector3 }): number?
	if #spawns == 0 then return nil end
	if #enemies == 0 then
		return math.random(1, #spawns)
	end
	local bestIndex = 1
	local bestDistance = -1
	for index, spawn in spawns do
		local nearest = math.huge
		for _, enemy in enemies do
			local distance = (enemy - spawn).Magnitude
			if distance < nearest then
				nearest = distance
			end
		end
		if nearest > bestDistance then
			bestDistance = nearest
			bestIndex = index
		end
	end
	return bestIndex
end

-- Where every live combatant stands (the InRound tag: Safe players and bots), `exclude` left out.
local function combatantPositions(exclude: Model?): { Vector3 }
	local positions: { Vector3 } = {}
	for _, tagged in CollectionService:GetTagged(Constants.IN_ROUND_TAG) do
		local model: Instance? = tagged
		if tagged:IsA("Player") then
			model = tagged.Character
		end
		if not model or model == exclude then continue end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

-- The spawn point farthest from every live combatant but `exclude`.
function MapManager.spawnCFrameAwayFrom(exclude: Model?): CFrame?
	local spawns = getCurrentSpawnPoints()
	local spawnPositions: { Vector3 } = {}
	for _, spawn in spawns do
		table.insert(spawnPositions, spawn.Position)
	end
	local index = MapManager._pickSpawn(spawnPositions, combatantPositions(exclude))
	if not index then return nil end
	return spawns[index].CFrame
end

function MapManager.teleportToArena(player: Player)
	local spawn = MapManager.spawnCFrameAwayFrom(player.Character)
	if not spawn then
		warn("MapManager: current map has no SpawnPoints: using fallback")
		teleportTo(player, CFrame.new(0, 5, 0))
		return
	end
	teleportTo(player, spawn + Vector3.new(0, 4, 0))
end

function MapManager.teleportToLobby(player: Player)
	if not lobbySpawn or not lobbySpawn.Parent then
		lobbySpawn = findLobbySpawn()
	end
	if lobbySpawn then
		teleportTo(player, lobbySpawn.CFrame + Vector3.new(0, 4, 0))
	else
		teleportTo(player, CFrame.new(0, 5, 0))
	end
end

function MapManager.init()
	-- Clear any stale map folder from a previous server session before maps load.
	local stale = Workspace:FindFirstChild(LOADED_MAP_FOLDER_NAME)
	if stale then
		stale:Destroy()
	end

	lobbySpawn = findLobbySpawn()
	if not lobbySpawn then
		warn("MapManager: no SpawnLocation found in Workspace.Lobby: players may not spawn correctly")
	end

	local mapsFolder = ServerStorage:FindFirstChild("Maps")
	if not mapsFolder then
		warn("MapManager: ServerStorage.Maps folder is missing: rounds cannot start. Create a Folder named 'Maps' in ServerStorage and place at least one Model inside it.")
		return
	end

	local mapCount = 0
	for _, child in mapsFolder:GetChildren() do
		if child:IsA("Model") then
			mapCount += 1
		end
	end
	if mapCount == 0 then
		warn("MapManager: ServerStorage.Maps contains no Models: rounds cannot start. Add at least one Model to that folder.")
	end
end

return MapManager
