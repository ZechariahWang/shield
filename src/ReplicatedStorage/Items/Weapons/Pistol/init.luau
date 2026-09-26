-- The Pistol's Frame points +X toward the barrel and +Y up; the grip maps that to
-- the arm's -Y (forward when raised) and -Z, with the magazine sitting in the hand.
return {
	displayName = "Pistol",
	price = 0,
	description = "Standard issue sidearm. One clean shot eliminates.",
	stats = { { "Damage", 100 }, { "Range", 200 }, { "Cooldown", "1s" } },
	grip = CFrame.new(0, -0.99, 0.09, 0, 0, 1, -1, 0, 0, 0, -1, 0),
}
