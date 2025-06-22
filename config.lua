--todo 
    -- minigame for hacking perms
Config = {}

Config.Framework = "esx"  -- "qb" for QBCore, "esx" for ESX, "none" for standalone

Config.ItemName = "jammer"              -- Item name in inventory
Config.MaxJammersPerPlayer = 5          -- Maximum jammers a player can place
Config.JammerHealth = 100               -- Health of placed jammers
Config.UseAsUsableItem = true           -- Make jammer a usable item (right-click to use)

-- ================================================================
-- PLACEMENT SETTINGS
-- ================================================================
Config.AllowGroundPlacement = true      -- Allow placing jammers on the ground
Config.AllowWallPlacement = false       -- Disable wall placement - only ground placement
Config.AllowAnyoneToDestroy = true      -- Allow anyone to destroy jammers
Config.OnlyOwnerGetsItemBack = true     -- Only original owner gets item back when destroying
Config.CheckForCollisions = true        -- Check for collisions before placing

-- Placement Offset Settings
Config.PlacementOffset = {
    forward = 1.0,                       -- Distance forward from player (meters) - increased for better placement
    up = 0.1,                           -- Height offset from ground (meters) - slight elevation
    right = 0.0                         -- Offset to the right of player (meters)
}

-- Collision Detection Settings
Config.CollisionDetection = {
    enabled = true,                      -- Enable collision detection
    radius = 1.0                        -- Collision detection radius (meters)
}

-- Weapon Destruction Settings
Config.WeaponDestruction = {
    enabled = true,                      -- Allow jammers to be destroyed with weapons
    permanentImmune = false,             -- Permanent jammers cannot be destroyed with weapons
    permanentRespawnDelay = 5,           -- Delay in seconds before permanent jammers can be damaged again
    damageMultiplier = 1.0,              -- Damage multiplier for weapon damage (1.0 = normal damage)
    baseDamage = 25,                     -- Base damage amount when specific damage can't be calculated
    checkInterval = 100,                 -- How often to check for damage (milliseconds)
    allowedWeapons = {                   -- Leave empty {} to allow all weapons
        -- Examples: `weapon_pistol`, `weapon_assaultrifle`, `weapon_rpg`, etc.
        -- If this table is not empty, only these weapons can damage jammers
    }
}

-- Placement Animations
Config.PlacementAnimations = {
    ground = {
        enabled = true,                     -- Enable animation for ground placement
        dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@",
        name = "machinic_loop_mechandplayer",                      -- Simple planting/placing animation without weapons
        duration = 3000,                    -- Animation duration (milliseconds)
        flag = 1                           -- Animation flag
    }
}

-- ================================================================
-- PERMANENT JAMMERS
-- ================================================================

Config.PermanentJammers = {    {        
        coords = {x = -2431.5518, y = 3269.3284, z = 40.8615},  
        heading = 58.7023,
        label = "MilitaryBase_1",  
        model = "sm_prop_smug_jammer",                 -- Custom model for this jammer
        range = 600.0,                                -- 100m range for high-security military base
        noGoZone = 500, 
        ignoredJobs = {"police", "jsoc"}               -- Jobs that can ignore this jammer
    },
    {
        coords = {x = -1837.0573, y = 3102.9004, z = 39.7955}, 
        heading = 59.0,
        label = "MilitaryBase_2",
        model = "sm_prop_smug_jammer",                -- Different model
        range = 600.0,                                -- 100m range for high-security military base
        noGoZone = 500,  
        ignoredJobs = {"police", "jsoc"}               -- Jobs that can ignore this jammer
    },
    {
        coords = {x = -3212.5703, y = 3889.5361, z = 5.0773}, 
        heading = 268.8678,
        label = "AircraftCarrier_1",  
        model = "gr_prop_gr_rsply_crate04a",          -- Different model
        range = 400.0,                                -- 120m range for aircraft carrier (largest range)
        noGoZone = 0.75,                               -- 30% of range (larger no-go zone) = 36m
        ignoredJobs = {"police", "jsoc"}       -- Jobs that can ignore this jammer
    },
    {
        coords = {x = -989.4125, y = -3017.2617, z = 47.7317},
        heading = 148.3204,
        label = "Airport_1",
        model = "sm_prop_smug_jammer",                -- Different model
        range = 400.0,                                 -- 60m range for civilian airport
        noGoZone = 0.80,                               -- 25% of range = 15m no-go zone
        ignoredJobs = {"police", "airport"}            -- Jobs that can ignore this jammer
    },    {
        coords = {x = -1762.3580, y = -2816.7952, z = 12.9443},    -- Sandy Shores Airfield
        heading =  147.4484,
        label = "Airport_2",
        model = "sm_prop_smug_jammer",                -- Another model option
        range = 500.0,                                 -- 45m range for smaller airfield
        noGoZone = 0.80,                               -- 10 meter absolute radius
        ignoredJobs = {"police", "airport"}            -- Jobs that can ignore this jammer
    }



    -- Add more permanent jammers here as needed
    -- Available models: prop_satdish_2_l, prop_satdish_s_05, prop_cs_tablet_01, prop_laptop_01a
    -- {
    --     coords = vector3(x, y, z),
    --     heading = 0.0,
    --     label = "Custom Jammer Name",
    --     model = "prop_cs_tablet_01"
    -- }
}

-- ================================================================
-- VISUAL SETTINGS
-- ================================================================
Config.JammerModel = "m23_1_prop_m31_jammer_01a"    -- Model for jammer prop
Config.JammerRange = 30.0                   -- Range for player-placed jammers (meters)
Config.PermanentJammerRange = 75.0          -- Default range for permanent jammers (meters)
Config.PlacementRange = 3.0                 -- Maximum distance to place jammer
Config.InteractionRange = 2.0               -- Maximum distance to interact with jammer

-- No-Go Zone Settings
Config.DefaultNoGoZonePercentage = 0.2      -- Default no-go zone as 20% of jammer range
                                            -- This is used when a jammer doesn't specify its own noGoZone value

-- Visual Effects
Config.ShowPlacementPreview = false         -- Disable preview when placing
Config.PreviewAlpha = 150                   -- Alpha value for preview (0-255)
Config.UseMarkers = false                   -- Show markers at jammer locations (disabled as requested)

-- ================================================================
-- DESTRUCTION EFFECTS
-- ================================================================
Config.DestructionEffects = {
    enabled = true,                          -- Enable destruction effects
    playSound = false,                       -- Disable default sound, as explosions have their own
    useExplosion = true,                     -- Use explosion effect
    explosionType = 73,                      -- Explosion type (40 as requested)
    explosionScale = 0.75,                   -- Explosion scale
    
}
Config.UseMarkersOnPermanent = false       -- Show markers on permanent jammers (disabled as requested)
Config.MarkerType = 1                       -- Marker type
Config.MarkerSize = {x = 1.0, y = 1.0, z = 1.0} -- Marker size
Config.MarkerColor = {r = 255, g = 0, b = 0, a = 100} -- Marker color (red)

-- Beeping Sound Settings
Config.BeepingSound = {
    enabled = true,                         -- Enable beeping sound near jammers
    range = 10.0,                          -- Range in meters to hear beeping (10m as requested)
    interval = 2000,                       -- Time between beeps in milliseconds (2 seconds)    
    sound = {
        name = "SELECT",                  -- Sound name (subtle warning beep)
        set = "HUD_MINI_GAME_SOUNDSET"    -- Sound set
        
    },
    volumeByDistance = true,               -- Lower volume when further away
    onlyForOwner = false,                  -- If true, only jammer owner hears beeps
    permanentJammers = true                -- Include permanent jammers in beeping
}

-- Interaction Settings
Config.PickupConfirmation = {
    enabled = true,                         -- Require confirmation to pick up jammers
    holdTime = 2000,                       -- Time to hold button (milliseconds)
    key = 38,                              -- Key to hold (38 = E)
    showProgress = true                    -- Show progress bar while holding
}

-- ================================================================
-- DEBUG SETTINGS
-- ================================================================
Config.Debug = {
    enabled = true,                        -- Enable debug console prints (temporarily enabled for testing)
    beepingDebug = false,                  -- Enable beeping system debug prints
    coordinateDebug = true                 -- Enable coordinate validation debug prints
}

-- ================================================================
-- CLEANUP SETTINGS
-- ================================================================
Config.CleanupSettings = {
    removeOnDisconnect = false,            -- Keep jammers when players disconnect (as requested)
    cleanupOrphanedOnStart = true,         -- Clean orphaned props on script restart
    autoCleanupInterval = 0,               -- Auto cleanup interval in minutes (0 = disabled)
    maxJammersBeforeCleanup = 100          -- Max total jammers before forcing cleanup
}

-- ================================================================
-- NOTIFICATIONS
-- ================================================================
Config.Notifications = {
    placed = "Jammer placed successfully",
    destroyed = "Jammer destroyed",
    destroyedWithItem = "Jammer picked up successfully",
    destroyedByOther = "Jammer destroyed by someone else",
    destroyedByWeapon = "Jammer destroyed by weapon damage",
    maxReached = "Maximum jammers limit reached",
    noItem = "You don't have a jammer device",
    noPermission = "You don't have permission to do this",
    tooFar = "Too far to place jammer",
    blocked = "Location is blocked",
    usableItemInfo = "~g~Jammer ready!~s~ Use the item or press ~INPUT_CONTEXT~ to place, ~INPUT_FRONTEND_CANCEL~ to cancel",
    pickupProgress = "Hold ~INPUT_CONTEXT~ to pick up jammer...",
    destroyProgress = "Hold ~INPUT_CONTEXT~ to destroy jammer...",
    jammerDamaged = "Jammer taking damage!"
}