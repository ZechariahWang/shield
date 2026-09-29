-- Command-bar check for the spawn point choice: require(game.ServerScriptService.Systems.SpawnPickTest)()
local MapManager = require(script.Parent.MapManager)

return function()
	local spawns = {
		Vector3.new(0, 0, 0),
		Vector3.new(100, 0, 0),
		Vector3.new(50, 0, 0),
	}

	-- No spawn points: nothing to pick.
	assert(MapManager._pickSpawn({}, {}) == nil, "no spawn points")
	assert(MapManager._pickSpawn({}, { Vector3.new(1, 0, 0) }) == nil, "no spawn points with enemies")

	-- No enemies: any spawn point will do.
	local free = MapManager._pickSpawn(spawns, {})
	assert(free ~= nil and free >= 1 and free <= #spawns, "any point without enemies")

	-- One enemy: the point farthest from it.
	assert(MapManager._pickSpawn(spawns, { Vector3.new(0, 0, 0) }) == 2, "farthest from the enemy")
	assert(MapManager._pickSpawn(spawns, { Vector3.new(100, 0, 0) }) == 1, "farthest from the other end")

	-- Several enemies: the nearest one to each point is what counts.
	local enemies = { Vector3.new(0, 0, 0), Vector3.new(100, 0, 0) }
	assert(MapManager._pickSpawn(spawns, enemies) == 3, "the middle is farthest from both ends")

	-- Height counts as distance too.
	local stacked = { Vector3.new(0, 0, 0), Vector3.new(0, 80, 0) }
	assert(MapManager._pickSpawn(stacked, { Vector3.new(5, 0, 0) }) == 2, "the upper floor is farther")

	print("SpawnPickTest: all checks passed")
end
