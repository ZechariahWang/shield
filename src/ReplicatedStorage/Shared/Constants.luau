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
Constants.SHIELD_RAISE_SOUND = "rbxassetid://102387902167220"  -- all shield sounds play at the owner's head, server side
Constants.SHIELD_LOWER_SOUND = "rbxassetid://130860293177595"  -- natural expiry and manual lower
Constants.SHIELD_BREAK_SOUND = "rbxassetid://132492701741331"  -- a shot landed on the raised shield

-- MOVEMENT
Constants.SAFE_WALKSPEED = 16
Constants.MOVEMENT_STRIDE_LENGTH = 1.6        -- studs of horizontal foot drift before a swing fires
Constants.MOVEMENT_STEP_HEIGHT = 0.55         -- peak vertical arc of a swinging foot
Constants.MOVEMENT_STEP_TIME = 0.18           -- seconds per swing
Constants.MOVEMENT_TURN_RATE = 14             -- exp-decay rate of HRP yaw toward camera yaw
Constants.MOVEMENT_GROUND_RAYCAST_DEPTH = 6   -- max stud distance below the ideal foot pos to look for ground

-- COMBAT CAMERA (scriptable shoulder view while combat mode is active)
Constants.CAMERA_SHOULDER_OFFSET = Vector3.new(1.75, 0.5, 0) -- camera space: right, up, back
Constants.CAMERA_FOCUS_HEIGHT = 1.5           -- studs above the root part the camera orbits
Constants.CAMERA_COMBAT_FOV = 80
Constants.CAMERA_MIN_ZOOM = 6
Constants.CAMERA_MAX_ZOOM = 12
Constants.CAMERA_DEFAULT_ZOOM = 8
Constants.CAMERA_ZOOM_STEP = 1                -- studs per mouse wheel notch
Constants.CAMERA_SENSITIVITY_X = 0.0065       -- radians per pixel, multiplied by the user's mouse sensitivity setting (matches the stock camera)
Constants.CAMERA_SENSITIVITY_Y = 0.005
Constants.CAMERA_PITCH_MIN = -60              -- degrees
Constants.CAMERA_PITCH_MAX = 75
Constants.CAMERA_ROTATION_SMOOTHING = 30      -- exp-decay rates: higher is snappier
Constants.CAMERA_FOLLOW_SMOOTHING = 14
Constants.CAMERA_ZOOM_SMOOTHING = 6           -- easing back out after an obstacle
Constants.CAMERA_OCCLUSION_IN_RATE = 40       -- pulling in toward an obstacle
Constants.CAMERA_FOV_SMOOTHING = 8
Constants.CAMERA_OCCLUSION_PADDING = 0.5      -- studs kept between the camera and the wall behind it
Constants.CAMERA_OCCLUSION_MIN_DISTANCE = 1

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
