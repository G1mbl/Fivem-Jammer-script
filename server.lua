-- ================================================================
-- SIMPLIFIED JAMMER SYSTEM - SERVER SIDE
-- ================================================================
-- This server-side script manages jammer placement and synchronization
-- with permanent jammers support from config. No database required.
-- ================================================================
--
-- FEATURES:
-- - Simple jammer placement mechanics
-- - Permanent jammers from config with custom models
-- - Framework-agnostic player management (ESX/QBCore)
-- - Real-time synchronization across all clients
-- - No job-based permissions (anyone can destroy, only owner gets item back)
-- - Inventory integration for jammer items
-- ================================================================

local QBCore = nil
local ESX = nil
local jammers = {}              -- Server-side jammer storage
local jammerIdCounter = 1       -- Auto-incrementing ID for new jammers
local permanentJammers = {}     -- Permanent jammers from config
local jammerCooldowns = {}      -- Cooldown tracking for permanent jammers
local lastDamageProcessTime = 0 -- Global damage processing throttle

-- ================================================================
-- DEBUG HELPER FUNCTION
-- ================================================================
local function DebugPrint(message, debugType)
    debugType = debugType or "general"
    
    if Config.Debug.enabled then
        if debugType == "general" or 
           (debugType == "beeping" and Config.Debug.beepingDebug) or
           (debugType == "coordinates" and Config.Debug.coordinateDebug) then
            print(message)
        end
    end
end

-- ================================================================
-- FRAMEWORK INITIALIZATION
-- ================================================================
if Config.Framework == "qb" then
    QBCore = exports['qb-core']:GetCoreObject()
elseif Config.Framework == "esx" then
    ESX = exports["es_extended"]:getSharedObject()
end

-- ================================================================
-- USABLE ITEM REGISTRATION
-- ================================================================
-- Register jammer as a usable item for both frameworks
-- ================================================================
Citizen.CreateThread(function()
    -- Only register usable item if enabled in config
    if not Config.UseAsUsableItem then
        DebugPrint('[Jammer] Usable item disabled in config')
        return
    end
    
    -- Wait a bit for frameworks to fully load
    Citizen.Wait(1000)
      if Config.Framework == "qb" and QBCore then
        -- Register usable item for QBCore
        QBCore.Functions.CreateUseableItem(Config.ItemName, function(source, item)
            TriggerClientEvent('jammer:use', source)
        end)
        DebugPrint('[Jammer] Registered ' .. Config.ItemName .. ' as usable item for QBCore')
        
    elseif Config.Framework == "esx" and ESX then
        -- Register usable item for ESX
        ESX.RegisterUsableItem(Config.ItemName, function(source)
            TriggerClientEvent('jammer:use', source)
        end)
        DebugPrint('[Jammer] Registered ' .. Config.ItemName .. ' as usable item for ESX')
    end
end)

-- ================================================================
-- PLAYER UTILITY FUNCTIONS
-- ================================================================
local function GetPlayerIdentifier(source)
    if Config.Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(source)
        return Player and Player.PlayerData.citizenid or nil
    elseif Config.Framework == "esx" then
        local xPlayer = ESX.GetPlayerFromId(source)
        return xPlayer and xPlayer.identifier or nil
    end
    return tostring(source) -- Fallback to source ID if framework fails
end

-- ================================================================
-- INVENTORY MANAGEMENT FUNCTIONS
-- ================================================================
local function HasItem(source, item)
    if Config.Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            local hasItem = Player.Functions.GetItemByName(item)
            return hasItem and hasItem.amount > 0
        end
    elseif Config.Framework == "esx" then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local item = xPlayer.getInventoryItem(item)
            return item and item.count > 0
        end
    end
    return false
end

local function RemoveItem(source, item, amount)
    amount = amount or 1
    if Config.Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            Player.Functions.RemoveItem(item, amount)
        end
    elseif Config.Framework == "esx" then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeInventoryItem(item, amount)
        end
    end
end

local function AddItem(source, item, amount)
    amount = amount or 1
    if Config.Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            Player.Functions.AddItem(item, amount)
        end
    elseif Config.Framework == "esx" then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addInventoryItem(item, amount)
        end
    end
end

-- ================================================================
-- PERMISSION CHECKING FUNCTIONS
-- ================================================================
local function CanPlayerUseJammer(source)
    return true -- Anyone can use jammers now
end

local function CanPlayerDestroy(source)
    return Config.AllowAnyoneToDestroy or true -- Always allow destruction
end

-- ================================================================
-- COORDINATE VALIDATION
-- ================================================================
local function ValidateCoordinates(coords)
    -- Debug: Print incoming coords for debugging
    DebugPrint('[Jammer] DEBUG: Validating coordinates - Type: ' .. type(coords), "coordinates")
    if type(coords) == "table" then
        DebugPrint('[Jammer] DEBUG: coords.x=' .. tostring(coords.x) .. ', coords.y=' .. tostring(coords.y) .. ', coords.z=' .. tostring(coords.z), "coordinates")
    end
    
    -- Handle vector3 type (might come as userdata)
    if type(coords) == "userdata" then
        -- Try to convert userdata to table
        local x, y, z = coords.x or coords[1], coords.y or coords[2], coords.z or coords[3]
        if x and y and z then
            coords = {x = x, y = y, z = z}
            DebugPrint('[Jammer] DEBUG: Converted userdata to table: x=' .. x .. ', y=' .. y .. ', z=' .. z, "coordinates")
        else
            DebugPrint('[Jammer] Invalid coords userdata structure', "coordinates")
            return false
        end
    end
    
    -- Check if coords is a valid table/vector
    if type(coords) ~= "table" or not coords.x or not coords.y or not coords.z then
        DebugPrint('[Jammer] Invalid coords structure - Type: ' .. type(coords) .. ', x=' .. tostring(coords.x) .. ', y=' .. tostring(coords.y) .. ', z=' .. tostring(coords.z), "coordinates")
        return false
    end
    
    -- Convert to numbers if they're strings
    coords.x = tonumber(coords.x)
    coords.y = tonumber(coords.y)
    coords.z = tonumber(coords.z)
    
    if not coords.x or not coords.y or not coords.z then
        DebugPrint('[Jammer] Could not convert coordinates to numbers', "coordinates")
        return false
    end
    
    -- Check for reasonable coordinate values (prevent teleportation exploits)
    -- Made bounds more generous for debugging
    if math.abs(coords.x) > 20000 or math.abs(coords.y) > 20000 or 
       coords.z < -500 or coords.z > 2000 then
        DebugPrint('[Jammer] Coords out of bounds: x=' .. coords.x .. ', y=' .. coords.y .. ', z=' .. coords.z, "coordinates")
        return false
    end
    
    -- Check for NaN or infinite values
    if coords.x ~= coords.x or coords.y ~= coords.y or coords.z ~= coords.z or
       coords.x == math.huge or coords.y == math.huge or coords.z == math.huge or
       coords.x == -math.huge or coords.y == -math.huge or coords.z == -math.huge then
        DebugPrint('[Jammer] Invalid coordinate values (NaN or infinite)', "coordinates")
        return false
    end
    
    DebugPrint('[Jammer] Coordinates validated successfully: x=' .. coords.x .. ', y=' .. coords.y .. ', z=' .. coords.z, "coordinates")
    return true
end

-- ================================================================
-- JAMMER MANAGEMENT
-- ================================================================
local function SyncJammers()
    -- Add yield to prevent deadloop
    Citizen.Wait(0)
    
    -- Combine player-placed jammers with permanent jammers
    local allJammers = {}
    
    -- Add player-placed jammers
    for id, jammer in pairs(jammers) do
        allJammers[id] = jammer
    end
    
    -- Add permanent jammers
    for id, jammer in pairs(permanentJammers) do
        allJammers[id] = jammer
    end
    
    TriggerClientEvent('jammer:client:sync', -1, allJammers)
end

local function CountPlayerJammers(identifier)
    local count = 0
    for _, jammer in pairs(jammers) do
        if jammer.owner == identifier then
            count = count + 1
        end
    end
    return count
end

-- ================================================================
-- PERMANENT JAMMERS INITIALIZATION
-- ================================================================
local function LoadPermanentJammers()
    if Config.PermanentJammers then
        local counter = -1000 -- Use negative IDs for permanent jammers
        for _, jammerConfig in ipairs(Config.PermanentJammers) do
            -- Validate coordinates before creating jammer
            if not ValidateCoordinates(jammerConfig.coords) then
                DebugPrint('[Jammer] ERROR: Invalid coordinates for permanent jammer, skipping', "coordinates")
                goto continue
            end
              permanentJammers[counter] = {
                coords = jammerConfig.coords,
                heading = jammerConfig.heading or 0.0,
                health = Config.JammerHealth,
                owner = "system",
                permanent = true,
                label = jammerConfig.label or "Permanent Jammer",
                range = jammerConfig.range or Config.PermanentJammerRange or 50.0,
                noGoZone = jammerConfig.noGoZone or Config.DefaultNoGoZonePercentage or 0.2,
                model = jammerConfig.model or Config.JammerModel,  -- Use custom model or default
                ignoredJobs = jammerConfig.ignoredJobs or {}       -- Add ignored jobs for job detection
            }
            
            DebugPrint('[Jammer] Loaded permanent jammer ' .. counter .. ' at (' .. 
                      jammerConfig.coords.x .. ', ' .. jammerConfig.coords.y .. ', ' .. jammerConfig.coords.z .. ')')
            
            ::continue::
            counter = counter - 1
        end
        DebugPrint('[Jammer] Loaded ' .. #Config.PermanentJammers .. ' permanent jammers')
    end
end

-- ================================================================
-- EXPORTS
-- ================================================================
exports('GetAllJammers', function()
    local allJammers = {}
    for id, jammer in pairs(jammers) do
        allJammers[id] = jammer
    end
    for id, jammer in pairs(permanentJammers) do
        allJammers[id] = jammer
    end
    return allJammers
end)

-- ================================================================
-- EVENTS
-- ================================================================
RegisterNetEvent('jammer:server:place')
AddEventHandler('jammer:server:place', function(coords, heading)
    local source = source
    local identifier = GetPlayerIdentifier(source)
    
    DebugPrint('[Jammer] DEBUG: Place jammer request from player ' .. source)
    
    -- Basic validation
    if not identifier then 
        DebugPrint('[Jammer] ERROR: Could not get identifier for player ' .. source)
        return 
    end
    
    DebugPrint('[Jammer] DEBUG: Player identifier: ' .. identifier)
    
    -- Coordinate validation
    if not ValidateCoordinates(coords) then
        DebugPrint('[Jammer] ERROR: Invalid coordinates from player ' .. source)
        TriggerClientEvent('jammer:client:notification', source, 'Invalid placement location')
        return
    end
    
    -- Validate heading value
    if type(heading) ~= "number" or heading < 0 or heading > 360 then
        DebugPrint('[Jammer] DEBUG: Invalid heading (' .. tostring(heading) .. '), defaulting to 0.0')
        heading = 0.0
    end
    
    DebugPrint('[Jammer] DEBUG: Checking permissions...')
    
    -- Check permissions
    if not CanPlayerUseJammer(source) then
        DebugPrint('[Jammer] ERROR: Player ' .. source .. ' does not have permission to use jammers')
        TriggerClientEvent('jammer:client:notification', source, Config.Notifications.noPermission)
        return
    end
    
    DebugPrint('[Jammer] DEBUG: Checking if player has item...')
    
    -- Check if player has item
    if not HasItem(source, Config.ItemName) then
        DebugPrint('[Jammer] ERROR: Player ' .. source .. ' does not have jammer item')
        TriggerClientEvent('jammer:client:notification', source, Config.Notifications.noItem)
        return
    end
    
    DebugPrint('[Jammer] DEBUG: Checking jammer limit...')
    
    -- Check jammer limit
    local currentCount = CountPlayerJammers(identifier)
    DebugPrint('[Jammer] DEBUG: Player has ' .. currentCount .. ' jammers, limit is ' .. Config.MaxJammersPerPlayer)
    
    if currentCount >= Config.MaxJammersPerPlayer then
        DebugPrint('[Jammer] ERROR: Player ' .. source .. ' has reached jammer limit')
        TriggerClientEvent('jammer:client:notification', source, Config.Notifications.maxReached)
        return
    end
    
    DebugPrint('[Jammer] DEBUG: Removing item from inventory...')
      -- Remove item from inventory
    RemoveItem(source, Config.ItemName, 1)
    
    DebugPrint('[Jammer] DEBUG: Creating jammer...')
    
    -- Create jammer
    local jammerId = jammerIdCounter
    jammerIdCounter = jammerIdCounter + 1    jammers[jammerId] = {
        coords = coords,
        heading = heading,
        health = Config.JammerHealth,
        owner = identifier,
        permanent = false,
        label = "Player Jammer " .. jammerId,
        range = Config.JammerRange or 30.0,
        noGoZone = Config.DefaultNoGoZonePercentage or 0.2,
        model = Config.JammerModel  -- Use default model for player-placed jammers
    }
    
    DebugPrint('[Jammer] SUCCESS: Created jammer ' .. jammerId .. ' for player ' .. source)
    DebugPrint('[Jammer] DEBUG: Jammer coords: x=' .. coords.x .. ', y=' .. coords.y .. ', z=' .. coords.z)

    -- Sync with all clients
    SyncJammers()

    -- Notify player
    TriggerClientEvent('jammer:client:notification', source, Config.Notifications.placed)
    
    DebugPrint('[Jammer] Player ' .. source .. ' placed jammer ' .. jammerId .. ' at x=' .. coords.x .. ', y=' .. coords.y .. ', z=' .. coords.z)
end)

RegisterNetEvent('jammer:server:destroy')
AddEventHandler('jammer:server:destroy', function(jammerId, isPickup)
    local source = source
    local jammer = jammers[jammerId]
    local destroyerIdentifier = GetPlayerIdentifier(source)
    
    DebugPrint('[Jammer] DEBUG: Destroy request from player ' .. source .. ' for jammer ' .. jammerId)
    DebugPrint('[Jammer] DEBUG: Destroyer identifier: ' .. destroyerIdentifier)
    DebugPrint('[Jammer] DEBUG: IsPickup: ' .. tostring(isPickup))
    
    -- Check if jammer exists and is not permanent
    if not jammer then
        DebugPrint('[Jammer] ERROR: Jammer ' .. jammerId .. ' does not exist')
        TriggerClientEvent('jammer:client:notification', source, 'Jammer not found')
        return 
    end
    
    if jammer.permanent then
        DebugPrint('[Jammer] ERROR: Cannot destroy permanent jammer ' .. jammerId)
        TriggerClientEvent('jammer:client:notification', source, 'Cannot destroy permanent jammer')
        return 
    end
    
    -- Check permissions
    if not CanPlayerDestroy(source) then
        DebugPrint('[Jammer] ERROR: Player ' .. source .. ' does not have permission to destroy jammers')
        TriggerClientEvent('jammer:client:notification', source, Config.Notifications.noPermission)
        return
    end
    
    -- Check if destroyer is the owner
    local isOwner = (jammer.owner == destroyerIdentifier)
    DebugPrint('[Jammer] DEBUG: Jammer owner: ' .. tostring(jammer.owner))
    DebugPrint('[Jammer] DEBUG: IsOwner: ' .. tostring(isOwner))
    
    if isPickup and isOwner then
        -- Owner is picking up the jammer - give item back
        AddItem(source, Config.ItemName, 1)
        TriggerClientEvent('jammer:client:notification', source, Config.Notifications.destroyedWithItem)
        DebugPrint('[Jammer] Player ' .. source .. ' picked up jammer ' .. jammerId)    else
        -- Jammer is being destroyed (not picked up) - no item back
        if Config.DestructionEffects and Config.DestructionEffects.enabled then
            -- Trigger destruction effects on all clients
            TriggerClientEvent('jammer:client:playDestructionEffects', -1, jammer.coords)
        end
        
        local message = isOwner and Config.Notifications.destroyed or Config.Notifications.destroyedByOther
        TriggerClientEvent('jammer:client:notification', source, message)
        DebugPrint('[Jammer] Player ' .. source .. ' destroyed jammer ' .. jammerId .. (isOwner and ' (owner)' or ' (not owner)'))
    end
    
    -- Remove from memory
    jammers[jammerId] = nil
    DebugPrint('[Jammer] DEBUG: Removed jammer ' .. jammerId .. ' from server memory')
    
    -- Sync with all clients
    SyncJammers()
    DebugPrint('[Jammer] DEBUG: Synced jammers with all clients after destruction')
end)

-- Handle jammer destruction report from a client
RegisterNetEvent('jammer:server:reportDestruction')
AddEventHandler('jammer:server:reportDestruction', function(jammerId)
    local source = source
    DebugPrint('[Jammer] Destruction report for jammer ' .. tostring(jammerId) .. ' from player ' .. source)

    -- Add a yield to prevent any potential deadlocks
    Citizen.Wait(0)

    -- Find the jammer (check both player and permanent lists)
    local jammer = jammers[jammerId] or permanentJammers[jammerId]
    if not jammer then
        DebugPrint('[Jammer] ERROR: Received destruction report for non-existent jammer ID: ' .. tostring(jammerId))
        return
    end

    -- If the jammer is permanent, handle its destruction and respawn cycle
    if jammer.permanent then
        if Config.WeaponDestruction.permanentImmune then
            DebugPrint('[Jammer] Permanent jammer ' .. jammerId .. ' is immune and cannot be destroyed.')
            return -- Do nothing if immune
        end

        -- Play destruction effects
        if Config.DestructionEffects and Config.DestructionEffects.enabled then
            TriggerClientEvent('jammer:client:playDestructionEffects', -1, jammer.coords)
        end

        -- Temporarily remove the jammer from the list to make it disappear
        local jammerBackup = permanentJammers[jammerId]
        permanentJammers[jammerId] = nil
        SyncJammers() -- Sync removal with clients

        DebugPrint('[Jammer] Permanent jammer ' .. jammerId .. ' temporarily destroyed. Respawning soon...')

        -- Respawn the jammer after a delay
        Citizen.CreateThread(function()
            Citizen.Wait(3000) -- 3-second respawn delay
            jammerBackup.health = Config.JammerHealth -- Reset health
            permanentJammers[jammerId] = jammerBackup
            SyncJammers() -- Sync respawn with clients
            DebugPrint('[Jammer] Permanent jammer ' .. jammerId .. ' has respawned.')
        end)

    else
        -- If it's a player-placed jammer, destroy it permanently
        DebugPrint('[Jammer] Destroying player-placed jammer ' .. jammerId)

        -- Play destruction effects
        if Config.DestructionEffects and Config.DestructionEffects.enabled then
            TriggerClientEvent('jammer:client:playDestructionEffects', -1, jammer.coords)
        end

        -- Remove the jammer from the server and sync with all clients
        jammers[jammerId] = nil
        SyncJammers()
        DebugPrint('[Jammer] Player jammer ' .. jammerId .. ' destroyed and removed. Synced with clients.')
    end
end)

-- ================================================================
-- CLEANUP FUNCTIONS
-- ================================================================
local function CleanupServerJammers()
    local playerJammerCount = 0
    local permanentJammerCount = 0
    
    -- Count jammers before cleanup
    for _ in pairs(jammers) do
        playerJammerCount = playerJammerCount + 1
    end
    for _ in pairs(permanentJammers) do
        permanentJammerCount = permanentJammerCount + 1
    end
    
    print('[Jammer] Starting server cleanup...')
    print('[Jammer] Before cleanup: ' .. playerJammerCount .. ' player jammers, ' .. permanentJammerCount .. ' permanent jammers')
    
    -- Clear all player-placed jammers
    jammers = {}
    
    -- Reset counter
    jammerIdCounter = 1
    
    -- Sync with all clients to remove objects
    SyncJammers()
    
    print('[Jammer] Server cleanup complete - Removed ' .. playerJammerCount .. ' player jammers')
    print('[Jammer] Permanent jammers remain: ' .. permanentJammerCount)
end

-- Handle sync requests from clients
RegisterNetEvent('jammer:server:requestSync')
AddEventHandler('jammer:server:requestSync', function()
    local source = source
    SyncJammers()    DebugPrint('[Jammer] Manual sync requested by player ' .. source)
end)

-- Note: Duplicate destroy handler removed - using the main one above

-- Player disconnect - jammers now persist (removed auto-cleanup)
AddEventHandler('playerDropped', function(reason)
    local source = source
    local identifier = GetPlayerIdentifier(source)
    
    if not identifier then return end
    
    local jammerCount = 0
    
    -- Count jammers owned by disconnected player (but don't remove them)
    for id, jammer in pairs(jammers) do
        if jammer.owner == identifier then
            jammerCount = jammerCount + 1
        end
    end
    
    if jammerCount > 0 then
        print('[Jammer] Player ' .. source .. ' (' .. identifier .. ') disconnected - ' .. jammerCount .. ' jammers will persist')
    end
end)

-- ================================================================
-- COMMANDS
-- ================================================================
RegisterCommand('listjammers', function(source, args, rawCommand)
    if source == 0 then -- Console
        print('[Jammer] Active jammers:')
        for id, jammer in pairs(jammers) do
            print('  ID: ' .. id .. ' | Owner: ' .. jammer.owner .. ' | Coords: ' .. tostring(jammer.coords))
        end
        print('[Jammer] Permanent jammers:')
        for id, jammer in pairs(permanentJammers) do
            print('  ID: ' .. id .. ' | Label: ' .. jammer.label .. ' | Coords: ' .. tostring(jammer.coords))
        end
    else
        local identifier = GetPlayerIdentifier(source)
        local count = CountPlayerJammers(identifier)
        TriggerClientEvent('jammer:client:notification', source, 'You have ' .. count .. '/' .. Config.MaxJammersPerPlayer .. ' jammers placed')
    end
end, false)

RegisterCommand('clearjammers', function(source, args, rawCommand)
    if source ~= 0 then return end -- Console only
    
    jammers = {}
    SyncJammers()
    print('[Jammer] All player jammers cleared (permanent jammers remain)')
end, true)

RegisterCommand('cleanupjammers', function(source, args, rawCommand)
    if source ~= 0 then return end -- Console only
    
    CleanupServerJammers()
end, true)

RegisterCommand('restartjammers', function(source, args, rawCommand)
    if source ~= 0 then return end -- Console only
    
    print('[Jammer] Restarting jammer system...')
    
    -- Cleanup everything
    CleanupServerJammers()
    
    -- Wait a moment
    Citizen.Wait(2000)
    
    -- Clean up orphaned props
    CleanupOrphanedProps()
    
    -- Wait for cleanup to complete
    Citizen.Wait(3000)
    
    -- Reload permanent jammers
    LoadPermanentJammers()
    
    -- Sync with all clients
    SyncJammers()
    
    print('[Jammer] Jammer system restart complete')
end, true)

RegisterCommand('cleanuporphaned', function(source, args, rawCommand)
    if source ~= 0 then return end -- Console only
    
    print('[Jammer] Triggering orphaned prop cleanup...')
    CleanupOrphanedProps()
end, true)

RegisterCommand('givejammer', function(source, args, rawCommand)
    if source ~= 0 then return end -- Console only
    
    local targetId = tonumber(args[1])
    local amount = tonumber(args[2]) or 1
    
    if targetId and GetPlayerName(targetId) then
        AddItem(targetId, Config.ItemName, amount)
        print('[Jammer] Gave ' .. amount .. ' jammer(s) to player ' .. targetId)
    else
        print('[Jammer] Invalid player ID')
    end
end, true)



-- ================================================================
-- STARTUP CLEANUP FOR SCRIPT CRASHES
-- ================================================================
local function CleanupOrphanedProps()
    if not Config.CleanupSettings.cleanupOrphanedOnStart then
        print('[Jammer] Orphaned prop cleanup disabled in config')
        return
    end
    
    print('[Jammer] Starting cleanup of orphaned jammer props from previous sessions...')
    
    -- Send cleanup request to all clients
    TriggerClientEvent('jammer:client:cleanupOrphanedProps', -1)
    
    Citizen.Wait(2000) -- Give clients time to cleanup
    
    print('[Jammer] Orphaned prop cleanup request sent to all clients')
end

-- ================================================================
-- INITIALIZATION
-- ================================================================
Citizen.CreateThread(function()
    -- Clean up orphaned props from previous sessions first
    CleanupOrphanedProps()
    
    -- Load permanent jammers from config
    LoadPermanentJammers()
    
    -- Initial sync
    Citizen.Wait(3000) -- Wait a bit longer for cleanup to complete
    SyncJammers()
    
    print('[Jammer] System initialized - Disconnected player jammers will persist')
end)

-- Perform startup cleanup
Citizen.CreateThread(function()
    Citizen.Wait(5000) -- Wait for other resources to load
    CleanupOrphanedProps()
end)