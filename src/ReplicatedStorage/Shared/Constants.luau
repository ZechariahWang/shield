local Constants = {}

-- MATCH (free-for-all deathmatch: killed players return to the lobby and spawn back in)
Constants.MIN_PLAYERS = 2                 -- players plus planned bots needed for a match
Constants.ROUND_TIME = 300                -- seconds a match lasts unless the kill target ends it
Constants.KILL_TARGET = 20                -- the first combatant to this many kills wins
Constants.TOP_BOARD_SIZE = 5              -- names on the in-match top kills board
Constants.TOP_BOARD_SELF_COLOR = Color3.fromRGB(255, 159, 80) -- the ring around the local player's headshot on the top board
Constants.TOP_BOARD_AVATAR_RETRY = 2          -- seconds before the top board looks a missing avatar up again
Constants.RESPAWN_DELAY = 3               -- seconds from a death to the next spawn, players and bots (the kill cam's length)
Constants.MENU_CAMERA_TWEEN_TIME = 0.8       -- seconds the lobby menu camera takes to move between views
Constants.SPAWN_PROTECTION_TIME = 2       -- seconds a fresh spawn cannot be hurt; shooting ends it early
Constants.END_DELAY_TIME = 3 -- post-round freeze: players stay in arena, invincible, abilities/shooting off, before teleport to lobby
Constants.END_TIME = 5

-- BOTS (server-driven combatants cloned from ReplicatedStorage.Assets.Rigs.NPC).
-- They count as players: toward MIN_PLAYERS, on the scoreboard and for the win.
Constants.BOTS_ENABLED = true
Constants.BOT_COUNT = 5                   -- fielded for the whole match while BOTS_ENABLED; each respawns after RESPAWN_DELAY
Constants.BOT_RIG_PATH = { "Assets", "Rigs", "NPC" }
Constants.BOT_WAYPOINT_TIMEOUT = 4        -- seconds before a stuck bot picks a new destination
-- Per-bot skill, rolled uniformly inside each range at spawn (BotBrain._rollSkill).
Constants.BOT_REACTION_TIME = { 0.4, 1.0 }  -- seconds from first sight to the first shot, and from a threat to the shield
Constants.BOT_AIM_ERROR = { 0.05, 0.14 }   -- radians of aim error at BOT_AIM_REFERENCE_DISTANCE on a still, freshly seen target
Constants.BOT_AGGRESSION = { 0.3, 0.9 }    -- 0..1: jump rate, and the chance to re-raise right after a break
Constants.BOT_SHIELD_SENSE = { 0.3, 0.9 }  -- 0..1: chance to answer a threat (an enemy facing the bot with a ready gun) with the shield
-- Aim model: error scales with sqrt(distance / reference), grows with target speed, shrinks the longer the target is tracked.
Constants.BOT_AIM_REFERENCE_DISTANCE = 30
Constants.BOT_AIM_SPEED_PENALTY = 0.5      -- error multiplier per SAFE_WALKSPEED of target speed
Constants.BOT_AIM_SETTLE_RATE = 0.15       -- error divides by 1 + seconds tracked * this
Constants.BOT_FIRE_HESITATION = { 0.2, 1.2 } -- seconds on top of PISTOL_COOLDOWN between shots
-- Engagement movement.
Constants.BOT_ENGAGE_DISTANCE = { 20, 45 } -- studs: closes in above the top, backs off below the bottom, strafes in between
Constants.BOT_STRAFE_SWITCH = { 0.6, 1.6 } -- seconds between strafe direction flips
Constants.BOT_JUMP_INTERVAL = { 2, 6 }     -- seconds between hops while engaged, divided by (0.5 + aggression)
Constants.BOT_THREAT_ANGLE = 12            -- degrees: an enemy looking this close to the bot with a ready gun is a threat
Constants.BOT_THREAT_REROLL = 1.5          -- seconds of sustained threat before the bot rolls its shield sense again
Constants.BOT_TURN_RATE = 10               -- exp-decay rate the bot turns toward its target while engaged
-- Roaming.
Constants.BOT_MEMORY_TIME = 8              -- seconds a lost target's last position is still worth walking to
Constants.BOT_SPRINT_LEG = 30              -- studs: a roam leg longer than this is run at SPRINT_WALKSPEED
Constants.BOT_PERCEPTION_INTERVAL = 0.1    -- seconds between line-of-sight scans
-- Look and name.
Constants.BOT_AVATAR_TRIES = 3             -- random user ids tried for an avatar before falling back to random body colors
Constants.BOT_AVATAR_USER_ID_RANGE = { 100000000, 4000000000 }
Constants.BOT_NAME_ADJECTIVES = { "Shadow", "Blaze", "Frost", "Neon", "Silent", "Crimson", "Turbo", "Pixel", "Rogue", "Storm", "Lunar", "Hyper", "Toxic", "Ghost", "Mystic", "Rapid" }
Constants.BOT_NAME_NOUNS = { "Knight", "Wolf", "Fox", "Ninja", "Gamer", "Viper", "Falcon", "Reaper", "Tiger", "Hawk", "Sniper", "Racer", "Blade", "Dragon", "Pilot", "Rider" }

-- PISTOL
Constants.PISTOL_COOLDOWN = 1.0
Constants.PISTOL_COOLDOWN_TOLERANCE = 0.05 -- server slack for network jitter: the client stamps at send, the server at receive
Constants.PISTOL_RANGE = 200              -- studs
Constants.PISTOL_DAMAGE = 100             -- one shot eliminates
Constants.PISTOL_ORIGIN_TOLERANCE = 8     -- studs; max distance between client-reported origin and the head
Constants.PISTOL_HIT_TOLERANCE = 5        -- studs past the hit part's half-diagonal a client-claimed hit point may sit from the part's server position
Constants.PISTOL_TRACER_SPEED = 600       -- studs per second the tracer segment travels
Constants.PISTOL_TRACER_LENGTH = 6        -- studs
Constants.PISTOL_TRACER_THICKNESS = 0.08  -- studs
Constants.PISTOL_TRACER_COLOR = Color3.fromRGB(255, 240, 160)
Constants.PISTOL_IMPACT_PARTICLES = 10    -- spark burst count where a tracer ends
Constants.PISTOL_IMPACT_FX_TIME = 0.4     -- seconds the impact emitter lives
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
Constants.AIM_FOV = 50                    -- hold the Aim key during combat
Constants.AIM_FOV_TWEEN_TIME = 0.15
Constants.DOUBLE_JUMP_DELAY = 0.15        -- seconds airborne before a second jump is allowed
Constants.SPEED_LINE_COUNT = 36            -- sprint speed lines drawn by SprintEffectController while moving at sprint speed
Constants.SPEED_LINE_MIN_SPEED = 18        -- studs/s of horizontal velocity before the lines show (between walk 16 and sprint 24)
Constants.SPEED_LINE_FADE_TIME = 0.25      -- seconds for the whole field to fade in or out
Constants.SPEED_LINE_LIFETIME = 0.35       -- seconds a streak lives before it respawns at a new angle (each lives 50..100% of this)
Constants.SPEED_LINE_COLOR = Color3.fromRGB(255, 245, 220)
Constants.SPEED_LINE_THICKNESS = 3         -- px
Constants.SPEED_LINE_MIN_LENGTH = 0.2      -- streak length range as fractions of the distance from the screen center to its border; the bright end sits on the border
Constants.SPEED_LINE_MAX_LENGTH = 0.5
Constants.SPEED_LINE_MAX_TRANSPARENCY = 0.35 -- a streak at full intensity is this transparent at its brightest end
Constants.MOVEMENT_STRIDE_LENGTH = 1.6        -- studs of horizontal foot drift before a swing fires
Constants.MOVEMENT_STEP_HEIGHT = 0.55         -- peak vertical arc of a swinging foot
Constants.MOVEMENT_STEP_TIME = 0.18           -- seconds per swing
Constants.MOVEMENT_TURN_RATE = 14             -- exp-decay rate of HRP yaw toward camera yaw
Constants.MOVEMENT_GROUND_RAYCAST_DEPTH = 6   -- max stud distance below the ideal foot pos to look for ground
Constants.MOVEMENT_ANIMATIONS = {             -- blended by MovementController at Movement priority, above the stock Animate walk
	Idle = "rbxassetid://81009869478028",
	Forward = "rbxassetid://107961851755533",
	Backward = "rbxassetid://128010261091905",
	Left = "rbxassetid://84426628902537",
	Right = "rbxassetid://89148728176605",
	Run = "rbxassetid://100362019423807",       -- takes the forward share of the blend while sprinting
}
Constants.DASH_ANIMATIONS = {                 -- one-shot Action priority, picked by MovementBlend.dashTrack from the move direction
	Left = "rbxassetid://87274812929516",
	Right = "rbxassetid://106434084542928",
	Forward = "rbxassetid://104272845733150",
	Backward = "rbxassetid://132347250678738",
}
Constants.SLIDE_ANIMATION = "rbxassetid://88454254966714" -- one-shot Action priority for the slide, stopped when the slide ends
Constants.SLIDE_SPEED = 34                    -- studs per second at the start of a slide, easing down to SAFE_WALKSPEED
Constants.SLIDE_DURATION = 0.7                -- seconds a slide carries the character
Constants.SLIDE_COOLDOWN = 1.0                -- seconds between slides
Constants.JUMP_ANIMATION = "rbxassetid://94756604871926"  -- one-shot Action priority on every Jumping state (double jump included)
Constants.MOVEMENT_ANIM_REFERENCE_SPEED = 16  -- studs per second the walk cycles are authored for; playback speed scales from this
Constants.MOVEMENT_RUN_REFERENCE_SPEED = 24   -- same for the run cycle (the sprint speed)
Constants.MOVEMENT_ANIM_FADE = 0.15           -- seconds the movement blend eases between weights
Constants.MOVEMENT_AIR_FADE = 0.05            -- same, while airborne or on the grapple: the walk and run cut out instead of trailing into the air
Constants.PUSH_MAX_ACCEL = 6000               -- studs/s^2: MaxForce per unit of mass for the dash and grapple constraints. Finite, so a wall stops the character (an unlimited force fights the collision and launches it); under about 2000 a grounded humanoid holds the character in place
Constants.GRAPPLE_RANGE = 400                 -- studs from the root to the anchor
Constants.GRAPPLE_PULL_ACCEL = 150            -- studs/s^2 toward the anchor while attached, on top of the velocity already carried
Constants.GRAPPLE_MAX_SPEED = 110             -- studs per second cap while attached and on release
Constants.GRAPPLE_GRAVITY = 45                -- studs/s^2 downward while attached (the world's is 196.2): the path sags into an arc
Constants.GRAPPLE_SWING_DAMPING = 3           -- exp-decay rate per second of the speed across the rope. Too low and the path misses the anchor and orbits it (0.6 with gravity 60 passes 15 studs under on a 125 stud pull)
Constants.GRAPPLE_STEER_ACCEL = 120           -- studs/s^2 across the rope at full steering input (about 40 studs per second against the damping)
Constants.GRAPPLE_START_HOP = 40              -- studs per second added upward when the grapple starts on the ground, so the character lifts off instead of dragging
Constants.GRAPPLE_RELEASE_LIFT = 45           -- studs per second added upward when the key lets go or the pull arrives
Constants.GRAPPLE_CARRY_DRAG = 0.4            -- exp-decay rate per second of the horizontal speed carried after a release, until landing or SPRINT_WALKSPEED
Constants.GRAPPLE_CARRY_STEER_ACCEL = 40      -- studs/s^2 the movement input bends the carried velocity by
Constants.GRAPPLE_ARRIVE_DISTANCE = 6         -- studs from the anchor at which the rope lets go
Constants.GRAPPLE_MAX_TIME = 20              -- seconds before a rope lets go on its own
Constants.GRAPPLE_STALL_SPEED = 4             -- studs per second: slower than this for GRAPPLE_STALL_TIME means something is in the way
Constants.GRAPPLE_STALL_TIME = 0.3
Constants.GRAPPLE_COOLDOWN = 0.1              -- seconds from a release to the next grapple
Constants.GRAPPLE_COOLDOWN_TOLERANCE = 0.2    -- server slack: cooldown seconds and range studs (the client stamps at send)
Constants.GRAPPLE_ROPE_WIDTH = 0.15           -- studs
Constants.GRAPPLE_ROPE_COLOR = Color3.fromRGB(235, 235, 235)
Constants.LEAN_MAX_ANGLE = 8                  -- degrees the torso tips toward the movement direction at full input
Constants.LEAN_RATE = 10                      -- exp-decay rate of the lean toward its target (server Heartbeat)

-- RAGDOLL (a corpse clone left where a combatant was eliminated; only during Round, cleared with the map)
Constants.RAGDOLL_LIFETIME = 15           -- seconds before a corpse is removed
Constants.RAGDOLL_IMPULSE = 30            -- studs per second added away from the killer
Constants.RAGDOLL_JOINT_LIMIT = 45        -- degrees each ball socket may swing
Constants.RAGDOLL_DENSITY = 0.3           -- light enough that a corpse cannot shove a living player

-- KILL CAM (victim's camera swings to face the killer after elimination)
Constants.KILL_CAM_TIME = 3
Constants.KILL_CAM_DISTANCE = 7
Constants.KILL_CAM_HEIGHT = 2
Constants.KILL_CAM_TWEEN_TIME = 0.6

-- THIRD-PERSON WEAPON (welded to every player by RoundManager)
Constants.VIEWMODEL_DEFAULT_WEAPON = "Pistol"  -- fallback when a save names a weapon the catalog no longer has

-- SHOP (items are the modules under ReplicatedStorage.Items; prices, stats and per-ability tunables live there)
Constants.SHOP_STARTING_COINS = 0
Constants.SHOP_COINS_PER_KILL = 25
Constants.SHOP_COINS_PER_WIN = 100
Constants.STORE_DATASTORE_NAME = "PlayerData"
Constants.STORE_LOAD_RETRIES = 3
Constants.STORE_RETRY_DELAY = 1         -- seconds between failed load attempts
Constants.STORE_AUTOSAVE_INTERVAL = 120 -- seconds between background saves of changed wallets

-- SETTINGS (per player, saved inside the Store record; edited from the lobby on PC)
Constants.DEFAULT_KEYBINDS = {           -- Enum.KeyCode names or MouseButton1/2/3
	Shoot = "MouseButton1",
	Shield = "Q",
	Dash = "E",
	Sprint = "LeftShift",
	Aim = "Four",
	Slide = "C",
	Grapple = "MouseButton2",             -- held: the rope lives while the key is down
}
Constants.SENSITIVITY_DEFAULT = 1        -- UserInputService.MouseDeltaSensitivity while aiming: scales the mouse delta on top of the player's Roblox sensitivity
Constants.SENSITIVITY_MIN = 0.1
Constants.SENSITIVITY_MAX = 4
Constants.SENSITIVITY_STEP = 0.1

-- PLAYER STATES
Constants.STATE_LOBBY = "Lobby"     -- in the lobby: between matches, before the first spawn, and after every death
Constants.STATE_SAFE = "Safe"       -- alive in the arena
Constants.IN_ROUND_TAG = "InRound"  -- CollectionService tag on every Safe Player and every live bot Model

-- ROUND PHASES
Constants.PHASE_LOBBY = "Lobby"     -- waiting for enough players
Constants.PHASE_ROUND = "Round"     -- the match
Constants.PHASE_END = "End"         -- arena freeze, then the results in the lobby

-- UI COLORS
Constants.SURVIVOR_COLOR = Color3.fromRGB(27, 180, 32)   -- #1BB420
Constants.TAGGER_COLOR = Color3.fromRGB(255, 56, 60)     -- #FF383C
Constants.WHITE = Color3.fromRGB(255, 255, 255)       -- #FFFFFF

-- MINIMAP (the Game.Minimap frame authored in Studio; Round phase only)
Constants.MINIMAP_DOT_SIZE = 6                        -- px
Constants.MINIMAP_RANGE = 100                          -- studs from the local player to the minimap's edge
Constants.MINIMAP_SHOT_FLASH = 0.35                   -- seconds a dot stays yellow after that combatant fires
Constants.MINIMAP_ENEMY_COLOR = Constants.TAGGER_COLOR
Constants.MINIMAP_SHIELD_COLOR = Constants.SHIELD_COLOR
Constants.MINIMAP_SHOOTING_COLOR = Color3.fromRGB(255, 220, 60)
Constants.MINIMAP_SELF_COLOR = Constants.WHITE

-- SHIELD STATUS (ShieldChanged remote payload)
Constants.SHIELD_UP = "Up"
Constants.SHIELD_COOLDOWN_STATUS = "Cooldown"
Constants.SHIELD_READY = "Ready"

-- END REASONS
Constants.REASON_KILL_TARGET = "KillTarget"
Constants.REASON_TIME_UP = "TimeUp"
Constants.REASON_ABORTED = "Aborted"

return Constants
