-- Command-bar check for the match scores: require(game.ServerScriptService.Systems.MatchScoreTest)()
-- Only the pure helpers are used, so the live scores of a running match are untouched.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local MatchScore = require(script.Parent.MatchScore)

return function()
	local state = MatchScore._new()

	-- Nobody has scored: no leader, target not reached.
	local name, kills = MatchScore._leader(state)
	assert(name == nil and kills == 0, "empty board has no leader")
	assert(not MatchScore._targetReached(state), "empty board has not reached the target")
	assert(MatchScore._kills(state, "Ann") == 0, "unknown name has no kills")

	-- Kills add up per name.
	MatchScore._addKill(state, "Ann")
	MatchScore._addKill(state, "Bob")
	MatchScore._addKill(state, "Bob")
	assert(MatchScore._kills(state, "Ann") == 1, "ann has one")
	assert(MatchScore._kills(state, "Bob") == 2, "bob has two")
	name, kills = MatchScore._leader(state)
	assert(name == "Bob" and kills == 2, "top scorer leads")

	-- A tie goes to whoever reached the count first.
	MatchScore._addKill(state, "Ann")
	name, kills = MatchScore._leader(state)
	assert(name == "Bob" and kills == 2, "bob reached two first")

	-- Passing the leader takes the lead.
	MatchScore._addKill(state, "Ann")
	name, kills = MatchScore._leader(state)
	assert(name == "Ann" and kills == 3, "ann passes bob")

	-- The top n names: kills descending, a tie to whoever reached the count first.
	local board = MatchScore._new()
	MatchScore._addKill(board, "Ann")
	MatchScore._addKill(board, "Bob")
	MatchScore._addKill(board, "Bob")
	MatchScore._addKill(board, "Cy")
	local top = MatchScore._top(board, 5)
	assert(#top == 3 and top[1] == "Bob" and top[2] == "Ann" and top[3] == "Cy", "top order")
	local two = MatchScore._top(board, 2)
	assert(#two == 2 and two[2] == "Ann", "top n cuts the list")
	assert(#MatchScore._top(MatchScore._new(), 5) == 0, "empty top")

	-- The target flips exactly at KILL_TARGET.
	local race = MatchScore._new()
	for _ = 1, Constants.KILL_TARGET - 1 do
		MatchScore._addKill(race, "Cy")
	end
	assert(not MatchScore._targetReached(race), "one short of the target")
	MatchScore._addKill(race, "Cy")
	assert(MatchScore._targetReached(race), "target reached")

	print("MatchScoreTest: all checks passed")
end
