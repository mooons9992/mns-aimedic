local QBCore = exports['qb-core']:GetCoreObject()
local isDead = false
local isBleeding = false
local medicCalled = false
local medicTimeout = false
local medicPed = nil
local medicVehicle = nil
local medicBlip = nil
local lastMedicCall = 0

-- Debug logging function
local function DebugLog(message)
    if Config.Debug then
        print("[MNS-AIMedic] " .. message)
    end
end

-- Check if player is dead
local function IsPlayerDead()
    return isDead
end

-- Check if player is bleeding out or dead
local function IsPlayerInNeedOfHelp()
    -- This now returns true for both bleeding out and dead states
    return isDead or isBleeding
end

-- Check if there are enough EMS online
local function AreEnoughEMSOnline()
    -- Using TriggerCallback to get online EMS count from server
    local emsCount = 0
    
    QBCore.Functions.TriggerCallback('mns-aimedic:server:GetOnlineEMS', function(count)
        emsCount = count
    end)
    
    -- Add a small delay to ensure callback completes
    Wait(100)
    
    return emsCount >= Config.MinEMSCount
end

-- Notification function
local function Notify(message, type)
    if Config.UseOxLibNotifications and Config.NotificationType == 'ox_lib' then
        exports['ox_lib']:notify({
            title = 'Emergency Services',
            description = message,
            type = type or 'inform',
            position = 'top',
            icon = 'fas fa-ambulance',
            iconColor = '#ff0000',
            duration = 5000
        })
    else
        QBCore.Functions.Notify(message, type)
    end
end

-- Create blip for medic
local function CreateMedicBlip(entity)
    if medicBlip then RemoveBlip(medicBlip) end
    
    medicBlip = AddBlipForEntity(entity)
    SetBlipSprite(medicBlip, Config.MedicBlip.sprite)
    SetBlipColour(medicBlip, Config.MedicBlip.color)
    SetBlipScale(medicBlip, Config.MedicBlip.scale)
    SetBlipAsShortRange(medicBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Config.MedicBlip.label)
    EndTextCommandSetBlipName(medicBlip)
    
    return medicBlip
end

-- Clean up medic resources
local function CleanupMedic()
    if medicPed then
        if DoesEntityExist(medicPed) then
            DeleteEntity(medicPed)
        end
        medicPed = nil
    end
    
    if medicVehicle then
        if DoesEntityExist(medicVehicle) then
            DeleteEntity(medicVehicle)
        end
        medicVehicle = nil
    end
    
    if medicBlip then
        RemoveBlip(medicBlip)
        medicBlip = nil
    end
    
    medicCalled = false
    
    -- Set timeout to prevent spam
    medicTimeout = true
    lastMedicCall = GetGameTimer()
    SetTimeout(Config.MedicTimeout, function()
        medicTimeout = false
    end)
end

-- Spawn the AI medic and vehicle
local function SpawnMedic()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    -- Find a valid spawn position for the vehicle
    local spawnPoint = nil
    local heading = 0
      -- Find closest vehicle node that's not too close to the player
    local found = false
    local attempts = 0
    local minDistance = 500.0  -- Much larger minimum distance
    local maxDistance = 750.0  -- Much larger maximum distance
    
    while not found and attempts < 20 do  -- Increased number of attempts
        attempts = attempts + 1
        local randomOffset = vector3(
            math.random(-maxDistance, maxDistance),
            math.random(-maxDistance, maxDistance),
            0.0
        )
        
        local testPos = vector3(
            playerCoords.x + randomOffset.x,
            playerCoords.y + randomOffset.y,
            playerCoords.z
        )
        
        local success, nodePos, nodeHeading = GetClosestVehicleNodeWithHeading(testPos.x, testPos.y, testPos.z, 1, 3.0, 0)
        
        if success then
            local distance = #(playerCoords - nodePos)
            if distance > minDistance and distance < maxDistance then
                -- Also check if there's a clear path to the player
                local _, hit, _, _, _ = GetShapeTestResult(StartShapeTestRay(
                    nodePos.x, nodePos.y, nodePos.z + 2.0,
                    playerCoords.x, playerCoords.y, playerCoords.z + 2.0,
                    2, 0, 0
                ))
                  if not hit then
                    spawnPoint = nodePos
                    heading = nodeHeading
                    found = true
                    DebugLog("Found valid spawn point at distance: " .. distance)
                end
            end
        end
    end
    
    -- Force far spawn if using fallback position
    if not found then
        -- Fallback spawn position - make sure it's far away
        local angle = math.random() * math.pi * 2 -- Random angle in radians
        local distance = 600.0 -- Force a minimum distance
        
        spawnPoint = vector3(
            playerCoords.x + math.cos(angle) * distance,
            playerCoords.y + math.sin(angle) * distance,
            playerCoords.z
        )
        
        -- Try to find a valid road near this far point
        local success, nodePos, nodeHeading = GetClosestVehicleNodeWithHeading(
            spawnPoint.x, spawnPoint.y, spawnPoint.z, 1, 3.0, 0)
          if success and #(playerCoords - nodePos) > 400.0 then
            spawnPoint = nodePos
            heading = nodeHeading
            DebugLog("Using fallback far road position at distance: " .. #(playerCoords - nodePos))
        else
            DebugLog("Using raw fallback position at distance: " .. #(playerCoords - spawnPoint))
        end
    end
    
    -- Request models
    RequestModel(GetHashKey(Config.MedicModel))
    RequestModel(GetHashKey(Config.MedicVehicle))
    
    while not HasModelLoaded(GetHashKey(Config.MedicModel)) or not HasModelLoaded(GetHashKey(Config.MedicVehicle)) do
        Wait(1)
    end
    
    -- Spawn vehicle
    local spawnCoords = spawnPoint
    
    -- Set z-coordinate correctly to avoid falling or floating
    local groundZ = 0
    for height = 1, 1000 do
        local foundGround, zPos = GetGroundZFor_3dCoord(spawnCoords.x, spawnCoords.y, spawnCoords.z + height)
        if foundGround then
            groundZ = zPos
            break
        end
    end
    spawnCoords = vector3(spawnCoords.x, spawnCoords.y, groundZ)
    
    -- Create the vehicle on a valid ground position
    medicVehicle = CreateVehicle(GetHashKey(Config.MedicVehicle), spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, false)
    SetEntityAsMissionEntity(medicVehicle, true, true)
    SetVehicleEngineOn(medicVehicle, true, true, false)
    SetVehRadioStation(medicVehicle, 'OFF')
    
    -- Turn on lights and sirens
    SetVehicleSiren(medicVehicle, true)
    SetVehicleLights(medicVehicle, 2)
    
    -- Spawn medic ped
    medicPed = CreatePedInsideVehicle(medicVehicle, 26, GetHashKey(Config.MedicModel), -1, true, false)
    SetEntityAsMissionEntity(medicPed, true, true)
    SetBlockingOfNonTemporaryEvents(medicPed, true)
    SetPedCanBeTargetted(medicPed, false)
    SetEntityInvincible(medicPed, true)
    
    -- Create blip
    CreateMedicBlip(medicVehicle)      -- Calculate ETA
    local eta = math.random(Config.MedicArrivalTime.min, Config.MedicArrivalTime.max)
    Notify(string.format(Config.Notifications.MedicDispatched, eta), "primary")
      -- Actually wait for the ETA before starting to drive
    DebugLog("Waiting " .. eta .. " seconds before starting ambulance journey")
    Wait(eta * 1000)
    
    -- Drive to player with better driving flags
    DebugLog("Medic starting journey to player")
      -- Set driving abilities
    SetDriverAbility(medicPed, 1.0) -- Maximum driving ability
    SetDriverAggressiveness(medicPed, 0.7) -- Slightly more aggressive to navigate better
    
    -- Make sure the vehicle is fully operational
    SetVehicleEngineOn(medicVehicle, true, true, false)
    SetVehicleForwardSpeed(medicVehicle, 10.0) -- Give it an initial push
    SetVehicleSiren(medicVehicle, true)
    
    -- Use a better driving style for emergency vehicles
    -- 786469 combines avoiding traffic + rushed flag + ignore lights
    local drivingStyle = 786469
    
    -- Apply emergency vehicle driving behavior
    SetVehicleHandlingField(medicVehicle, 'CHandlingData', 'fSteeringLock', 70.0)
    SetVehicleHasBeenOwnedByPlayer(medicVehicle, true)
    ModifyVehicleTopSpeed(medicVehicle, 50.0)
    
    -- Give clear driving instructions with higher speed
    ClearPedTasks(medicPed)
    TaskVehicleDriveToCoordLongrange(medicPed, medicVehicle, playerCoords.x, playerCoords.y, playerCoords.z, 35.0, drivingStyle, 10.0)
    
    -- Improved monitoring thread to keep the ambulance moving
    CreateThread(function()
        if not medicVehicle or not medicPed then return end
        
        local startPosition = GetEntityCoords(medicVehicle)
        local lastPosition = startPosition
        local stuckCounter = 0
        local routeRefreshCount = 0
        
        while DoesEntityExist(medicVehicle) and medicCalled do
            Wait(1000)
            
            local currentPosition = GetEntityCoords(medicVehicle)
            local distance = #(lastPosition - currentPosition)
            
            -- Refresh route every 10 seconds regardless of movement
            routeRefreshCount = routeRefreshCount + 1
            if routeRefreshCount >= 10 then
                local freshPlayerCoords = GetEntityCoords(PlayerPedId())
                ClearPedTasks(medicPed)
                TaskVehicleDriveToCoordLongrange(medicPed, medicVehicle, 
                    freshPlayerCoords.x, freshPlayerCoords.y, freshPlayerCoords.z, 
                    35.0, 786469, 10.0)                routeRefreshCount = 0
                DebugLog("Refreshing ambulance route to player")
            end
            
            -- Check if vehicle is stuck (not moving much)
            if distance < 0.3 then
                stuckCounter = stuckCounter + 1
                
                -- After 3 seconds of being stuck, try to fix it
                if stuckCounter >= 3 then
                    DebugLog("Ambulance appears stuck, attempting to fix...")
                    
                    -- Clear any existing tasks
                    ClearPedTasksImmediately(medicPed)
                    
                    -- Turn on engine and set vehicle in motion
                    SetVehicleEngineOn(medicVehicle, true, true, false)
                    SetVehicleForwardSpeed(medicVehicle, 15.0)
                    
                    -- Get fresh player coordinates
                    local freshPlayerCoords = GetEntityCoords(PlayerPedId())
                    
                    -- Try to find a better path
                    local success, roadPos, roadHeading = GetClosestVehicleNodeWithHeading(
                        currentPosition.x, currentPosition.y, currentPosition.z, 1, 3.0, 0)
                        
                    if success then
                        -- Move slightly toward the road node first
                        TaskVehicleDriveToCoord(medicPed, medicVehicle, roadPos.x, roadPos.y, roadPos.z, 
                            25.0, 0, GetEntityModel(medicVehicle), 787004, 15.0, true)
                        Wait(2000)
                    end
                    
                    -- Give a new driving task with different style
                    TaskVehicleDriveToCoordLongrange(medicPed, medicVehicle, 
                        freshPlayerCoords.x, freshPlayerCoords.y, freshPlayerCoords.z, 
                        35.0, 787004, 15.0)
                    
                    stuckCounter = 0
                end
            else
                stuckCounter = 0
            end
            
            lastPosition = currentPosition
              -- If we've reached the player, end the thread
            local distToPlayer = #(GetEntityCoords(PlayerPedId()) - currentPosition)
            if distToPlayer < 20.0 then
                DebugLog("Ambulance has reached player, ending monitor thread")
                break
            end
        end
    end)
    
    -- Check if medic reached player
    local timeout = 60 -- 60 second timeout
    local startTime = GetGameTimer()
    
    while true do
        Wait(1000)
        local medicCoords = GetEntityCoords(medicPed)
        local dist = #(playerCoords - medicCoords)
        
        -- Get current player position in case they've been moved
        playerCoords = GetEntityCoords(PlayerPedId())
        
        if dist < 20.0 then
            -- Medic arrived
            break
        end
        
        if GetGameTimer() - startTime > timeout * 1000 then            -- Timeout, teleport medic closer
            local street = GetStreetNameAtCoord(playerCoords.x, playerCoords.y, playerCoords.z)
            local streetName = GetStreetNameFromHashKey(street)
            DebugLog("Medic taking too long, teleporting closer to " .. streetName)
            
            -- Find a close but valid road position
            local foundSpot = false
            local tries = 0
            local closerPos = nil
            
            while not foundSpot and tries < 5 do
                tries = tries + 1
                local testPos = vector3(
                    playerCoords.x + math.random(-20, 20),
                    playerCoords.y + math.random(-20, 20),
                    playerCoords.z
                )
                
                local success, roadPos, roadHeading = GetClosestVehicleNodeWithHeading(testPos.x, testPos.y, testPos.z, 1, 3.0, 0)
                
                if success and #(playerCoords - roadPos) < 30.0 then
                    closerPos = roadPos
                    foundSpot = true
                end
            end
            
            if foundSpot then
                SetEntityCoords(medicVehicle, closerPos.x, closerPos.y, closerPos.z)
            else
                -- Last resort
                SetEntityCoords(medicVehicle, 
                    playerCoords.x + math.random(-10, 10), 
                    playerCoords.y + math.random(-10, 10), 
                    playerCoords.z)
            end
            break
        end
          -- Update destination if player moved significantly (more than 20 units)
        local currentPlayerCoords = GetEntityCoords(PlayerPedId())        if #(playerCoords - currentPlayerCoords) > 20.0 then
            playerCoords = currentPlayerCoords
            -- Use the improved navigation function
            ImproveAmbulanceNavigation()
            DebugLog("Player moved, updating ambulance destination")
        end
    end
    
    -- Park and exit vehicle
    TaskVehiclePark(medicPed, medicVehicle, playerCoords.x, playerCoords.y, playerCoords.z, 0.0, 1, 20.0, false)
    Wait(2000)
      -- Leave vehicle with urgency
    TaskLeaveVehicle(medicPed, medicVehicle, 256) -- 256 flag for urgency
    Wait(2000)
      -- Walk to player normally without aiming
    Notify(Config.Notifications.MedicArrived, "success")
    ClearPedTasksImmediately(medicPed)
    TaskGoToEntity(medicPed, playerPed, -1, 1.0, 2.0, 0, 0)
    DebugLog("Medic is walking to player normally without aiming")
      -- Wait until close enough
    local timeoutWalk = 30 -- 30 second timeout
    local startTimeWalk = GetGameTimer()
    
    while true do
        Wait(500)
        local medicCoords = GetEntityCoords(medicPed)
        local dist = #(GetEntityCoords(playerPed) - medicCoords)
        
        if dist < Config.ReviveDistance + 1.0 then
            -- Medic arrived at player
            break
        end
        
        if GetGameTimer() - startTimeWalk > timeoutWalk * 1000 then
            -- Timeout, teleport medic to player
            SetEntityCoords(medicPed, 
                playerCoords.x + 1.0, 
                playerCoords.y + 1.0, 
                playerCoords.z)
            break
        end
    end
    
    -- Check for payment first before any treatment
    if Config.RequiresCash then
        local playerData = QBCore.Functions.GetPlayerData()
        local bankBalance = playerData.money['bank']
        
        if bankBalance < Config.ReviveCost then
            -- Not enough money - medic checks and walks away
            Notify(string.format(Config.Notifications.NotEnoughMoney, Config.ReviveCost), "error")
            
            -- Play checking animation
            local checkDict = "amb@medic@standing@kneel@base"
            local checkAnim = "base"
            
            RequestAnimDict(checkDict)
            while not HasAnimDictLoaded(checkDict) do
                Wait(10)
            end
            
            -- Medic kneels down to check player
            TaskPlayAnim(medicPed, checkDict, checkAnim, 8.0, -8.0, 3000, 1, 0, false, false, false)
            Wait(3000)
            ClearPedTasks(medicPed)
            
            -- Medic shakes head or shows some disappointment
            local disappointDict = "anim@amb@nightclub@mini@dance@dance_solo@male@var_a@"
            local disappointAnim = "med_center_down"
            
            RequestAnimDict(disappointDict)
            while not HasAnimDictLoaded(disappointDict) do
                Wait(10)
            end
            
            TaskPlayAnim(medicPed, disappointDict, disappointAnim, 8.0, -8.0, 2000, 0, 0, false, false, false)
            Wait(2000)
            
            -- Medic leaves without reviving
            TaskEnterVehicle(medicPed, medicVehicle, 20000, -1, 2.0, 1, 0)
            Wait(5000)
            
            -- Drive away
            local randomCoords = vector3(
                playerCoords.x + math.random(-500, 500),
                playerCoords.y + math.random(-500, 500),
                playerCoords.z
            )
            
            -- Find a valid road to drive away on
            local success, roadPos, roadHeading = GetClosestVehicleNodeWithHeading(randomCoords.x, randomCoords.y, randomCoords.z, 1, 3.0, 0)
            if success then
                randomCoords = roadPos
            end
            
            TaskVehicleDriveToCoordLongrange(medicPed, medicVehicle, randomCoords.x, randomCoords.y, randomCoords.z, 20.0, 786603, 2.0)
            
            -- Clean up after some distance
            SetTimeout(15000, function()
                CleanupMedic()
            end)
            
            return -- Exit without reviving
        end
    end
    
    -- Start the revive process - player has money or payment not required
    
    -- Use proper CPR animation instead of aiming
    local animDict = "mini@cpr@char_a@cpr_str"
    local animName = "cpr_pumpchest"
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(1)
    end
      -- Loop the animation for the entire revive time
    local startTime = GetGameTimer()
    local animDuration = GetAnimDuration(animDict, animName) * 1000
    DebugLog("Starting CPR animation loop for " .. Config.ReviveTime .. "ms, animation duration: " .. animDuration .. "ms")
    
    while GetGameTimer() - startTime < Config.ReviveTime do
        if not IsEntityPlayingAnim(medicPed, animDict, animName, 3) then
            DebugLog("Playing CPR animation")
            TaskPlayAnim(medicPed, animDict, animName, 8.0, -8.0, -1, 1, 0, false, false, false)
        end
        Wait(1000) -- Check every second
    end-- Clear animation
    ClearPedTasks(medicPed)
    
    -- Process payment
    if Config.RequiresCash then
        local playerData = QBCore.Functions.GetPlayerData()
        local bankBalance = playerData.money['bank']
        
        if bankBalance >= Config.ReviveCost then
            -- Attempt to pay from bank
            TriggerServerEvent('mns-aimedic:server:PayForRevive', Config.ReviveCost)
        else
            -- Not enough money
            Notify(string.format(Config.Notifications.NotEnoughMoney, Config.ReviveCost), "error")
            
            -- Medic leaves without reviving
            Wait(3000)
            TaskEnterVehicle(medicPed, medicVehicle, 20000, -1, 2.0, 1, 0)
            Wait(5000)
            
            -- Drive away
            local randomCoords = vector3(
                playerCoords.x + math.random(-500, 500),
                playerCoords.y + math.random(-500, 500),
                playerCoords.z
            )
            
            -- Find a valid road to drive away on
            local success, roadPos, roadHeading = GetClosestVehicleNodeWithHeading(randomCoords.x, randomCoords.y, randomCoords.z, 1, 3.0, 0)
            if success then
                randomCoords = roadPos
            end
            
            TaskVehicleDriveToCoordLongrange(medicPed, medicVehicle, randomCoords.x, randomCoords.y, randomCoords.z, 20.0, 786603, 2.0)
            
            -- Clean up after some distance
            SetTimeout(15000, function()
                CleanupMedic()
            end)
            
            return -- Exit without reviving
        end
    else
        -- If payment not required, directly revive
        TriggerEvent('hospital:client:Revive')
    end
    
    -- Wait and then leave
    Wait(3000)
    TaskEnterVehicle(medicPed, medicVehicle, 20000, -1, 2.0, 1, 0)
    Wait(5000)
    
    -- Drive away
    local randomCoords = vector3(
        playerCoords.x + math.random(-500, 500),
        playerCoords.y + math.random(-500, 500),
        playerCoords.z
    )
    
    -- Find a valid road to drive away on
    local success, roadPos, roadHeading = GetClosestVehicleNodeWithHeading(randomCoords.x, randomCoords.y, randomCoords.z, 1, 3.0, 0)
    if success then
        randomCoords = roadPos
    end
    
    TaskVehicleDriveToCoordLongrange(medicPed, medicVehicle, randomCoords.x, randomCoords.y, randomCoords.z, 20.0, 786603, 2.0)
    
    -- Clean up after some distance
    SetTimeout(15000, function()
        CleanupMedic()
    end)
end

-- Helper function to improve ambulance navigation
local function ImproveAmbulanceNavigation()
    if medicVehicle and DoesEntityExist(medicVehicle) and medicPed and DoesEntityExist(medicPed) then
        -- Check if vehicle exists every time we call this
        if not DoesEntityExist(medicVehicle) or not DoesEntityExist(medicPed) then
            return
        end
        
        -- Get current locations
        local playerCoords = GetEntityCoords(PlayerPedId())
        local medicCoords = GetEntityCoords(medicPed)
        local distance = #(playerCoords - medicCoords)
        
        -- Basic improvements for the ambulance
        SetVehicleHandlingFloat(medicVehicle, "CHandlingData", "fSteeringLock", 70.0)
        SetVehicleHandlingFloat(medicVehicle, "CHandlingData", "fTractionCurveMax", 2.5)
        ModifyVehicleTopSpeed(medicVehicle, 50.0)
        
        -- Clear tasks and create fresh driving instructions
        ClearPedTasksImmediately(medicPed)
        
        -- First try to find the best road node to the player
        local success, roadPos, roadHeading = GetClosestVehicleNodeWithHeading(
            playerCoords.x, playerCoords.y, playerCoords.z, 
            1, 3.0, 0)
            
        if success then
            -- Use a specialized emergency vehicle driving style: combines rushed + ignore lights + avoid traffic
            local drivingStyle = 787396
            
            -- Give the driver maximum abilities
            SetDriverAbility(medicPed, 1.0)
            SetDriverAggressiveness(medicPed, 0.8)
            
            -- Give a significant speed boost to ensure it can get over hills
            SetVehicleForwardSpeed(medicVehicle, 15.0)
            
            -- Task the driver to get to the player's nearest road node
            TaskVehicleDriveToCoordLongrange(medicPed, medicVehicle, 
                roadPos.x, roadPos.y, roadPos.z, 
                35.0, drivingStyle, 15.0)
                
            print("Improved ambulance navigation - distance to player: " .. distance)
        end
    end
end

-- Fixed version - walk to player without aiming gun
local function FixedWalkToPlayer()
    -- Walk to player using normal walking animation, not aiming
    ClearPedTasksImmediately(medicPed)
    TaskGoToEntity(medicPed, playerPed, -1, 1.0, 2.0, 0, 0)
    Notify(Config.Notifications.MedicArrived, "success")
    print("Medic is walking to player normally without aiming")
end

-- Register a command for testing/fixing ambulance navigation
RegisterCommand('fixambulance', function()
    if medicCalled and medicVehicle and medicPed then
        ImproveAmbulanceNavigation()
        Notify("Attempting to fix ambulance navigation", "primary")
    else
        Notify("No active ambulance to fix", "error")
    end
end, false)

-- Mail command that player can use to send themselves a test mail
RegisterCommand('medicbill', function(source, args)
    local player = QBCore.Functions.GetPlayerData()
    if player then
        local amount = args[1] or Config.ReviveCost
        TriggerServerEvent('mns-aimedic:server:SendTestMail', tonumber(amount))
        Notify("Requesting test medical bill email...", "primary")
    end
end, false)

-- Call the AI medic
local function CallMedic()
    -- Check if medic is already called
    if medicCalled then
        return false
    end
    
    -- Force check for laststand/bleeding state
    local player = QBCore.Functions.GetPlayerData()
    if player and player.metadata and player.metadata.inlaststand then
        isBleeding = true
    end
    
    -- Check if player is dead or bleeding out
    if not IsPlayerInNeedOfHelp() then
        Notify(Config.Notifications.NotDead, "error")
        return false
    end
    
    -- Check timeout
    if medicTimeout then
        local timeLeft = math.ceil((Config.MedicTimeout - (GetGameTimer() - lastMedicCall)) / 1000)
        Notify("Please wait " .. timeLeft .. " seconds before calling an AI medic again.", "error")
        return false
    end
    
    -- Check if enough EMS are online
    if AreEnoughEMSOnline() then
        Notify(Config.Notifications.EnoughEMSOnline, "error")
        return false
    end
    
    -- Start medic process
    medicCalled = true
    Notify(Config.Notifications.NoEMSOnline, "primary")
    SpawnMedic()
    
    return true
end

-- Register command to call medic
RegisterCommand(Config.MedicCommand, function()
    -- Force check the bleeding state before attempting to call the medic
    local player = QBCore.Functions.GetPlayerData()
    if player and player.metadata and player.metadata.inlaststand then
        isBleeding = true
    end
    
    CallMedic()
end, false)

-- Event when player dies
RegisterNetEvent('hospital:client:SetDeathState', function(state)
    isDead = state
    
    -- Send ox_lib notification when player dies or is bleeding out
    if state and Config.UseOxLibNotifications and Config.NotificationType == 'ox_lib' then
        exports['ox_lib']:notify({
            title = 'Emergency Services',
            description = 'A medic has been dispatched to your location.',
            type = 'inform',
            position = 'top',
            icon = 'fas fa-ambulance',
            iconColor = '#ff0000',
            duration = 5000
        })
    end
    
    -- Automatically call medic if enabled and no EMS online
    if Config.AutomaticMedic and isDead and not medicCalled and not medicTimeout and not AreEnoughEMSOnline() then
        SetTimeout(5000, function() -- Give a slight delay
            if isDead and not medicCalled then
                CallMedic()
            end
        end)
    end
end)

-- Register events for bleeding state and downed state
RegisterNetEvent('hospital:client:SetBleeding', function(bool)
    DebugLog("SetBleeding event received: " .. tostring(bool))
    isBleeding = bool
    
    -- Send notification when bleeding starts
    if bool and not isDead and Config.UseOxLibNotifications and Config.NotificationType == 'ox_lib' then
        exports['ox_lib']:notify({
            title = 'Emergency Services',
            description = 'You are bleeding out. A medic has been dispatched to your location.',
            type = 'inform',
            position = 'top',
            icon = 'fas fa-ambulance',
            iconColor = '#ff0000',
            duration = 5000
        })
    end
    
    -- Automatically call medic
    if Config.AutomaticMedic and isBleeding and not isDead and not medicCalled and not medicTimeout and not AreEnoughEMSOnline() then
        SetTimeout(5000, function()
            if (isDead or isBleeding) and not medicCalled then
                CallMedic()
            end
        end)
    end
end)

-- Direct revive event for integrations
RegisterNetEvent('mns-aimedic:client:Revive', function()
    TriggerEvent('hospital:client:Revive')
end)

-- Handle payment processed response from server
RegisterNetEvent('mns-aimedic:client:PaymentProcessed', function(success, amount)    if success then
        -- Payment successful
        Notify(string.format(Config.Notifications.MoneyDeducted, amount), "success")
        
        -- Log payment success
        DebugLog("Payment processed successfully: $" .. amount)
        
        -- Revive player
        TriggerEvent('hospital:client:Revive')
    else
        -- Payment failed (shouldn't reach here but just in case)
        Notify(string.format(Config.Notifications.NotEnoughMoney, amount), "error")
    end
end)

-- Add additional event listeners for QBCore incapacitated state
RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)    if val and val.metadata and val.metadata.inlaststand ~= nil then
        isBleeding = val.metadata.inlaststand
        DebugLog("Player laststand state changed: " .. tostring(isBleeding))
        
        if isBleeding and not medicCalled and not medicTimeout and not AreEnoughEMSOnline() and Config.AutomaticMedic then
            SetTimeout(5000, function()
                if (isDead or isBleeding) and not medicCalled then
                    CallMedic()
                end
            end)
        end
    end
end)

-- Listen for ambulancejob:client:SetDeathStatus
RegisterNetEvent('ambulancejob:client:SetDeathStatus', function(isDead)
    isBleeding = isDead
    DebugLog("SetDeathStatus event received: " .. tostring(isDead))
end)

-- Listen for hospital:client:FinishServices as well
RegisterNetEvent('hospital:client:FinishServices', function()
    isBleeding = false
    isDead = false
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        CleanupMedic()
    end
end)

-- Check if player is in laststand state (manual check)
CreateThread(function()
    while true do
        Wait(1000)
        local player = QBCore.Functions.GetPlayerData()
        if player and player.metadata then
            local inLastStand = player.metadata.inlaststand
            local isDown = player.metadata.isdead
              if inLastStand and not isBleeding then
                DebugLog("Manual check detected player in laststand")
                isBleeding = true
                
                -- Send notification when bleeding starts
                if Config.UseOxLibNotifications and Config.NotificationType == 'ox_lib' then
                    exports['ox_lib']:notify({
                        title = 'Emergency Services',
                        description = 'You are bleeding out. A medic has been dispatched to your location.',
                        type = 'inform',
                        position = 'top',
                        icon = 'fas fa-ambulance',
                        iconColor = '#ff0000',
                        duration = 5000
                    })
                end
                
                -- Automatically call medic
                if Config.AutomaticMedic and not medicCalled and not medicTimeout and not AreEnoughEMSOnline() then
                    SetTimeout(5000, function()
                        if (isDead or isBleeding) and not medicCalled then
                            CallMedic()
                        end
                    end)
                end
            elseif isDown and not isDead then
                isDead = true
            elseif not inLastStand and not isDown then
                isBleeding = false
                isDead = false
            end
        end
    end
end)