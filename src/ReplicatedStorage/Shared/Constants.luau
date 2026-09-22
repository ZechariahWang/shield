local Constants = {}

-- ROUND
Constants.MIN_PLAYERS = 2
Constants.INTERMISSION_TIME = 10
Constants.REVEAL_TIME = 10 -- pre-round positioning grace. No damage, no abilities.
Constants.ROUND_TIME = 90
Constants.END_DELAY_TIME = 3 -- post-round freeze: players stay in arena, invincible, abilities/shooting off, before teleport to lobby
Constants.END_TIME = 5

-- PISTOL
Constants.PISTOL_COOLDOWN = 1.0
Constants.PISTOL_COOLDOWN_TOLERANCE = 0.05 -- server slack for network jitter: the client stamps at send, the server at receive
Constants.PISTOL_RANGE = 200              -- studs
Constants.PISTOL_DAMAGE = 100             -- one shot eliminates
Constants.PISTOL_ORIGIN_TOLERANCE = 8     -- studs; max distance between client-reported origin and the head
Constants.PISTOL_TRACER_LIFETIME = 0.08   -- seconds the tracer part stays in Workspace
Constants.PISTOL_SHOT_SOUND = "rbxassetid://127604219525464"  -- played at the shooter's head, server side
Constants.SHIELD_BLOCK_SOUND = "rbxassetid://9116669121"     -- played at the victim's head when a shield absorbs a shot
Constants.SOUND_CLEANUP_TIME = 3          -- seconds before a one-shot Sound instance is removed

-- SHIELD
Constants.SHIELD_DURATIONS = { 1.0, 0.5, 0.25 } -- active seconds; index = 1 + breaks in the current chain (clamped)
Constants.SHIELD_COOLDOWN = 3.0           -- after natural expiry or manual lower. A break has no cooldown.
Constants.SHIELD_CHAIN_RESET = 5.0        -- seconds since the last break before the chain resets to full duration
Constants.SHIELD_WALKSPEED = 12           -- while the shield is up

-- MOVEMENT
Constants.SAFE_WALKSPEED = 16
Constants.MOVEMENT_STRIDE_LENGTH = 1.6        -- studs of horizontal foot drift before a swing fires
Constants.MOVEMENT_STEP_HEIGHT = 0.55         -- peak vertical arc of a swinging foot
Constants.MOVEMENT_STEP_TIME = 0.18           -- seconds per swing
Constants.MOVEMENT_TURN_RATE = 14             -- exp-decay rate of HRP yaw toward camera yaw
Constants.MOVEMENT_GROUND_RAYCAST_DEPTH = 6   -- max stud distance below the ideal foot pos to look for ground

-- COMBAT CAMERA (shoulder view while combat mode is active)
Constants.CAMERA_SHOULDER_OFFSET = Vector3.new(1.75, 0.5, 0)
Constants.CAMERA_COMBAT_FOV = 80
Constants.CAMERA_MIN_ZOOM = 6
Constants.CAMERA_MAX_ZOOM = 12

-- KILL CAM (victim's camera swings to face the killer after elimination)
Constants.KILL_CAM_TIME = 3
Constants.KILL_CAM_DISTANCE = 7
Constants.KILL_CAM_HEIGHT = 2
Constants.KILL_CAM_TWEEN_TIME = 0.6

-- THIRD-PERSON WEAPON (welded to every player by RoundManager)
Constants.VIEWMODEL_DEFAULT_WEAPON = "M4A1"

-- DASH
Constants.DASH_COOLDOWN = 3
Constants.DASH_DURATION = 0.2
Constants.DASH_VELOCITY = 60

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
