local Constants = {}

-- ROUND
Constants.MIN_PLAYERS = 2
Constants.INTERMISSION_TIME = 10
Constants.REVEAL_TIME = 10 -- pre-round positioning grace. No damage, no abilities.
Constants.ROUND_TIME = 90
Constants.END_DELAY_TIME = 3 -- post-round freeze: players stay in arena, invincible, abilities/shooting off, before teleport to lobby
Constants.END_TIME = 5

-- TEST MODE (solo playtesting). Rounds start with one player, the timer and
-- last-standing checks are off, and the round ends when a Safe player touches
-- a part named TEST_END_WALL in the loaded map (or when no real player is Safe).
Constants.TEST_MODE = true
Constants.TEST_END_WALL = "ShortWall"

-- BOTS (server-driven combatants cloned from ReplicatedStorage.Assets.Rigs.NPC)
Constants.BOT_COUNT = 3                   -- spawned at Reveal, removed at round end; 0 disables
Constants.BOT_RIG_PATH = { "Assets", "Rigs", "NPC" }
Constants.BOT_SHOOT_INTERVAL = { 2, 5 }    -- seconds between shots, uniform random
Constants.BOT_SHIELD_INTERVAL = { 4, 10 }  -- seconds between shield raises, uniform random
Constants.BOT_AIM_JITTER = 0.2            -- radians of random error on an aimed shot (they miss a lot on purpose)
Constants.BOT_WAYPOINT_TIMEOUT = 4        -- seconds before a stuck bot picks a new destination

-- PISTOL
Constants.PISTOL_COOLDOWN = 1.0
Constants.PISTOL_COOLDOWN_TOLERANCE = 0.05 -- server slack for network jitter: the client stamps at send, the server at receive
Constants.PISTOL_RANGE = 200              -- studs
Constants.PISTOL_DAMAGE = 100             -- one shot eliminates
Constants.PISTOL_ORIGIN_TOLERANCE = 8     -- studs; max distance between client-reported origin and the head
Constants.PISTOL_TRACER_LIFETIME = 0.08   -- seconds the tracer part stays in Workspace
Constants.PISTOL_SHOT_SOUND = "rbxassetid://127604219525464"  -- played at the shooter's head, server side
Constants.SOUND_CLEANUP_TIME = 3          -- seconds before a one-shot Sound instance is removed

-- SHIELD
Constants.SHIELD_DURATIONS = { 1.0, 0.5, 0.25 } -- active seconds; index = 1 + breaks in the current chain (clamped)
Constants.SHIELD_COOLDOWN = 3.0           -- after natural expiry or manual lower. A break has no cooldown.
Constants.SHIELD_CHAIN_RESET = 5.0        -- seconds since the last break before the chain resets to full duration
Constants.SHIELD_WALKSPEED = 12           -- while the shield is up
Constants.SHIELD_SIZE = 8                 -- diameter (studs) of the bubble welded to the root part
Constants.SHIELD_COLOR = Color3.fromRGB(0, 210, 255)
Constants.SHIELD_TRANSPARENCY = 0.25
Constants.SHIELD_BREAK_FX_TIME = 0.25     -- seconds the shattered bubble takes to swell and fade
Constants.SHIELD_BREAK_FX_SCALE = 1.4
Constants.SHIELD_BREAK_PARTICLES = 28     -- shard burst count on a break
Constants.SHIELD_BREAK_RING_SIZE = 18     -- studs the ground ring expands to
Constants.SHIELD_BREAK_RING_TIME = 0.35
Constants.SHIELD_RAISE_FX_TIME = 0.2      -- bubble pops in from SHIELD_RAISE_FX_START scale with a Back overshoot
Constants.SHIELD_RAISE_FX_START = 0.3
Constants.SHIELD_LOWER_FX_TIME = 0.15     -- bubble shrinks to SHIELD_LOWER_FX_SCALE and fades on lower/expiry
Constants.SHIELD_LOWER_FX_SCALE = 0.5
Constants.SHIELD_RAISE_SOUND = "rbxassetid://102387902167220"  -- all shield sounds play at the owner's head, server side
Constants.SHIELD_LOWER_SOUND = "rbxassetid://130860293177595"  -- natural expiry and manual lower
Constants.SHIELD_BREAK_SOUND = "rbxassetid://132492701741331"  -- a shot landed on the raised shield

-- MOVEMENT
Constants.SAFE_WALKSPEED = 16
Constants.SPRINT_WALKSPEED = 24           -- hold Shift during combat; blocked while the shield is up
Constants.CAMERA_FOV = 70
Constants.SPRINT_FOV = 82
Constants.SPRINT_FOV_TWEEN_TIME = 0.25
Constants.SHIFTLOCK_CAMERA_OFFSET = Vector3.new(2.5, 0, 0) -- shoulder offset during combat (stock shift lock uses 1.75; wider keeps the character clear of the crosshair)
Constants.AIM_FOV = 50                    -- hold right click during combat
Constants.AIM_FOV_TWEEN_TIME = 0.15
Constants.DOUBLE_JUMP_DELAY = 0.15        -- seconds airborne before a second jump is allowed
Constants.MOVEMENT_STRIDE_LENGTH = 1.6        -- studs of horizontal foot drift before a swing fires
Constants.MOVEMENT_STEP_HEIGHT = 0.55         -- peak vertical arc of a swinging foot
Constants.MOVEMENT_STEP_TIME = 0.18           -- seconds per swing
Constants.MOVEMENT_TURN_RATE = 14             -- exp-decay rate of HRP yaw toward camera yaw
Constants.MOVEMENT_GROUND_RAYCAST_DEPTH = 6   -- max stud distance below the ideal foot pos to look for ground

-- KILL CAM (victim's camera swings to face the killer after elimination)
Constants.KILL_CAM_TIME = 3
Constants.KILL_CAM_DISTANCE = 7
Constants.KILL_CAM_HEIGHT = 2
Constants.KILL_CAM_TWEEN_TIME = 0.6

-- THIRD-PERSON WEAPON (welded to every player by RoundManager)
Constants.VIEWMODEL_DEFAULT_WEAPON = "Pistol"
-- Grip CFrame (Right Arm space -> weapon primary part) for weapons without a
-- ThirdPersonRigs entry. The Pistol's Frame points +X toward the barrel and +Y
-- up; this maps that to the arm's -Y (forward when raised) and -Z, with the
-- magazine sitting in the hand.
Constants.WEAPON_GRIPS = {
	Pistol = CFrame.new(0, -0.99, 0.09, 0, 0, 1, -1, 0, 0, 0, -1, 0),
}

-- SHOP (weapon skins bought with coins; per-ability tunables live in Shared/Abilities.luau)
Constants.SHOP_STARTING_COINS = 0
Constants.SHOP_COINS_PER_KILL = 25
Constants.SHOP_COINS_PER_WIN = 100
Constants.SHOP_DEFAULT_PRICE = 200   -- used when a weapon model or ability folder has no Price attribute
Constants.SHOP_DEFAULT_ABILITY = "Dash"  -- owned by everyone; the only ability with behavior

-- PLAYER STATES
Constants.STATE_LOBBY = "Lobby"     -- also used for eliminated players (spectating from the lobby)
Constants.STATE_SAFE = "Safe"       -- alive in the arena

-- ROUND PHASES
Constants.PHASE_LOBBY = "Lobby"
Constants.PHASE_INTERMISSION = "Intermission"
Constants.PHASE_REVEAL = "Reveal"
Constants.PHASE_ROUND = "Round"
Constants.PHASE_END = "End"

-- UI COLORS
Constants.SURVIVOR_COLOR = Color3.fromRGB(27, 180, 32)   -- #1BB420
Constants.TAGGER_COLOR = Color3.fromRGB(255, 56, 60)     -- #FF383C
Constants.WHITE = Color3.fromRGB(255, 255, 255)       -- #FFFFFF

-- SHIELD STATUS (ShieldChanged remote payload)
Constants.SHIELD_UP = "Up"
Constants.SHIELD_COOLDOWN_STATUS = "Cooldown"
Constants.SHIELD_READY = "Ready"

-- END REASONS
Constants.REASON_SURVIVED = "Survived"
Constants.REASON_LAST_STANDING = "LastStanding"
Constants.REASON_ABORTED = "Aborted"

return Constants
