local RSGCore = exports['rsg-core']:GetCoreObject()


local placedStands = {}
local worldStands = {}
local currentStand = nil
local isSitting = false
local isShining = false
local isBeingShined = false
local sittingPlayer = nil
local queuedNPCs = {}
local StartingCoords = nil
local autoShinerNPC = nil
local autoShinerActive = false
local isPlacingStand = false
local isCallingCustomer = false
local lastPromptTime = 0
local promptCooldown = 500
local pendingShinerNPC = nil  


local promptGroup = GetRandomIntInRange(1, 1000000)
local sitPrompt = nil
local shinePrompt = nil
local standUpPrompt = nil
local callCustomerPrompt = nil
local callShinerPrompt = nil
local pickupPrompt = nil


local PromptPlacerGroup = GetRandomIntInRange(0, 0xffffff)
local CancelPrompt = nil
local SetPrompt = nil
local RotateLeftPrompt = nil
local RotateRightPrompt = nil
local PitchUpPrompt = nil
local PitchDownPrompt = nil
local RollLeftPrompt = nil
local RollRightPrompt = nil
local placerConfirmed = false
local placerHeading = 0.0
local placerPitch = 0.0
local placerRoll = 0.0



local function HasShoeShinerJob()
    if not Config.RequireJob then
        return true
    end
    
    local PlayerData = RSGCore.Functions.GetPlayerData()
    if PlayerData and PlayerData.job then
        local requiredJob = Config.JobName or 'shoeshiner'
        return PlayerData.job.name == requiredJob
    end
    return false
end

local function IsPedUsingScenario(ped, scenarioName)
    if not DoesEntityExist(ped) then return false end
    return IsPedUsingAnyScenario(ped)
end

local function LoadModel(model)
    local modelHash = model
    if type(model) == 'string' then
        modelHash = joaat(model)
    end
    
    if not IsModelValid(modelHash) then
        
        return false
    end
    
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = 0
        while not HasModelLoaded(modelHash) and timeout < 5000 do
            Wait(10)
            timeout = timeout + 10
        end
    end
    
    if HasModelLoaded(modelHash) then
        return true
    else
        
        return false
    end
end

local function GetGroundZ(x, y, z)
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 10.0, false)
    if found then
        return groundZ
    end
    return z
end

local function GetPositionRelativeToEntity(entity, offsetX, offsetY, offsetZ, offsetHeading)
    local objectHeading = GetEntityHeading(entity)
    local objectCoords = GetEntityCoords(entity)
    
    local r = math.rad(objectHeading)
    local cosr = math.cos(r)
    local sinr = math.sin(r)
    
    local x = offsetX * cosr - offsetY * sinr + objectCoords.x
    local y = offsetY * cosr + offsetX * sinr + objectCoords.y
    local z = offsetZ + objectCoords.z
    local h = offsetHeading + objectHeading
    
    return x, y, z, h
end


local function GetPositionRelativeToCoords(baseCoords, baseHeading, offsetX, offsetY, offsetZ, offsetHeading)
    local r = math.rad(baseHeading)
    local cosr = math.cos(r)
    local sinr = math.sin(r)
    
    local x = offsetX * cosr - offsetY * sinr + baseCoords.x
    local y = offsetY * cosr + offsetX * sinr + baseCoords.y
    local z = offsetZ + baseCoords.z
    local h = (offsetHeading + baseHeading) % 360
    
    return x, y, z, h
end

local function PlayScenarioAtPosition(ped, scenario, x, y, z, heading)
    if not DoesEntityExist(ped) then return end
    
    ClearPedTasksImmediately(ped)
    Wait(100)
    
    TaskStartScenarioAtPosition(ped, joaat(scenario), x, y, z, heading, -1, false, true, false)
end

local function StopScenario(ped)
    if not DoesEntityExist(ped) then return end
    ClearPedTasks(ped)
end

local function FindNearbyNPCForShining(coords, radius)
    local nearbyPeds = {}
    local handle, ped = FindFirstPed()
    local success
    local myPed = PlayerPedId()
    
    repeat
        if ped ~= myPed and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) then
            local pedCoords = GetEntityCoords(ped)
            local distance = #(coords - pedCoords)
            
            if distance < radius then
                local alreadyUsed = false
                for _, queuedPed in pairs(queuedNPCs) do
                    if queuedPed == ped then
                        alreadyUsed = true
                        break
                    end
                end
                
                if not alreadyUsed and ped ~= autoShinerNPC then
                    table.insert(nearbyPeds, {ped = ped, distance = distance})
                end
            end
        end
        success, ped = FindNextPed(handle)
    until not success
    EndFindPed(handle)
    
    if #nearbyPeds > 0 then
        table.sort(nearbyPeds, function(a, b) return a.distance < b.distance end)
        return nearbyPeds[1].ped
    end
    
    return nil
end



local function SetupPlacerPrompts()
    CancelPrompt = PromptRegisterBegin()
    PromptSetControlAction(CancelPrompt, 0xF84FA74F)
    PromptSetText(CancelPrompt, CreateVarString(10, 'LITERAL_STRING', Config.PropPlacer.PromptCancelName))
    PromptSetEnabled(CancelPrompt, true)
    PromptSetVisible(CancelPrompt, true)
    PromptSetHoldMode(CancelPrompt, true)
    PromptSetGroup(CancelPrompt, PromptPlacerGroup)
    PromptRegisterEnd(CancelPrompt)
    
    SetPrompt = PromptRegisterBegin()
    PromptSetControlAction(SetPrompt, 0xC7B5340A)
    PromptSetText(SetPrompt, CreateVarString(10, 'LITERAL_STRING', Config.PropPlacer.PromptPlaceName))
    PromptSetEnabled(SetPrompt, true)
    PromptSetVisible(SetPrompt, true)
    PromptSetHoldMode(SetPrompt, true)
    PromptSetGroup(SetPrompt, PromptPlacerGroup)
    PromptRegisterEnd(SetPrompt)
    
    RotateLeftPrompt = PromptRegisterBegin()
    PromptSetControlAction(RotateLeftPrompt, 0xA65EBAB4)
    PromptSetText(RotateLeftPrompt, CreateVarString(10, 'LITERAL_STRING', Config.PropPlacer.PromptRotateLeft))
    PromptSetEnabled(RotateLeftPrompt, true)
    PromptSetVisible(RotateLeftPrompt, true)
    PromptSetHoldMode(RotateLeftPrompt, true)
    PromptSetGroup(RotateLeftPrompt, PromptPlacerGroup)
    PromptRegisterEnd(RotateLeftPrompt)
    
    RotateRightPrompt = PromptRegisterBegin()
    PromptSetControlAction(RotateRightPrompt, 0xDEB34313)
    PromptSetText(RotateRightPrompt, CreateVarString(10, 'LITERAL_STRING', Config.PropPlacer.PromptRotateRight))
    PromptSetEnabled(RotateRightPrompt, true)
    PromptSetVisible(RotateRightPrompt, true)
    PromptSetHoldMode(RotateRightPrompt, true)
    PromptSetGroup(RotateRightPrompt, PromptPlacerGroup)
    PromptRegisterEnd(RotateRightPrompt)
    
    PitchUpPrompt = PromptRegisterBegin()
    PromptSetControlAction(PitchUpPrompt, 0x6319DB71)
    PromptSetText(PitchUpPrompt, CreateVarString(10, 'LITERAL_STRING', Config.PropPlacer.PromptPitchUp))
    PromptSetEnabled(PitchUpPrompt, true)
    PromptSetVisible(PitchUpPrompt, true)
    PromptSetHoldMode(PitchUpPrompt, true)
    PromptSetGroup(PitchUpPrompt, PromptPlacerGroup)
    PromptRegisterEnd(PitchUpPrompt)
    
    PitchDownPrompt = PromptRegisterBegin()
    PromptSetControlAction(PitchDownPrompt, 0x05CA7C52)
    PromptSetText(PitchDownPrompt, CreateVarString(10, 'LITERAL_STRING', Config.PropPlacer.PromptPitchDown))
    PromptSetEnabled(PitchDownPrompt, true)
    PromptSetVisible(PitchDownPrompt, true)
    PromptSetHoldMode(PitchDownPrompt, true)
    PromptSetGroup(PitchDownPrompt, PromptPlacerGroup)
    PromptRegisterEnd(PitchDownPrompt)
    
    RollLeftPrompt = PromptRegisterBegin()
    PromptSetControlAction(RollLeftPrompt, 0xF1E9A8D7)
    PromptSetText(RollLeftPrompt, CreateVarString(10, 'LITERAL_STRING', Config.PropPlacer.PromptRollLeft))
    PromptSetEnabled(RollLeftPrompt, true)
    PromptSetVisible(RollLeftPrompt, true)
    PromptSetHoldMode(RollLeftPrompt, true)
    PromptSetGroup(RollLeftPrompt, PromptPlacerGroup)
    PromptRegisterEnd(RollLeftPrompt)
    
    RollRightPrompt = PromptRegisterBegin()
    PromptSetControlAction(RollRightPrompt, 0xE764D794)
    PromptSetText(RollRightPrompt, CreateVarString(10, 'LITERAL_STRING', Config.PropPlacer.PromptRollRight))
    PromptSetEnabled(RollRightPrompt, true)
    PromptSetVisible(RollRightPrompt, true)
    PromptSetHoldMode(RollRightPrompt, true)
    PromptSetGroup(RollRightPrompt, PromptPlacerGroup)
    PromptRegisterEnd(RollRightPrompt)
end

local function RotationToDirection(rotation)
    local adjustedRotation = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z
    }
    local direction = {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
    return direction
end

local function RayCastGamePlayCamera(distance)
    local cameraRotation = GetGameplayCamRot()
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination = {
        x = cameraCoord.x + direction.x * distance,
        y = cameraCoord.y + direction.y * distance,
        z = cameraCoord.z + direction.z * distance
    }
    local rayHandle = StartShapeTestRay(cameraCoord.x, cameraCoord.y, cameraCoord.z, destination.x, destination.y, destination.z, 1 + 2 + 4 + 8 + 16, PlayerPedId(), 0)
    local _, hit, coords, surfaceNormal, entity = GetShapeTestResult(rayHandle)
    return hit, coords, surfaceNormal, entity
end

local function GetSurfaceType(surfaceNormal)
    if surfaceNormal.z > 0.7 then
        return "Floor"
    elseif surfaceNormal.z < -0.7 then
        return "Ceiling"
    else
        return "Wall"
    end
end

local function AlignPropToSurface(prop, surfaceNormal, coords, entity)
    local propThickness = 0.01
    local offsetDistance = propThickness
    
    if DoesEntityExist(entity) and entity ~= 0 then
        local entityType = GetEntityType(entity)
        if entityType == 2 or entityType == 3 then
            local forward, right, up, _ = GetEntityMatrix(entity)
            surfaceNormal = up
        end
    end
    
    local offsetCoords = vector3(
        coords.x + (surfaceNormal.x * offsetDistance),
        coords.y + (surfaceNormal.y * offsetDistance),
        coords.z + (surfaceNormal.z * offsetDistance)
    )
    
    SetEntityCoordsNoOffset(prop, offsetCoords.x, offsetCoords.y, offsetCoords.z, false, false, false, true)
    SetEntityRotation(prop, placerPitch, placerRoll, placerHeading, 2, false)
end

local function PropPlacer(callback)
    local PropHash = joaat(Config.StandModel)
    placerHeading = 0.0
    placerPitch = 0.0
    placerRoll = 0.0
    placerConfirmed = false
    isPlacingStand = true
    
    if not LoadModel(PropHash) then
        lib.notify({
            title = 'Shoe Shine',
            description = 'Failed to load stand model!',
            type = 'error'
        })
        isPlacingStand = false
        return
    end
    
    SetCurrentPedWeapon(PlayerPedId(), GetHashKey("WEAPON_UNARMED"), true)
    
    local hit, coords, surfaceNormal, entity
    local timeout = 0
    while not hit and timeout < 100 do
        hit, coords, surfaceNormal, entity = RayCastGamePlayCamera(1000.0)
        Wait(10)
        timeout = timeout + 1
    end
    
    if not hit then
        lib.notify({
            title = 'Shoe Shine',
            description = 'Could not find a surface!',
            type = 'error'
        })
        SetModelAsNoLongerNeeded(PropHash)
        isPlacingStand = false
        return
    end
    
    local tempObj = CreateObject(PropHash, coords.x, coords.y, coords.z, false, false, true)
    
    if not DoesEntityExist(tempObj) then
        lib.notify({
            title = 'Shoe Shine',
            description = 'Failed to create preview!',
            type = 'error'
        })
        SetModelAsNoLongerNeeded(PropHash)
        isPlacingStand = false
        return
    end
    
    if EagleEyeSetCustomEntityTint then
        EagleEyeSetCustomEntityTint(tempObj, 255, 255, 0)
    end
    
    CreateThread(function()
        while not placerConfirmed and isPlacingStand do
            hit, coords, surfaceNormal, entity = RayCastGamePlayCamera(1000.0)
            
            if hit then
                AlignPropToSurface(tempObj, surfaceNormal, coords, entity)
                FreezeEntityPosition(tempObj, true)
                SetEntityCollision(tempObj, false, false)
                SetEntityAlpha(tempObj, 150, false)
                
                local rotationInfo = string.format("Heading: %.1f | Pitch: %.1f | Roll: %.1f", placerHeading, placerPitch, placerRoll)
                SetTextScale(0.3, 0.3)
                SetTextColor(255, 255, 255, 255)
                SetTextCentre(true)
                SetTextDropshadow(1, 0, 0, 0, 255)
                DisplayText(CreateVarString(10, "LITERAL_STRING", rotationInfo), 0.5, 0.08)
                
                local surfaceType = GetSurfaceType(surfaceNormal)
                SetTextScale(0.35, 0.35)
                SetTextColor(255, 255, 255, 255)
                SetTextCentre(true)
                SetTextDropshadow(1, 0, 0, 0, 255)
                DisplayText(CreateVarString(10, "LITERAL_STRING", "Surface: " .. surfaceType), 0.5, 0.05)
            end
            
            Wait(0)
            
            local PropPlacerGroupName = CreateVarString(10, 'LITERAL_STRING', Config.PropPlacer.PromptGroupName)
            PromptSetActiveGroupThisFrame(PromptPlacerGroup, PropPlacerGroupName)
            
            local rotationSpeed = 2.0
            
            if IsControlPressed(1, 0xA65EBAB4) then
                placerHeading = placerHeading + rotationSpeed
            elseif IsControlPressed(1, 0xDEB34313) then
                placerHeading = placerHeading - rotationSpeed
            end
            
            if IsControlPressed(1, 0x6319DB71) then
                placerPitch = placerPitch + rotationSpeed
            elseif IsControlPressed(1, 0x05CA7C52) then
                placerPitch = placerPitch - rotationSpeed
            end
            
            if IsControlPressed(1, 0xF1E9A8D7) then
                placerRoll = placerRoll + rotationSpeed
            elseif IsControlPressed(1, 0xE764D794) then
                placerRoll = placerRoll - rotationSpeed
            end
            
            if placerHeading > 360.0 then placerHeading = placerHeading - 360.0 end
            if placerHeading < 0.0 then placerHeading = placerHeading + 360.0 end
            if placerPitch > 360.0 then placerPitch = placerPitch - 360.0 end
            if placerPitch < 0.0 then placerPitch = placerPitch + 360.0 end
            if placerRoll > 360.0 then placerRoll = placerRoll - 360.0 end
            if placerRoll < 0.0 then placerRoll = placerRoll + 360.0 end
            
            if PromptHasHoldModeCompleted(SetPrompt) then
                placerConfirmed = true
                local finalCoords = GetEntityCoords(tempObj)
                local finalHeading = placerHeading
                
                DeleteObject(tempObj)
                SetModelAsNoLongerNeeded(PropHash)
                isPlacingStand = false
                
                if callback then
                    callback(true, finalCoords, finalHeading)
                end
                break
            end
            
            if PromptHasHoldModeCompleted(CancelPrompt) then
                DeleteObject(tempObj)
                SetModelAsNoLongerNeeded(PropHash)
                isPlacingStand = false
                
                if callback then
                    callback(false, nil, nil)
                end
                break
            end
        end
    end)
end



local function CreatePrompt(text, key, holdMode)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, key)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', text))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    PromptSetGroup(prompt, promptGroup)
    
    if holdMode then
        PromptSetHoldMode(prompt, true)
    else
        PromptSetStandardMode(prompt, true)
    end
    
    PromptRegisterEnd(prompt)
    
    return prompt
end

local function SetupPrompts()
    sitPrompt = CreatePrompt('Sit on Stand', 0xCEFD9220, true)
    local shineText = 'Shine Shoes ($' .. tostring(Config.ShinePrice or 5) .. ')'
    shinePrompt = CreatePrompt(shineText, 0xCEFD9220, true)
    standUpPrompt = CreatePrompt('Stand Up', 0x156F7119, false)
    local shinerCost = Config.AutoNPCShiner and Config.AutoNPCShiner.cost or 3
    callShinerPrompt = CreatePrompt('Call Shoe Shiner ($' .. shinerCost .. ')', 0x760A9C6F, true)
    callCustomerPrompt = CreatePrompt('Call Customer', 0x7F7E5A78, true)
    pickupPrompt = CreatePrompt('Pickup Stand', 0xF3830D8E, true)
    
    SetupPlacerPrompts()
    
    
end

local function ShowPromptGroup(text)
    PromptSetActiveGroupThisFrame(promptGroup, CreateVarString(10, 'LITERAL_STRING', text))
end

local function HideAllPrompts()
    if sitPrompt then PromptSetEnabled(sitPrompt, false) end
    if shinePrompt then PromptSetEnabled(shinePrompt, false) end
    if standUpPrompt then PromptSetEnabled(standUpPrompt, false) end
    if callShinerPrompt then PromptSetEnabled(callShinerPrompt, false) end
    if callCustomerPrompt then PromptSetEnabled(callCustomerPrompt, false) end
    if pickupPrompt then PromptSetEnabled(pickupPrompt, false) end
end

local function ShowPrompt(prompt)
    if prompt then
        PromptSetEnabled(prompt, true)
        PromptSetVisible(prompt, true)
    end
end



local function CleanupAutoShiner()
    if autoShinerNPC and DoesEntityExist(autoShinerNPC) then
        ClearPedTasks(autoShinerNPC)
        FreezeEntityPosition(autoShinerNPC, false)
        
        local npcCoords = GetEntityCoords(autoShinerNPC)
        local randomX = npcCoords.x + math.random(-20, 20)
        local randomY = npcCoords.y + math.random(-20, 20)
        TaskGoToCoordAnyMeans(autoShinerNPC, randomX, randomY, npcCoords.z, 1.0, 0, false, 786603, 0xbf800000)
    end
    
    autoShinerNPC = nil
    autoShinerActive = false
    isBeingShined = false
    pendingShinerNPC = nil
end

local function CallNPCShiner()
    
    
    if not isSitting or not currentStand then 
       
        return 
    end
    
    if autoShinerActive or isBeingShined then 
        
        return 
    end

    local standCoords = GetEntityCoords(currentStand.entity)
    local searchRadius = Config.AutoNPCShiner and Config.AutoNPCShiner.npcSearchRadius or 50.0
    local npc = FindNearbyNPCForShining(standCoords, searchRadius)

    if not npc then
        
        lib.notify({ title = 'Shoe Shine', description = 'No shoe shiners nearby!', type = 'error' })
        return
    end

    
    
    
    pendingShinerNPC = npc
    autoShinerActive = true
    
    local cost = Config.AutoNPCShiner and Config.AutoNPCShiner.cost or 3
    

   
    TriggerServerEvent('shoeshine:server:payForNPCShineNow', cost)
end

RegisterNetEvent('shoeshine:client:npcShinePaymentResult', function(success, cost)
    
    
    if not success then
       
        autoShinerActive = false
        pendingShinerNPC = nil
        lib.notify({
            title = 'Shoe Shine',
            description = 'You don\'t have enough money! ($' .. cost .. ' required)',
            type = 'error'
        })
        return
    end
    
    
    
    if not isSitting or not currentStand then 
        
        autoShinerActive = false
        pendingShinerNPC = nil
        TriggerServerEvent('shoeshine:server:refundNPCShine', cost)
        return 
    end
    
    
    local npc = pendingShinerNPC
    pendingShinerNPC = nil
    
    if not npc or not DoesEntityExist(npc) then
       
        autoShinerActive = false
        TriggerServerEvent('shoeshine:server:refundNPCShine', cost)
        lib.notify({
            title = 'Shoe Shine',
            description = 'Shoe shiner no longer available! Money refunded.',
            type = 'error'
        })
        return
    end
    
    
    
    autoShinerNPC = npc
    isBeingShined = true
    
    lib.notify({
        title = 'Shoe Shine',
        description = 'Paid $' .. cost .. ' - A shoe shiner is coming!',
        type = 'success'
    })
    
    local shinerOffsetX = Config.ShinerOffset and Config.ShinerOffset.x or 0.0
    local shinerOffsetY = Config.ShinerOffset and Config.ShinerOffset.y or 1.0
    local shinerOffsetZ = Config.ShinerOffset and Config.ShinerOffset.z or 0.0
    local shinerOffsetHeading = Config.ShinerOffset and Config.ShinerOffset.heading or 0.0
    
    local targetX, targetY, targetZ, targetHeading = GetPositionRelativeToEntity(
        currentStand.entity,
        shinerOffsetX,
        shinerOffsetY,
        shinerOffsetZ,
        shinerOffsetHeading
    )
    
    
    TaskGoToCoordAnyMeans(npc, targetX, targetY, targetZ, 1.0, 0, false, 786603, 0xbf800000)
    
    CreateThread(function()
        local timeout = 30000
        local startTime = GetGameTimer()
        local shineDuration = Config.ShineDuration or 10000
        
        while DoesEntityExist(npc) and autoShinerActive and isSitting do
            Wait(500)
            
            local npcCoords = GetEntityCoords(npc)
            local distance = #(npcCoords - vector3(targetX, targetY, targetZ))
            
            
            
            if distance < 1.5 then
               
                
                SetEntityCoords(npc, targetX, targetY, targetZ, false, false, false, true)
                SetEntityHeading(npc, targetHeading)
                
                Wait(100)
                
                ClearPedTasksImmediately(npc)
                local shinerScenario = Config.Scenarios and Config.Scenarios.shiner or "WORLD_HUMAN_CROUCH_INSPECT"
                TaskStartScenarioInPlace(npc, joaat(shinerScenario), -1, true, false, false, false)
                
                lib.notify({
                    title = 'Shoe Shine',
                    description = 'Your shoes are being shined!',
                    type = 'inform'
                })
                
               
                
                -- Progress bar
                local finished = lib.progressBar({
                    duration = shineDuration,
                    label = 'Getting shoes shined...',
                    useWhileDead = false,
                    canCancel = true,
                    disable = {
                        move = true,
                        car = true,
                        combat = true,
                    },
                })
                
                
                
                if finished then
                    lib.notify({
                        title = 'Shoe Shine',
                        description = 'Your shoes are sparkling clean!',
                        type = 'success'
                    })
                else
                    lib.notify({
                        title = 'Shoe Shine',
                        description = 'Shoe shine cancelled.',
                        type = 'error'
                    })
                end
                
                CleanupAutoShiner()
                return
            end
            
            if GetGameTimer() - startTime > timeout then
                
                TriggerServerEvent('shoeshine:server:refundNPCShine', cost)
                lib.notify({
                    title = 'Shoe Shine',
                    description = 'Shoe shiner took too long. Money refunded.',
                    type = 'error'
                })
                CleanupAutoShiner()
                return
            end
            
            if not isSitting then
                
                CleanupAutoShiner()
                return
            end
        end
        
        CleanupAutoShiner()
    end)
end)



local function CallNearbyCustomer()
    if not HasShoeShinerJob() then
        lib.notify({
            title = 'Shoe Shine',
            description = 'You need to be a shoe shiner to do this!',
            type = 'error'
        })
        return
    end
    
    if isCallingCustomer then return end
    
    local maxQueue = Config.MaxNPCQueue or 3
    
    if #queuedNPCs >= maxQueue then
        lib.notify({
            title = 'Shoe Shine',
            description = 'Too many customers waiting!',
            type = 'error'
        })
        return
    end
    
    if not currentStand then
        lib.notify({
            title = 'Shoe Shine',
            description = 'You need to be near your stand!',
            type = 'error'
        })
        return
    end
    
    isCallingCustomer = true
    
    local standCoords = GetEntityCoords(currentStand.entity)
    local npcWalkDistance = Config.NPCWalkDistance or 30.0
    
    local nearbyPeds = {}
    local handle, ped = FindFirstPed()
    local success
    local myPed = PlayerPedId()
    
    repeat
        if ped ~= myPed and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) then
            local pedCoords = GetEntityCoords(ped)
            local distance = #(standCoords - pedCoords)
            
            if distance < npcWalkDistance then
                local alreadyQueued = false
                for _, queuedPed in pairs(queuedNPCs) do
                    if queuedPed == ped then
                        alreadyQueued = true
                        break
                    end
                end
                
                if not alreadyQueued and ped ~= autoShinerNPC then
                    table.insert(nearbyPeds, {ped = ped, distance = distance})
                end
            end
        end
        success, ped = FindNextPed(handle)
    until not success
    EndFindPed(handle)
    
    if #nearbyPeds == 0 then
        isCallingCustomer = false
        lib.notify({
            title = 'Shoe Shine',
            description = 'No customers nearby!',
            type = 'error'
        })
        return
    end
    
    table.sort(nearbyPeds, function(a, b) return a.distance < b.distance end)
    
    local selectedNPC = nearbyPeds[1].ped
    table.insert(queuedNPCs, selectedNPC)
    
    local sitOffsetX = Config.SitOffset and Config.SitOffset.x or 0.0
    local sitOffsetY = Config.SitOffset and Config.SitOffset.y or 0.0
    local sitOffsetZ = Config.SitOffset and Config.SitOffset.z or 0.45
    local sitOffsetHeading = Config.SitOffset and Config.SitOffset.heading or 180.0
    
    local targetX, targetY, targetZ, targetHeading = GetPositionRelativeToEntity(
        currentStand.entity,
        sitOffsetX,
        sitOffsetY,
        sitOffsetZ,
        sitOffsetHeading
    )
    
    local foundGround, groundZ = GetGroundZFor_3dCoord(targetX, targetY, targetZ + 5.0, false)
    if foundGround then
        targetZ = groundZ + (Config.SitOffset and Config.SitOffset.z or 0.45)
    end
    
    local standEntity = currentStand.entity
    
    SetEntityAsMissionEntity(selectedNPC, true, true)
    SetBlockingOfNonTemporaryEvents(selectedNPC, true)
    SetPedKeepTask(selectedNPC, true)
    
    TaskGoToCoordAnyMeans(selectedNPC, targetX, targetY, groundZ or targetZ, 1.0, 0, false, 786603, 0xbf800000)
    
    lib.notify({
        title = 'Shoe Shine',
        description = 'A customer is coming!',
        type = 'success'
    })
    
    SetTimeout(2000, function()
        isCallingCustomer = false
    end)
    
    CreateThread(function()
        local timeout = 30000
        local startTime = GetGameTimer()
        local hasSeated = false
        
        while DoesEntityExist(selectedNPC) do
            Wait(500)
            
            local stillQueued = false
            for _, qPed in pairs(queuedNPCs) do
                if qPed == selectedNPC then
                    stillQueued = true
                    break
                end
            end
            
            if not stillQueued then
                return
            end
            
            local npcCoords = GetEntityCoords(selectedNPC)
            local distance2D = #(vector2(npcCoords.x, npcCoords.y) - vector2(targetX, targetY))
            
            if distance2D < 1.5 and not hasSeated then
                hasSeated = true
                
                ClearPedTasksImmediately(selectedNPC)
                Wait(100)
                
                SetEntityCoords(selectedNPC, targetX, targetY, targetZ, false, false, false, true)
                SetEntityHeading(selectedNPC, targetHeading)
                
                Wait(100)
                
                FreezeEntityPosition(selectedNPC, true)
                SetBlockingOfNonTemporaryEvents(selectedNPC, true)
                SetPedKeepTask(selectedNPC, true)
                
                local sitScenario = Config.Scenarios and Config.Scenarios.sit or "PROP_HUMAN_SEAT_BENCH"
                TaskStartScenarioInPlace(selectedNPC, joaat(sitScenario), -1, true, false, false, false)
                
                lib.notify({
                    title = 'Shoe Shine',
                    description = 'Customer seated! Approach and shine their shoes.',
                    type = 'inform'
                })
                
                CreateThread(function()
                    while DoesEntityExist(selectedNPC) do
                        Wait(1000)
                        
                        local inQueue = false
                        for _, qPed in pairs(queuedNPCs) do
                            if qPed == selectedNPC then
                                inQueue = true
                                break
                            end
                        end
                        
                        if not inQueue then
                            return
                        end
                        
                        FreezeEntityPosition(selectedNPC, true)
                        SetBlockingOfNonTemporaryEvents(selectedNPC, true)
                    end
                end)
                
                return
            end
            
            if GetGameTimer() - startTime > timeout then
                for i, qPed in pairs(queuedNPCs) do
                    if qPed == selectedNPC then
                        table.remove(queuedNPCs, i)
                        break
                    end
                end
                
                SetBlockingOfNonTemporaryEvents(selectedNPC, false)
                SetPedKeepTask(selectedNPC, false)
                SetEntityAsMissionEntity(selectedNPC, false, true)
                FreezeEntityPosition(selectedNPC, false)
                
                lib.notify({
                    title = 'Shoe Shine',
                    description = 'Customer gave up waiting.',
                    type = 'error'
                })
                return
            end
        end
    end)
end

local function ShineNPCShoes(npc)
    if not HasShoeShinerJob() then
        lib.notify({
            title = 'Shoe Shine',
            description = 'You need to be a shoe shiner to do this!',
            type = 'error'
        })
        return
    end
    
    if isShining then return end
    if not DoesEntityExist(npc) then return end
    
    isShining = true
    local playerPed = PlayerPedId()
    local npcCoords = GetEntityCoords(npc)
    local shineDuration = Config.ShineDuration or 10000
    local npcPayAmount = Config.NPCPayAmount or 10
    
    local targetStand = nil
    
    for _, standData in pairs(placedStands) do
        if standData and standData.entity and DoesEntityExist(standData.entity) then
            local standCoords = GetEntityCoords(standData.entity)
            if #(npcCoords - standCoords) < 5.0 then
                targetStand = standData
                break
            end
        end
    end
    
    if not targetStand then
        for _, standData in pairs(worldStands) do
            if standData and standData.entity and DoesEntityExist(standData.entity) then
                local standCoords = GetEntityCoords(standData.entity)
                if #(npcCoords - standCoords) < 5.0 then
                    targetStand = standData
                    break
                end
            end
        end
    end
    
    if not targetStand then
        isShining = false
        lib.notify({
            title = 'Shoe Shine',
            description = 'Cannot find stand!',
            type = 'error'
        })
        return
    end
    
    local shinerOffsetX = Config.ShinerOffset and Config.ShinerOffset.x or 0.0
    local shinerOffsetY = Config.ShinerOffset and Config.ShinerOffset.y or 1.0
    local shinerOffsetZ = Config.ShinerOffset and Config.ShinerOffset.z or 0.0
    local shinerOffsetHeading = Config.ShinerOffset and Config.ShinerOffset.heading or 0.0
    
    local shinerX, shinerY, shinerZ, shinerHeading = GetPositionRelativeToEntity(
        targetStand.entity,
        shinerOffsetX,
        shinerOffsetY,
        shinerOffsetZ,
        shinerOffsetHeading
    )
    
    local foundGround, groundZ = GetGroundZFor_3dCoord(shinerX, shinerY, shinerZ + 5.0, false)
    if foundGround then
        shinerZ = groundZ
    end
    
    ClearPedTasksImmediately(playerPed)
    SetEntityCoords(playerPed, shinerX, shinerY, shinerZ, false, false, false, true)
    SetEntityHeading(playerPed, shinerHeading)
    
    Wait(200)
    
    local shinerScenario = Config.Scenarios and Config.Scenarios.shiner or "WORLD_HUMAN_CROUCH_INSPECT"
    TaskStartScenarioInPlace(playerPed, joaat(shinerScenario), -1, true, false, false, false)
    
    local finished = lib.progressBar({
        duration = shineDuration,
        label = 'Shining Shoes...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
    })
    
    if finished then
        ClearPedTasks(playerPed)
        isShining = false
        
        for i, qPed in pairs(queuedNPCs) do
            if qPed == npc then
                table.remove(queuedNPCs, i)
                break
            end
        end
        
        if DoesEntityExist(npc) then
            ClearPedTasks(npc)
            FreezeEntityPosition(npc, false)
            SetBlockingOfNonTemporaryEvents(npc, false)
            SetPedKeepTask(npc, false)
            SetEntityAsMissionEntity(npc, false, true)
            
            local randomX = npcCoords.x + math.random(-20, 20)
            local randomY = npcCoords.y + math.random(-20, 20)
            TaskGoToCoordAnyMeans(npc, randomX, randomY, npcCoords.z, 1.0, 0, false, 786603, 0xbf800000)
        end
        
        TriggerServerEvent('shoeshine:server:npcPayment')
        
        lib.notify({
            title = 'Shoe Shine',
            description = 'NPC paid you $' .. npcPayAmount .. '!',
            type = 'success'
        })
    else
        ClearPedTasks(playerPed)
        isShining = false
        
        lib.notify({
            title = 'Shoe Shine',
            description = 'Cancelled shoe shine.',
            type = 'error'
        })
    end
end


local function PlaceStand()
    if not HasShoeShinerJob() then
        lib.notify({
            title = 'Shoe Shine',
            description = 'You need to be a shoe shiner to do this!',
            type = 'error'
        })
        return
    end
    
    if isPlacingStand then return end
    
    PropPlacer(function(success, coords, heading)
        if not success then
            lib.notify({
                title = 'Shoe Shine',
                description = 'Stand placement cancelled.',
                type = 'inform'
            })
            return
        end
        
        local modelHash = joaat(Config.StandModel)
        
        if not LoadModel(modelHash) then
            lib.notify({
                title = 'Shoe Shine',
                description = 'Failed to load stand model!',
                type = 'error'
            })
            return
        end
        
        local stand = CreateObject(modelHash, coords.x, coords.y, coords.z, true, true, true)
        
        if not DoesEntityExist(stand) then
            lib.notify({
                title = 'Shoe Shine',
                description = 'Failed to create stand!',
                type = 'error'
            })
            SetModelAsNoLongerNeeded(modelHash)
            return
        end
        
        SetEntityHeading(stand, heading)
        PlaceObjectOnGroundProperly(stand)
        FreezeEntityPosition(stand, true)
        SetEntityCollision(stand, true, true)
        
        local timeout = 0
        while not NetworkGetEntityIsNetworked(stand) and timeout < 1000 do
            NetworkRegisterEntityAsNetworked(stand)
            Wait(10)
            timeout = timeout + 10
        end
        
        local netId = 0
        if NetworkGetEntityIsNetworked(stand) then
            netId = NetworkGetNetworkIdFromEntity(stand)
        end
        
        local standData = {
            entity = stand,
            coords = GetEntityCoords(stand),
            heading = heading,
            owner = GetPlayerServerId(PlayerId()),
            occupied = false,
            sittingPlayer = nil,
            isWorldStand = false
        }
        
        table.insert(placedStands, standData)
        currentStand = standData
        
        TriggerServerEvent('shoeshine:server:syncStand', {
            coords = standData.coords,
            heading = standData.heading,
            netId = netId
        })
        
        lib.notify({
            title = 'Shoe Shine',
            description = 'Stand placed successfully!',
            type = 'success'
        })
        
        SetModelAsNoLongerNeeded(modelHash)
    end)
end

local function SitOnStand(standData)
    if isSitting or isShining then return end
    
    local playerPed = PlayerPedId()
    
    if not StartingCoords then
        StartingCoords = GetEntityCoords(playerPed)
    end
    
    isSitting = true
    currentStand = standData
    standData.occupied = true
    standData.sittingPlayer = GetPlayerServerId(PlayerId())
    
    TriggerServerEvent('shoeshine:server:playerSat', standData.coords)
    
    local offsetX = Config.SitOffset and Config.SitOffset.x or 0.0
    local offsetY = Config.SitOffset and Config.SitOffset.y or 0.0
    local offsetZ = Config.SitOffset and Config.SitOffset.z or 0.5
    local offsetHeading = Config.SitOffset and Config.SitOffset.heading or 180.0
    
    local sitX, sitY, sitZ, sitHeading = GetPositionRelativeToEntity(
        standData.entity,
        offsetX,
        offsetY,
        offsetZ,
        offsetHeading
    )
    
    ClearPedTasksImmediately(playerPed)
    FreezeEntityPosition(playerPed, true)
    
    local sitScenario = Config.Scenarios and Config.Scenarios.sit or "MP_LOBBY_PROP_HUMAN_SEAT_CHAIR_WHITTLE"
    PlayScenarioAtPosition(playerPed, sitScenario, sitX, sitY, sitZ, sitHeading)
    
    lib.notify({
        title = 'Shoe Shine',
        description = 'You sat down. Press G to call a shoe shiner!',
        type = 'inform'
    })
end

local function StandUp()
    if not isSitting then return end
    
    CleanupAutoShiner()
    
    local playerPed = PlayerPedId()
    
    ClearPedTasks(playerPed)
    FreezeEntityPosition(playerPed, false)
    
    if StartingCoords then
        local currentCoords = GetEntityCoords(playerPed)
        local distance = #(currentCoords - StartingCoords)
        
        if distance > 0.4 then
            TaskGoToCoordAnyMeans(playerPed, StartingCoords.x, StartingCoords.y, StartingCoords.z, 1.0, 0, false, 786603, 0xbf800000)
            Wait(1000)
        end
        
        SetEntityCoordsNoOffset(playerPed, StartingCoords.x, StartingCoords.y, StartingCoords.z)
        StartingCoords = nil
    end
    
    if currentStand then
        currentStand.occupied = false
        currentStand.sittingPlayer = nil
        TriggerServerEvent('shoeshine:server:playerStood', currentStand.coords)
    end
    
    isSitting = false
    currentStand = nil
    
    lib.notify({
        title = 'Shoe Shine',
        description = 'You stood up.',
        type = 'inform'
    })
end

local function ShineShoes(standData, targetServerId)
    if not HasShoeShinerJob() then
        lib.notify({
            title = 'Shoe Shine',
            description = 'You need to be a shoe shiner to do this!',
            type = 'error'
        })
        return
    end
    
    if isShining then return end
    TriggerServerEvent('shoeshine:server:checkAndPay', targetServerId, standData.coords)
end

local function PickupStand(standData, index, isWorld)
    if not HasShoeShinerJob() then
        lib.notify({
            title = 'Shoe Shine',
            description = 'You need to be a shoe shiner to do this!',
            type = 'error'
        })
        return
    end
    
    if isWorld then
        lib.notify({
            title = 'Shoe Shine',
            description = 'You cannot pick up world stands!',
            type = 'error'
        })
        return
    end
    
    if standData.owner ~= GetPlayerServerId(PlayerId()) then
        lib.notify({
            title = 'Shoe Shine',
            description = 'This is not your stand!',
            type = 'error'
        })
        return
    end
    
    if standData.occupied then
        lib.notify({
            title = 'Shoe Shine',
            description = 'Someone is sitting on this stand!',
            type = 'error'
        })
        return
    end
    
    for i = #queuedNPCs, 1, -1 do
        local npc = queuedNPCs[i]
        if DoesEntityExist(npc) then
            ClearPedTasks(npc)
            FreezeEntityPosition(npc, false)
        end
        table.remove(queuedNPCs, i)
    end
    
    DeleteEntity(standData.entity)
    table.remove(placedStands, index)
    
    if currentStand and currentStand.entity == standData.entity then
        currentStand = nil
    end
    
    TriggerServerEvent('shoeshine:server:removeStand', standData.coords)
    
    lib.notify({
        title = 'Shoe Shine',
        description = 'Stand picked up!',
        type = 'success'
    })
end



RegisterNetEvent('shoeshine:client:performShine', function(standCoords)
    local playerPed = PlayerPedId()
    isShining = true
    
    local standData = nil
    
    for _, stand in pairs(placedStands) do
        if #(stand.coords - standCoords) < 1.0 then
            standData = stand
            break
        end
    end
    
    if not standData then
        for _, stand in pairs(worldStands) do
            if #(stand.coords - standCoords) < 1.0 then
                standData = stand
                break
            end
        end
    end
    
    if not standData then
        isShining = false
        return
    end
    
    local shinerOffsetX = Config.ShinerOffset and Config.ShinerOffset.x or 0.0
    local shinerOffsetY = Config.ShinerOffset and Config.ShinerOffset.y or 1.0
    local shinerOffsetZ = Config.ShinerOffset and Config.ShinerOffset.z or 0.0
    local shinerOffsetHeading = Config.ShinerOffset and Config.ShinerOffset.heading or 0.0
    
    local shinerX, shinerY, shinerZ, shinerHeading = GetPositionRelativeToEntity(
        standData.entity,
        shinerOffsetX,
        shinerOffsetY,
        shinerOffsetZ,
        shinerOffsetHeading
    )
    
    ClearPedTasksImmediately(playerPed)
    SetEntityCoords(playerPed, shinerX, shinerY, shinerZ, false, false, false, true)
    SetEntityHeading(playerPed, shinerHeading)
    
    Wait(100)
    
    local shinerScenario = Config.Scenarios and Config.Scenarios.shiner or "WORLD_HUMAN_CROUCH_INSPECT"
    TaskStartScenarioInPlace(playerPed, joaat(shinerScenario), -1, true, false, false, false)
    
    local shineDuration = Config.ShineDuration or 10000
    
    local finished = lib.progressBar({
        duration = shineDuration,
        label = 'Shining Shoes...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
    })
    
    if finished then
        ClearPedTasks(playerPed)
        isShining = false
        
        lib.notify({
            title = 'Shoe Shine',
            description = 'You finished shining the shoes!',
            type = 'success'
        })
    else
        ClearPedTasks(playerPed)
        isShining = false
        
        lib.notify({
            title = 'Shoe Shine',
            description = 'Cancelled shoe shine.',
            type = 'error'
        })
    end
end)

RegisterNetEvent('shoeshine:client:receiveShine', function()
    local shineDuration = Config.ShineDuration or 10000
    
    lib.notify({
        title = 'Shoe Shine',
        description = 'Your shoes are being shined!',
        type = 'inform'
    })
    
    Wait(shineDuration)
    
    lib.notify({
        title = 'Shoe Shine',
        description = 'Your shoes are now sparkling clean!',
        type = 'success'
    })
end)



local function OpenStandMenu()
    if not HasShoeShinerJob() then
        lib.notify({
            title = 'Shoe Shine',
            description = 'You need to be a shoe shiner to access this menu!',
            type = 'error'
        })
        return
    end
    
    local shinePrice = Config.ShinePrice or 5
    local shinerEarnings = Config.ShinerEarnings or 3
    local npcShinerCost = Config.AutoNPCShiner and Config.AutoNPCShiner.cost or 3
    local npcPayAmount = Config.NPCPayAmount or 10
    
    lib.registerContext({
        id = 'shoeshine_main_menu',
        title = 'Shoe Shine Stand',
        options = {
            {
                title = 'Place Stand',
                description = 'Place a shoe shine stand (with rotation controls)',
                icon = 'chair',
                onSelect = function()
                    PlaceStand()
                end
            },
            {
                title = 'Stand Information',
                description = 'View information about shoe shining',
                icon = 'info-circle',
                onSelect = function()
                    lib.registerContext({
                        id = 'shoeshine_info',
                        title = 'Shoe Shine Info',
                        menu = 'shoeshine_main_menu',
                        options = {
                            {
                                title = 'As a Customer',
                                description = '1. Sit on stand (yours or world stands)\n2. Press G to call a shoe shiner\n3. Pay $' .. npcShinerCost .. ' for service',
                                icon = 'user',
                            },
                            {
                                title = 'As a Shoe Shiner',
                                description = '1. Place your stand\n2. Press H to call customers\n3. Shine their shoes for $' .. npcPayAmount,
                                icon = 'briefcase',
                            },
                            {
                                title = 'Player to Player',
                                description = 'Customer pays: $' .. shinePrice .. '\nShiner earns: $' .. shinerEarnings,
                                icon = 'users',
                            },
                        }
                    })
                    lib.showContext('shoeshine_info')
                end
            },
        }
    })
    lib.showContext('shoeshine_main_menu')
end

RegisterCommand('shoeshine', function()
    OpenStandMenu()
end, false)


CreateThread(function()
    Wait(1000)
    SetupPrompts()
    
    while true do
        local sleep = 1000
        local currentTime = GetGameTimer()
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local interactionDistance = Config.InteractionDistance or 3.0
        
        local nearStand = false
        local nearNPC = false
        local nearOwnStand = false
        local isWorldStand = false
        local targetNPC = nil
        local targetStand = nil
        local targetIndex = nil
        local nearSittingPlayer = false
        local sittingPlayerPed = nil
        
        if isPlacingStand then
            Wait(100)
            goto continue
        end
        
        for index, standData in pairs(placedStands) do
            if standData and standData.entity and DoesEntityExist(standData.entity) then
                local standCoords = GetEntityCoords(standData.entity)
                local distance = #(playerCoords - standCoords)
                
                if distance < interactionDistance then
                    nearStand = true
                    targetStand = standData
                    targetIndex = index
                    isWorldStand = false
                    
                    if standData.owner == GetPlayerServerId(PlayerId()) then
                        nearOwnStand = true
                        currentStand = standData
                    end
                    
                    if standData.occupied and standData.sittingPlayer then
                        for _, playerId in ipairs(GetActivePlayers()) do
                            local otherPed = GetPlayerPed(playerId)
                            if otherPed ~= playerPed then
                                local serverId = GetPlayerServerId(playerId)
                                if serverId == standData.sittingPlayer then
                                    local otherCoords = GetEntityCoords(otherPed)
                                    local distToStand = #(otherCoords - standCoords)
                                    if distToStand < 2.5 then
                                        nearSittingPlayer = true
                                        sittingPlayerPed = otherPed
                                    end
                                    break
                                end
                            end
                        end
                    end
                    
                    sleep = 0
                    break
                end
            end
        end
        
        if not nearStand then
            for index, standData in pairs(worldStands) do
                if standData and standData.entity and DoesEntityExist(standData.entity) then
                    local standCoords = GetEntityCoords(standData.entity)
                    local distance = #(playerCoords - standCoords)
                    
                    if distance < interactionDistance then
                        nearStand = true
                        targetStand = standData
                        targetIndex = index
                        isWorldStand = true
                        currentStand = standData
                        
                        if standData.occupied and standData.sittingPlayer then
                            for _, playerId in ipairs(GetActivePlayers()) do
                                local otherPed = GetPlayerPed(playerId)
                                if otherPed ~= playerPed then
                                    local serverId = GetPlayerServerId(playerId)
                                    if serverId == standData.sittingPlayer then
                                        local otherCoords = GetEntityCoords(otherPed)
                                        local distToStand = #(otherCoords - standCoords)
                                        if distToStand < 2.5 then
                                            nearSittingPlayer = true
                                            sittingPlayerPed = otherPed
                                        end
                                        break
                                    end
                                end
                            end
                        end
                        
                        sleep = 0
                        break
                    end
                end
            end
        end
        
        if not isSitting then
            for _, npc in pairs(queuedNPCs) do
                if DoesEntityExist(npc) then
                    local npcCoords = GetEntityCoords(npc)
                    local distance = #(playerCoords - npcCoords)
                    
                    if distance < interactionDistance then
                        nearNPC = true
                        targetNPC = npc
                        sleep = 0
                        break
                    end
                end
            end
        end
        
        if nearStand or nearNPC or isSitting or nearOwnStand or nearSittingPlayer then
            sleep = 0
            
            HideAllPrompts()
            
            if isSitting then
                ShowPrompt(standUpPrompt)
                
                if not isBeingShined and not autoShinerActive then
                    ShowPrompt(callShinerPrompt)
                end
                
                ShowPromptGroup('Shoe Shine Stand')
                
                if currentTime - lastPromptTime > promptCooldown then
                    if PromptHasStandardModeCompleted(standUpPrompt) then
                        lastPromptTime = currentTime
                        StandUp()
                    end
                    
                    if not isBeingShined and not autoShinerActive and PromptHasHoldModeCompleted(callShinerPrompt) then
                        lastPromptTime = currentTime
                        CallNPCShiner()
                    end
                end
                
            elseif nearSittingPlayer and targetStand and not isShining then
                if HasShoeShinerJob() then
                    ShowPrompt(shinePrompt)
                    ShowPromptGroup('Shine Player Shoes')
                    
                    if currentTime - lastPromptTime > promptCooldown then
                        if PromptHasHoldModeCompleted(shinePrompt) then
                            lastPromptTime = currentTime
                            ShineShoes(targetStand, targetStand.sittingPlayer)
                        end
                    end
                end
                
            elseif nearNPC and targetNPC and not isShining then
                if HasShoeShinerJob() then
                    ShowPrompt(shinePrompt)
                    ShowPromptGroup('Shine Customer Shoes')
                    
                    if currentTime - lastPromptTime > promptCooldown then
                        if PromptHasHoldModeCompleted(shinePrompt) then
                            lastPromptTime = currentTime
                            ShineNPCShoes(targetNPC)
                        end
                    end
                end
                
            elseif nearStand and targetStand and not isShining and not nearSittingPlayer then
                if not targetStand.occupied or targetStand.sittingPlayer == GetPlayerServerId(PlayerId()) then
                    ShowPrompt(sitPrompt)
                    
                    if HasShoeShinerJob() then
                        if not isWorldStand then
                            ShowPrompt(pickupPrompt)
                        end
                        
                        if nearOwnStand or isWorldStand then
                            ShowPrompt(callCustomerPrompt)
                        end
                    end
                    
                    ShowPromptGroup('Shoe Shine Stand')
                    
                    if currentTime - lastPromptTime > promptCooldown then
                        if PromptHasHoldModeCompleted(sitPrompt) and not targetStand.occupied then
                            lastPromptTime = currentTime
                            SitOnStand(targetStand)
                        end
                        
                        if HasShoeShinerJob() then
                            if not isWorldStand and PromptHasHoldModeCompleted(pickupPrompt) then
                                lastPromptTime = currentTime
                                PickupStand(targetStand, targetIndex, isWorldStand)
                            end
                            
                            if (nearOwnStand or isWorldStand) and PromptHasHoldModeCompleted(callCustomerPrompt) then
                                lastPromptTime = currentTime
                                CallNearbyCustomer()
                            end
                        end
                    end
                end
            end
        else
            HideAllPrompts()
        end
        
        ::continue::
        Wait(sleep)
    end
end)

-- ============================================
-- SYNC EVENTS
-- ============================================

RegisterNetEvent('shoeshine:client:syncStands', function(stands)
    for _, standInfo in pairs(stands) do
        local standEntity = NetworkGetEntityFromNetworkId(standInfo.netId)
        if DoesEntityExist(standEntity) then
            local exists = false
            for _, existing in pairs(placedStands) do
                if existing.entity == standEntity then
                    exists = true
                    break
                end
            end
            
            if not exists then
                local standData = {
                    entity = standEntity,
                    coords = standInfo.coords,
                    heading = standInfo.heading,
                    owner = standInfo.owner,
                    occupied = standInfo.occupied or false,
                    sittingPlayer = standInfo.sittingPlayer or nil,
                    isWorldStand = false
                }
                table.insert(placedStands, standData)
            end
        end
    end
end)

RegisterNetEvent('shoeshine:client:updateStandStatus', function(coords, occupied, sittingPlayer)
    for _, standData in pairs(placedStands) do
        if #(standData.coords - coords) < 1.0 then
            standData.occupied = occupied
            standData.sittingPlayer = sittingPlayer
            break
        end
    end
    
    for _, standData in pairs(worldStands) do
        if #(standData.coords - coords) < 1.0 then
            standData.occupied = occupied
            standData.sittingPlayer = sittingPlayer
            break
        end
    end
end)

RegisterNetEvent('shoeshine:client:removeStand', function(coords)
    for i, standData in pairs(placedStands) do
        if #(standData.coords - coords) < 1.0 then
            if DoesEntityExist(standData.entity) then
                DeleteEntity(standData.entity)
            end
            table.remove(placedStands, i)
            break
        end
    end
end)

-- ============================================
-- RESOURCE EVENTS
-- ============================================

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        Wait(1000)
        TriggerServerEvent('shoeshine:server:requestSync')
        
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CleanupAutoShiner()
        
        for _, npc in pairs(queuedNPCs) do
            if DoesEntityExist(npc) then
                ClearPedTasks(npc)
                FreezeEntityPosition(npc, false)
            end
        end
        
        local playerPed = PlayerPedId()
        ClearPedTasks(playerPed)
        FreezeEntityPosition(playerPed, false)
        
        for _, standData in pairs(placedStands) do
            if standData and standData.entity and DoesEntityExist(standData.entity) then
                DeleteEntity(standData.entity)
            end
        end
    end
end)

-- ============================================
-- ITEM USAGE
-- ============================================

RegisterNetEvent('shoeshine:client:useItem', function()
    OpenStandMenu()
end)

exports('OpenShoeShineMenu', OpenStandMenu)