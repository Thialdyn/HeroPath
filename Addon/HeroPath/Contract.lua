-- Hero’sPath collector contract.
-- Product metadata, schema, enums, thresholds and policies.
local ADDON_NAME, ns = ...

local C = {
    PRODUCT = "Hero’sPath",
    AUTHOR = "Darwyn",
    VERSION = "1.0.0",
    PUBLIC_API_VERSION = 1,
    SAVED_VARIABLES_SCHEMA = 1,
    RECOVERY_SCHEMA_VERSION = 1,
    SUPPORTED_INTERFACES = {120100, 120105, 16001},

    Limits = {
        MAX_MOVEMENT_MODE = 5,
        MAX_ORDER = 9007199254740000,
        MAX_TRANSITION_ID = 9007199254740000,
        MAX_CONTEXT_TEXT = 160,
        MAX_PLAYED_SECONDS = 100 * 366 * 24 * 3600,
        STORED_LAST_PLAYED_AHEAD_TOLERANCE = 6 * 3600,
        MAX_WORLD_COORD_ABS = 10000000,
        MAX_WORLD_ID = 2147483647,
    },

    Sampling = {
        SAMPLE_SECONDS = 0.25,
        SAMPLE_FAST_SECONDS = 0.25, -- export metadata compatibility
        SAMPLE_MOVING_SECONDS = 0.25,
        SAMPLE_IDLE_SECONDS = 0.25,
        PLAYED_BACKSTEP_TOLERANCE = 0.050,
        PLAYED_FORWARD_SLACK_SECONDS = 5.0,
        POSITION_MISSING_CONFIRM_SAMPLES = 2,
        STATE_CHANGE_CONFIRM_SAMPLES = 2,
        MIN_MOVE_YARDS = 1.00,
        -- World position is still observed at 4 Hz. These values only decide which
        -- ordinary observations are persisted; turns, mode changes and time
        -- keyframes can force a point earlier. Straight travel stays light while
        -- tight local geometry remains faithful.
        STORE_DISTANCE_YARDS = {
            [0] = 4.0,  -- foot
            [1] = 7.0,  -- mounted
            [2] = 3.0,  -- swimming
            [3] = 20.0, -- flight-path taxi
            [4] = 4.0,  -- ghost
            [5] = 7.0,  -- unknown/special continuous movement
        },
        STORE_MAX_INTERVAL_SECONDS = {
            [0] = 1.50, [1] = 1.50, [2] = 1.00,
            [3] = 2.00, [4] = 1.50, [5] = 1.50,
        },
        CORNER_MIN_LEG_YARDS = 0.45,
        CORNER_STORE_MIN_YARDS = 1.00,
        CORNER_MIN_DEVIATION_YARDS = 0.18,
        CORNER_COS_MAX = 0.9781476007338057, -- >= 12 degrees
        SHARP_CORNER_COS_MAX = 0.8660254037844386, -- >= 30 degrees
        RAW_IDLE_YARDS = 0.35,
        IDLE_HOLD_SECONDS = 3,
        SAMPLE_GAP_SECONDS = 1.25,
        RESUME_CONTINUITY_YARDS = 45,
        POSITION_RETRY_SECONDS = 0.15,
        WORLD_EVENT_RETRIES = 8,
        TELEPORT_MARGIN_YARDS = 12,
        TELEPORT_MIN_GENERIC_YARDS = 80,
        SEMANTIC_TELEPORT_MIN_YARDS = 8,
        SHORT_RELOCATION_MIN_YARDS = 12,
        SHORT_RELOCATION_MARGIN_YARDS = 6,
        RESUME_PRIME_CONFIRM_SAMPLES = 2,
        RESUME_PRIME_STABLE_YARDS = 5,
        RESUME_PRIME_MOTION_SAMPLES = 3,
        WATCHDOG_SECONDS = 2,
        WATCHDOG_STALE_SECONDS = 2,
        SPECIAL_MOVEMENT_SPEED_YARDS_PER_SECOND = 16,
        INTERPOLATION_TIME_EPSILON_SECONDS = 0.000001,
        ANCHOR_TIME_EPSILON_SECONDS = 0.002,
        ANCHOR_POSITION_EPSILON_YARDS = 0.25,
        DISCONTINUITY_SETTLE_YARDS = 3.0,
        CONTINUOUS_HINT_CONSUME_YARDS = 4.0,
        MOTION_TIME_EPSILON_SECONDS = 0.001,
        SUSTAINED_MOTION_MIN_SECOND_LEG_YARDS = 4,
        SUSTAINED_DISTANCE_RATIO_MIN = 0.20,
        SUSTAINED_DISTANCE_RATIO_MAX = 5,
        SUSTAINED_DIRECTION_COS_MIN = 0.35,
        SUSTAINED_SPEED_RATIO_MIN = 0.15,
        SUSTAINED_SPEED_RATIO_MAX = 6,
        MAX_SPEED_YARDS_PER_SECOND = {
            [0] = 45, [1] = 65, [2] = 35, [3] = math.huge, [4] = 45, [5] = 120,
        },
    },

    Compression = {
        WORK_PER_SLICE = 64,
        SLICE_SECONDS = 0.01,
        RDP_EPSILON_YARDS = 3,
        RDP_KEYFRAME_SECONDS = 20,
        PRESERVE_CURVATURE = true,
        RETRY_MAX_FAILURES = 3,
        RETRY_SECONDS = 1,
        RAW_CHUNK_POINTS = 800,
        RAW_TAIL_TRIGGER = 1000,
    },

    Integration = {
        PLAYED_REQUEST_COOLDOWN = 1,
        PLAYED_RETRY_DELAYS = {2, 5, 10, 30},
        SOURCE_AGREE_YARDS = 6,
        CALIBRATION_REQUIRED_DECISIVE = 5,
        CALIBRATION_WINNER_MIN = 4,
        CALIBRATION_VOTE_MARGIN = 3,
        ORIENTATION_CONTRADICTION_RESET = 3,
        DEEPRUN_TRAM_INSTANCE_ID = 369,
    },

    Compatibility = {
        FUTURE_SCHEMA_READ_ONLY = true,
        WRITE_ROOT_SCHEMA = true,
    },

    FeatureFlags = {
        ENABLE_COLLECTOR_WATCHDOG = true,
        ENABLE_RESUME_PRIME = true,
        REQUIRE_WORLD_ENTRY_BEFORE_SAMPLING = true,
    },

    Event = { DEATH = 0, INSTANCE = 1, STATE = 2 },
    State = {
        RELEASE = 1, RESURRECT = 2, TAXI_START = 3, TAXI_END = 4,
        GAP_START = 5, GAP_END = 6, WORLD_TRANSITION = 7, TELEPORT = 8,
        HEARTH = 9, TRAM_START = 10, TRAM_END = 11, BOAT = 12,
        ZEPPELIN = 13, TRANSPORT_UNKNOWN = 14,
    },
    Break = {
        NONE = 0, INITIAL = 1, DEATH = 2, TELEPORT = 3, WORLD = 4,
        UNAVAILABLE = 5, INSTANCE_EXIT = 6, RESUME = 7, UNCERTAIN = 8,
    },
    DeathAccuracy = { EXACT = 1, LAST_KNOWN = 2, INSTANCE_ANCHOR = 3, UNKNOWN = 4 },
    Semantic = { HEARTH = 1, TELEPORT_SPELL = 2 },

    Transition = {
        Cause = {
            UNKNOWN = 0,
            HEARTH = 1,
            TELEPORT_SPELL = 2,
            WORLD_BOUNDARY = 3,
            OBSERVED_TELEPORT = 4,
        },
        Confidence = {
            OBSERVED = 1,
            SEMANTIC_CONFIRMED = 2,
        },
    },

    Context = {
        SESSION = 1,
        STATE = 2,
        DEATH = 3,
        INSTANCE_ENTER = 4,
        INSTANCE_EXIT = 5,
        TRANSITION_DEPARTURE = 6,
        TRANSITION_ARRIVAL = 7,
    },

    SemanticHints = {
        DIRECT_SECONDS = 3,
        DESTINATION_SECONDS = 5,
        CONTINUOUS_TTL_SECONDS = 2,
        CONTINUOUS_MAX_YARDS = 45,
        HEARTHSTONE_SPELL_IDS = { [8690] = true, [556] = true }, -- Hearthstone, Astral Recall
        TELEPORT_SPELL_IDS = {
            [1953] = "short",
            [3561] = true, [3562] = true, [3563] = true, [3565] = true, [3566] = true, [3567] = true,
            [1297659] = true, -- Teleport: Dalaran (Forever)
        },
        CONTINUOUS_MOVEMENT_SPELL_IDS = {
            [100] = true, [6178] = true, [11578] = true,
            [20252] = true, [20616] = true, [20617] = true,
            [1238122] = true, [16979] = true,
        },
    },
}

ns.Contract = C
