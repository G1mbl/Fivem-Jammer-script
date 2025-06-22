-- ================================================================
-- SIMPLIFIED JAMMER SYSTEM - CLIENT SIDE
-- ================================================================

local QBCore = nil
local ESX = nil
local PlayerData = {}
local jammers = {}
local previewObject = nil
local jammerHealthTracking = {} -- Track jammer entity health for damage detection

-- ================================================================
-- FRAMEWORK INITIALIZATION
-- ================================================================
Citizen.CreateThread(function()
    if Config.Framework == "qb" then
        QBCore = exports['qb-core']:GetCoreObject()
        while not QBCore do
            Citizen.Wait(100)
            QBCore = exports['qb-core']:GetCoreObject()
        end
        PlayerData = QBCore.Functions.GetPlayerData()
    elseif Config.Framework == "esx" then
        ESX = exports["es_extended"]:getSharedObject()
        while not ESX do
            Citizen.Wait(100)
            ESX = exports["es_extended"]:getSharedObject()
        end
        while not ESX.GetPlayerData().job do
            Citizen.Wait(10)
        end
        PlayerData = ESX.GetPlayerData()
    end
    
    -- Request initial jammer sync from server
    Citizen.Wait(2000)
    TriggerServerEvent('jammer:server:requestSync')
end)

-- ================================================================
-- UTILITY FUNCTIONS
-- ================================================================
local function ShowNotification(message)
    if Config.Framework == "qb" then
        QBCore.Functions.Notify(message)
    elseif Config.Framework == "esx" then
        ESX.ShowNotification(message)
    else
        print("[JAMMER] " .. message)
    end
end

local function GetPlayerIdentifier()
    if Config.Framework == "qb" and QBCore then
        local PlayerData = QBCore.Functions.GetPlayerData()
        return PlayerData.citizenid
    elseif Config.Framework == "esx" and ESX then
        local PlayerData = ESX.GetPlayerData()
        return PlayerData.identifier
    end
    return tostring(GetPlayerServerId(PlayerId()))
end

local function HasItem(item)
    if Config.Framework == "qb" then
        local hasItem = QBCore.Functions.HasItem(item)
        return hasItem
    elseif Config.Framework == "esx" then
        if ESX and ESX.GetPlayerData() then
            local playerData = ESX.GetPlayerData()
            if playerData.inventory then
                for _, inventoryItem in pairs(playerData.inventory) do
                    if inventoryItem.name == item and inventoryItem.count > 0 then
                        return true
                    end
                end
            end
        end
        return false
    end
    return true
end

function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

-- ================================================================
-- PLACEMENT ANIMATION FUNCTIONS
-- ================================================================
local function PlayPlacementAnimation()
    local animConfig = Config.PlacementAnimations.ground
    if not animConfig or not animConfig.enabled then
        return false
    end
    
    local playerPed = PlayerPedId()
    
    -- Request animation dictionary
    RequestAnimDict(animConfig.dict)
    while not HasAnimDictLoaded(animConfig.dict) do
        Citizen.Wait(1)
    end
    
    -- Play animation
    TaskPlayAnim(playerPed, animConfig.dict, animConfig.name, 8.0, -8.0, animConfig.duration or 3000, animConfig.flag or 1, 0, false, false, false)
    
    return true
end

-- ================================================================
-- PLACEMENT FUNCTIONS
-- ================================================================
local function IsLocationClear(coords, radius)
    if not Config.CheckForCollisions then return true end
    
    local checkRadius = radius or 1.5
    local objects = GetGamePool('CObject')
    
    for i = 1, #objects do
        local obj = objects[i]
        if DoesEntityExist(obj) then
            local objCoords = GetEntityCoords(obj)
            local distance = #(coords - objCoords)
            
            if distance < checkRadius then
                return false
            end
        end
    end
    
    return true
end

-- ================================================================
-- PLACEMENT COORDINATE CALCULATION
-- ================================================================
local function GetPlacementCoords()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local playerHeading = GetEntityHeading(playerPed)
    
    -- Get player's forward vector
    local forwardVector = GetEntityForwardVector(playerPed)
    
    -- Calculate placement position in front of player
    local offsetCoords = vector3(
        playerCoords.x + (forwardVector.x * Config.PlacementOffset.forward),
        playerCoords.y + (forwardVector.y * Config.PlacementOffset.forward),
        playerCoords.z + Config.PlacementOffset.up
    )
    
    -- Try multiple methods to find the best placement surface
    local finalCoords = offsetCoords
    local adjustedHeading = (playerHeading + 180.0) % 360.0
    
    -- Method 1: Try to find ground below the offset position
    local groundFound, groundZ = GetGroundZFor_3dCoord(offsetCoords.x, offsetCoords.y, offsetCoords.z + 5.0, false)
    
    if groundFound and groundZ then
        finalCoords = vector3(offsetCoords.x, offsetCoords.y, groundZ + Config.PlacementOffset.up)
    else
        -- Method 2: Raycast downward to find any surface
        local raycast = StartShapeTestRay(
            offsetCoords.x, offsetCoords.y, offsetCoords.z + 5.0,  -- Start above
            offsetCoords.x, offsetCoords.y, offsetCoords.z - 5.0,  -- End below
            1, -- Ray flag for world collision
            playerPed, 
            0
        )
        
        local _, hit, endCoords = GetShapeTestResult(raycast)
        if hit then
            finalCoords = vector3(endCoords.x, endCoords.y, endCoords.z + Config.PlacementOffset.up)
        else
            -- Method 3: Raycast forward from player to find wall/surface
            local forwardRaycast = StartShapeTestRay(
                playerCoords.x, playerCoords.y, playerCoords.z + 1.0,  -- Start at player chest level
                playerCoords.x + (forwardVector.x * Config.PlacementOffset.forward), 
                playerCoords.y + (forwardVector.y * Config.PlacementOffset.forward), 
                playerCoords.z + 1.0,  -- End at same height
                1, -- Ray flag for world collision
                playerPed, 
                0
            )
            
            local _, wallHit, wallCoords = GetShapeTestResult(forwardRaycast)
            if wallHit then
                -- Place slightly in front of the wall
                finalCoords = vector3(
                    wallCoords.x - (forwardVector.x * 0.1), 
                    wallCoords.y - (forwardVector.y * 0.1), 
                    wallCoords.z
                )
            else
                -- Fallback: use player position as reference
                finalCoords = vector3(offsetCoords.x, offsetCoords.y, playerCoords.z + Config.PlacementOffset.up)
            end
        end
    end
    
    return finalCoords, adjustedHeading
end

-- ================================================================
-- INSTANT PLACEMENT SYSTEM
-- ================================================================

local function PlaceJammer()
    if not HasItem(Config.ItemName) then
        ShowNotification(Config.Notifications.noItem)
        return
    end

    local coords, heading = GetPlacementCoords()
    local distance = #(GetEntityCoords(PlayerPedId()) - coords)

    if distance > Config.PlacementRange then
        ShowNotification(Config.Notifications.tooFar)
        return
    end

    local coordsTable = { x = coords.x, y = coords.y, z = coords.z }
    
    -- Play placement animation if enabled
    local animPlayed = PlayPlacementAnimation()

    if animPlayed then
        ShowNotification("~y~Placing jammer...~s~")
        
        -- Send placement request to server immediately
        TriggerServerEvent('jammer:server:place', coordsTable, heading)
        
        -- Wait for animation to complete
        Citizen.CreateThread(function()
            local waitTime = Config.PlacementAnimations.ground.duration or 3000
            Citizen.Wait(waitTime)
            ClearPedTasks(PlayerPedId())
        end)
    else
        -- No animation, just place immediately
        TriggerServerEvent('jammer:server:place', coordsTable, heading)
    end
end

-- ================================================================
-- JAMMER INTERACTION
-- ================================================================
local currentInteraction = { inProgress = false }

-- Simplified functions to only handle animations
local function StartJammerInteraction()
    local playerPed = PlayerPedId()
    local animConfig = Config.PlacementAnimations.ground
    if animConfig and animConfig.enabled then
        RequestAnimDict(animConfig.dict)
        while not HasAnimDictLoaded(animConfig.dict) do
            Citizen.Wait(1)
        end
        -- Play looping animation
        TaskPlayAnim(playerPed, animConfig.dict, animConfig.name, 8.0, -8.0, -1, animConfig.flag or 1, 0, false, false, false)
    end
end

local function StopJammerInteraction()
    ClearPedTasks(PlayerPedId())
end

-- The main interaction thread, rewritten for stability
Citizen.CreateThread(function()
    local interactionTargetId = nil -- The ID of the jammer we are currently showing a prompt for

    while true do
        Citizen.Wait(5) -- Run the loop frequently for responsiveness

        local playerCoords = GetEntityCoords(PlayerPedId())
        
        -- Only search for new targets if we are not in an active interaction
        if not currentInteraction.inProgress then
            local closestJammer, closestDist = nil, -1
            
            -- Find the closest jammer within range
            for id, jammer in pairs(jammers) do
                if jammer.coords and not jammer.permanent then
                    local distance = #(playerCoords - vector3(jammer.coords.x, jammer.coords.y, jammer.coords.z))
                    if distance < Config.InteractionRange then
                        local isOwner = (jammer.owner == GetPlayerIdentifier())
                        local canDestroy = Config.AllowAnyoneToDestroy or isOwner
                        if canDestroy and (closestDist == -1 or distance < closestDist) then
                            closestJammer, closestDist = jammer, distance
                            interactionTargetId = id
                        end
                    end
                end
            end

            if closestJammer then
                -- We have a target, show the initial prompt with sound
                local isOwner = (closestJammer.owner == GetPlayerIdentifier())
                local text = isOwner and Config.Notifications.pickupProgress or Config.Notifications.destroyProgress
                BeginTextCommandDisplayHelp("STRING")
                AddTextComponentSubstringPlayerName(text)
                EndTextCommandDisplayHelp(0, false, true, -1) -- Play sound for initial prompt

                -- Check if player starts holding the key
                if IsControlJustPressed(0, Config.PickupConfirmation.key or 38) then
                    currentInteraction = {
                        inProgress = true,
                        targetId = interactionTargetId,
                        isOwner = isOwner,
                        startTime = GetGameTimer()
                    }
                    StartJammerInteraction() -- Start the animation
                end
            end
        end

        -- Handle the ongoing interaction (progress)
        if currentInteraction.inProgress then
            local targetJammer = jammers[currentInteraction.targetId]
            
            -- Check if the interaction should be cancelled
            if not targetJammer or #(playerCoords - vector3(targetJammer.coords.x, targetJammer.coords.y, targetJammer.coords.z)) > Config.InteractionRange + 0.5 or not IsControlPressed(0, Config.PickupConfirmation.key or 38) then
                StopJammerInteraction()
                ShowNotification("Interaction cancelled.")
                currentInteraction = { inProgress = false }
            else
                -- Continue interaction: show progress text without sound or percentage
                local holdTime = GetGameTimer() - currentInteraction.startTime
                local requiredTime = Config.PickupConfirmation.holdTime or 2000
                
                local progressText = currentInteraction.isOwner and "Picking up..." or "Destroying..."
                BeginTextCommandDisplayHelp("STRING")
                AddTextComponentSubstringPlayerName(progressText)
                EndTextCommandDisplayHelp(0, false, false, -1) -- No sound for progress updates

                -- Check if interaction is complete
                if holdTime >= requiredTime then
                    TriggerServerEvent('jammer:server:destroy', currentInteraction.targetId, currentInteraction.isOwner)
                    StopJammerInteraction()
                    currentInteraction = { inProgress = false }
                end
            end
        end
    end
end)

-- ================================================================
-- BEEPING SOUND
-- ================================================================
local lastBeepTime = 0

Citizen.CreateThread(function()
    if not Config.BeepingSound.enabled then return end
    
    while true do
        local playerCoords = GetEntityCoords(PlayerPedId())
        local currentTime = GetGameTimer()
        local shouldBeep = false
        
        for _, jammer in pairs(jammers) do
            local distance = #(playerCoords - vector3(jammer.coords.x, jammer.coords.y, jammer.coords.z))
            if distance <= Config.BeepingSound.range then
                shouldBeep = true
                break
            end
        end
        
        if shouldBeep and (currentTime - lastBeepTime) >= Config.BeepingSound.interval then
            PlaySoundFrontend(-1, Config.BeepingSound.sound.name, Config.BeepingSound.sound.set, true)
            lastBeepTime = currentTime
        end
        
        Citizen.Wait(shouldBeep and 100 or 1000)
    end
end)

-- ================================================================
-- JAMMER SYNCHRONIZATION
-- ================================================================
RegisterNetEvent('jammer:client:sync')
AddEventHandler('jammer:client:sync', function(serverJammers)
    if Config.Debug.enabled then
        print('[Jammer Client] Received sync with ' .. (serverJammers and tablelength(serverJammers) or 0) .. ' jammers from server')
    end

    local serverJammerIds = {}
    if serverJammers and type(serverJammers) == "table" then
        for id, _ in pairs(serverJammers) do
            serverJammerIds[id] = true
        end
    end

    -- Deletion Pass: Remove jammers that are no longer sent by the server
    for id, jammer in pairs(jammers) do
        if not serverJammerIds[id] then
            if jammer.object and DoesEntityExist(jammer.object) then
                if Config.Debug.enabled then
                    print('[Jammer Client] Deleting stale jammer object ' .. id)
                end
                SetEntityAsMissionEntity(jammer.object, true, true)
                DeleteObject(jammer.object)
            end
            jammers[id] = nil
            jammerHealthTracking[id] = nil
        end
    end

    -- Creation/Update Pass: Add new jammers
    if serverJammers and type(serverJammers) == "table" then
        for id, serverJammerData in pairs(serverJammers) do
            if not jammers[id] then
                -- This is a new jammer, create it
                if serverJammerData and serverJammerData.coords then
                    local jammerModel = serverJammerData.model or Config.JammerModel
                    local modelHash = GetHashKey(jammerModel)

                    RequestModel(modelHash)
                    while not HasModelLoaded(modelHash) do
                        Citizen.Wait(1)
                    end

                    local object = CreateObject(modelHash, serverJammerData.coords.x, serverJammerData.coords.y, serverJammerData.coords.z, true, true, false)
                    
                    if DoesEntityExist(object) then
                        SetEntityHeading(object, serverJammerData.heading or 0.0)
                        FreezeEntityPosition(object, true)
                        
                        local jammerHealth = serverJammerData.health or Config.JammerHealth
                        SetEntityHealth(object, jammerHealth)
                        SetEntityMaxHealth(object, Config.JammerHealth)

                        jammers[id] = {
                            id = id,
                            coords = serverJammerData.coords,
                            heading = serverJammerData.heading,
                            owner = serverJammerData.owner,
                            permanent = serverJammerData.permanent,
                            label = serverJammerData.label,
                            range = serverJammerData.range,
                            noGoZone = serverJammerData.noGoZone,
                            model = jammerModel,
                            ignoredJobs = serverJammerData.ignoredJobs or {},
                            object = object -- Store the entity handle
                        }

                        jammerHealthTracking[id] = {
                            lastHealth = jammerHealth,
                            maxHealth = Config.JammerHealth,
                            reportedDestroyed = false
                        }

                        if Config.Debug.enabled then
                            print('[Jammer Client] Created new jammer entity ' .. id)
                        end
                    else
                        print('[Jammer Client] ERROR: Failed to create jammer entity for ID ' .. id)
                    end
                end
            end
        end
    end

    if Config.Debug.enabled then
        print('[Jammer Client] Sync complete. Total tracked jammers: ' .. tablelength(jammers))
    end
end)

-- ================================================================
-- SERVER EVENTS
-- ================================================================
RegisterNetEvent('jammer:client:notification')
AddEventHandler('jammer:client:notification', function(message)
    ShowNotification(message)
end)

-- ================================================================
-- DESTRUCTION EFFECTS EVENT HANDLER
-- ================================================================
RegisterNetEvent('jammer:client:playDestructionEffects')
AddEventHandler('jammer:client:playDestructionEffects', function(coords)
    print('[Jammer Client] Destruction effects triggered at coords:', coords.x, coords.y, coords.z)
    
    if Config.DestructionEffects and Config.DestructionEffects.enabled then
        print('[Jammer Client] Destruction effects are enabled, proceeding...')
        
        -- Play sound effect
        if Config.DestructionEffects.playSound then
            print('[Jammer Client] Playing destruction sound')
            PlaySoundFromCoord(-1, Config.DestructionEffects.soundName, coords.x, coords.y, coords.z, Config.DestructionEffects.soundSet, false, Config.DestructionEffects.soundVolume or 0.3, false)
        end
        
        -- Create FX particle effect
        if Config.DestructionEffects.useFX then
            print('[Jammer Client] Creating particle FX effect')
            RequestNamedPtfxAsset(Config.DestructionEffects.fxDict)
            while not HasNamedPtfxAssetLoaded(Config.DestructionEffects.fxDict) do
                Citizen.Wait(1)
            end
            
            UseParticleFxAssetNextCall(Config.DestructionEffects.fxDict)
            local fxHandle = StartParticleFxLoopedAtCoord(Config.DestructionEffects.fxName, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, Config.DestructionEffects.fxScale, false, false, false, false)
            
            print('[Jammer Client] Started particle FX with handle:', fxHandle)
            
            -- Stop the FX after a short duration
            Citizen.CreateThread(function()
                Citizen.Wait(Config.DestructionEffects.fxDuration or 3000)
                StopParticleFxLooped(fxHandle, false)
                print('[Jammer Client] Stopped particle FX after duration')
            end)
        end
        
        -- Create explosion effect
        if Config.DestructionEffects.useExplosion then
            print('[Jammer Client] Creating explosion effect')
            AddExplosion(coords.x, coords.y, coords.z, Config.DestructionEffects.explosionType or 13, 
                        Config.DestructionEffects.explosionScale or 0.1, true, false, 0.0)
        end
    else
        print('[Jammer Client] Destruction effects are disabled in config')
    end
    
    -- CRITICAL FIX: Force removal of jammer prop at the coordinates
    -- This ensures the prop is removed even if the sync doesn't work properly
    local found = false
    for id, jammer in pairs(jammers) do
        if jammer.coords then
            local distance = math.abs(jammer.coords.x - coords.x) + math.abs(jammer.coords.y - coords.y) + math.abs(jammer.coords.z - coords.z)
            if distance < 1.0 then -- Within 1 meter tolerance
                print('[Jammer Client] Found matching jammer', id, 'for destruction at distance', distance)
                if jammer.object and DoesEntityExist(jammer.object) then
                    SetEntityAsMissionEntity(jammer.object, true, true)
                    DeleteObject(jammer.object)
                    print('[Jammer Client] Deleted jammer prop for ID', id)
                    found = true
                else
                    print('[Jammer Client] Jammer object does not exist for ID', id)
                end
                jammers[id] = nil
                jammerHealthTracking[id] = nil  -- Clean up health tracking
                break
            end
        end
    end
    
    -- If no exact match found, try to find and remove any jammer entity near the coordinates
    if not found then
        print('[Jammer Client] No exact match found, searching for nearby jammer entities...')
        local nearbyObjects = GetGamePool('CObject')
        for i = 1, #nearbyObjects do
            local obj = nearbyObjects[i]
            if DoesEntityExist(obj) then
                local objCoords = GetEntityCoords(obj)
                local distance = #(vector3(coords.x, coords.y, coords.z) - objCoords)
                
                if distance < 2.0 then -- Within 2 meter radius
                    local model = GetEntityModel(obj)
                    -- Check if this is a jammer model
                    if model == GetHashKey(Config.JammerModel) or 
                       model == GetHashKey("sm_prop_smug_jammer") or 
                       model == GetHashKey("gr_prop_gr_rsply_crate04a") or
                       model == GetHashKey("m23_1_prop_m31_jammer_01a") then
                        print('[Jammer Client] Found nearby jammer entity at distance', distance, 'removing it')
                        SetEntityAsMissionEntity(obj, true, true)
                        DeleteObject(obj)
                        found = true
                        break
                    end
                end
            end
        end
    end
    
    if not found then
        print('[Jammer Client] WARNING: No jammer entity found for destruction at coords:', coords.x, coords.y, coords.z)
    end
end)

-- ================================================================
-- JAMMER DAMAGE DETECTION SYSTEM
-- ================================================================

-- Thread to monitor jammer entity health for damage detection
Citizen.CreateThread(function()
    if not Config.WeaponDestruction.enabled then return end
    
    while true do
        Citizen.Wait(250) -- Check every 250ms
        
        for id, jammer in pairs(jammers) do
            if jammer.object and DoesEntityExist(jammer.object) then
                local currentHealth = GetEntityHealth(jammer.object)
                
                -- Initialize health tracking if not present
                if not jammerHealthTracking[id] then
                    jammerHealthTracking[id] = {
                        lastHealth = currentHealth,
                        maxHealth = jammer.maxHealth or Config.JammerHealth,
                        reportedDestroyed = false
                    }
                end
                
                -- Only proceed if not already reported as destroyed
                if not jammerHealthTracking[id].reportedDestroyed then
                    local lastHealth = jammerHealthTracking[id].lastHealth
                    
                    -- Check if health has decreased
                    if currentHealth < lastHealth then
                        local isDestroyed = currentHealth <= 0
                        
                        -- If destroyed, report it to the server once
                        if isDestroyed then
                            TriggerServerEvent('jammer:server:reportDestruction', id)
                            jammerHealthTracking[id].reportedDestroyed = true -- Mark as reported to prevent duplicate events
                            
                            if Config.Debug.enabled then
                                print('[Jammer Client] Jammer ' .. id .. ' DESTROYED - reporting to server.')
                            end
                        end
                        
                        -- Always update the last known health
                        jammerHealthTracking[id].lastHealth = currentHealth
                    end
                end
            end
        end
    end
end)

-- ================================================================
-- EXPORTS FOR OTHER RESOURCES
-- ================================================================

-- Export function to get all jammers for other resources (like drone script)
exports('GetAllJammers', function()
    local jammerTable = {}
    local processedCount = 0
    local invalidCount = 0
    
    if jammers then
        for id, jammer in pairs(jammers) do
            -- Enhanced validation for jammer data
            if jammer and type(jammer) == "table" and 
               jammer.coords and type(jammer.coords) == "table" and 
               tonumber(jammer.coords.x) and tonumber(jammer.coords.y) and tonumber(jammer.coords.z) then
                
                -- Calculate proper range and noGoZone with validation
                local jammerRange = tonumber(jammer.range)
                if not jammerRange or jammerRange <= 0 then
                    jammerRange = jammer.permanent and (tonumber(Config.PermanentJammerRange) or 75.0) or (tonumber(Config.JammerRange) or 30.0)
                end
                
                local noGoZoneValue = tonumber(jammer.noGoZone)
                if not noGoZoneValue then
                    noGoZoneValue = tonumber(Config.DefaultNoGoZonePercentage) or 0.2
                end
                
                -- Ensure jammer has all required properties for drone script
                jammerTable[id] = {
                    id = tonumber(id) or id,
                    coords = {
                        x = tonumber(jammer.coords.x),
                        y = tonumber(jammer.coords.y),
                        z = tonumber(jammer.coords.z)
                    },
                    heading = tonumber(jammer.heading) or 0.0,
                    owner = tostring(jammer.owner or "unknown"),
                    permanent = jammer.permanent == true,
                    label = tostring(jammer.label or ("Jammer " .. id)),
                    range = jammerRange,
                    model = tostring(jammer.model or Config.JammerModel),
                    noGoZone = noGoZoneValue,
                    health = tonumber(jammer.health) or tonumber(Config.JammerHealth) or 100,
                    ignoredJobs = jammer.ignoredJobs or {} -- Add ignored jobs list for job detection
                }
                processedCount = processedCount + 1
                
                if Config.Debug and Config.Debug.enabled and processedCount <= 3 then
                    print('[Jammer Export] Successfully exported jammer ' .. tostring(id) .. 
                          ' - Range: ' .. jammerRange .. 
                          ', NoGoZone: ' .. noGoZoneValue .. 
                          ', Permanent: ' .. tostring(jammer.permanent))
                end
            else
                invalidCount = invalidCount + 1
                if Config.Debug and Config.Debug.enabled then
                    print('[Jammer Export] WARNING: Invalid jammer data for ID ' .. tostring(id) .. ' - missing or invalid coords')
                    if jammer then
                        print('  coords type: ' .. type(jammer.coords))
                        if jammer.coords and type(jammer.coords) == "table" then
                            print('  x: ' .. tostring(jammer.coords.x) .. ', y: ' .. tostring(jammer.coords.y) .. ', z: ' .. tostring(jammer.coords.z))
                        end
                    end
                end
            end
        end
    end
    
    local totalJammers = tablelength(jammers or {})
    
    if Config.Debug and Config.Debug.enabled then
        print('[Jammer Client] Export GetAllJammers: ' .. processedCount .. ' valid, ' .. invalidCount .. ' invalid out of ' .. totalJammers .. ' total jammers')
        
        -- Debug sample jammer data structure for verification
        for id, jammer in pairs(jammerTable) do
            print('[Jammer Export] Sample export - ID: ' .. tostring(id) .. 
                  ', coords: (' .. jammer.coords.x .. ', ' .. jammer.coords.y .. ', ' .. jammer.coords.z .. ')' ..
                  ', range: ' .. tostring(jammer.range) .. 
                  ', noGoZone: ' .. tostring(jammer.noGoZone) ..
                  ', owner: ' .. tostring(jammer.owner) ..
                  ', permanent: ' .. tostring(jammer.permanent))
            break -- Only show first one
        end
    end
    
    return jammerTable
end)

-- Export function to get jammer by ID
exports('GetJammerById', function(id)
    if jammers and jammers[id] then
        return jammers[id]
    end
    return nil
end)

-- Export function to check if a jammer is in a specific location
exports('IsJammerAt', function(coords, radius)
    radius = radius or 5.0
    for id, jammer in pairs(jammers or {}) do
        if jammer.coords then
            local distance = #(vector3(coords.x, coords.y, coords.z) - vector3(jammer.coords.x, jammer.coords.y, jammer.coords.z))
            if distance <= radius then
                return true, id, jammer
            end
        end
    end
    return false
end)

-- ================================================================
-- DEBUG COMMANDS FOR TESTING
-- ================================================================



-- ================================================================
-- ITEM USAGE EVENT
-- ================================================================
RegisterNetEvent('jammer:use')
AddEventHandler('jammer:use', function()
    PlaceJammer()
end)

-- ================================================================







