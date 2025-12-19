local RSGCore = exports['rsg-core']:GetCoreObject()

local syncedStands = {}

-- Helper function to convert vector3 to table
local function vectorToTable(vec)
    if vec then
        return { x = vec.x, y = vec.y, z = vec.z }
    end
    return nil
end

-- Helper function to convert table to vector3
local function tableToVector(tbl)
    if tbl then
        return vector3(tbl.x, tbl.y, tbl.z)
    end
    return nil
end

RSGCore.Functions.CreateUseableItem('shoeshine', function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    TriggerClientEvent('shoeshine:client:useItem', src)
end)

RegisterNetEvent('shoeshine:server:syncStand', function(data)
    local src = source
    
    -- Convert coords to table format for proper network serialization
    local standData = {
        owner = src,
        coords = vectorToTable(data.coords),
        heading = data.heading,
        netId = data.netId,  -- ✅ ADD THIS LINE
        occupied = false,
        sittingPlayer = nil
    }
    
    table.insert(syncedStands, standData)
    
    -- Debug print
    print('^2[Shoeshine]^7 Stand created by player ' .. src .. ' at ' .. json.encode(standData.coords) .. ' netId: ' .. tostring(data.netId))
    print('^2[Shoeshine]^7 Total stands: ' .. #syncedStands)
    
    -- Sync to ALL players
    TriggerClientEvent('shoeshine:client:syncStands', -1, syncedStands)
end)

-- Sync stands when player joins/loads
RegisterNetEvent('shoeshine:server:requestSync', function()
    local src = source
    print('^2[Shoeshine]^7 Player ' .. src .. ' requested sync. Sending ' .. #syncedStands .. ' stands')
    TriggerClientEvent('shoeshine:client:syncStands', src, syncedStands)
end)

-- Also sync on player loaded (RSG-Core specific)
AddEventHandler('RSGCore:Server:OnPlayerLoaded', function()
    local src = source
    Wait(2000) -- Give client time to fully load
    print('^2[Shoeshine]^7 Player ' .. src .. ' loaded. Sending ' .. #syncedStands .. ' stands')
    TriggerClientEvent('shoeshine:client:syncStands', src, syncedStands)
end)

RegisterNetEvent('shoeshine:server:playerSat', function(coords)
    local src = source
    local coordsTable = vectorToTable(coords)
    
    if not coordsTable then
        print('^1[Shoeshine]^7 playerSat received invalid coords')
        return
    end
    
    -- Update stand status in syncedStands using DISTANCE comparison (not exact)
    local found = false
    for i, stand in ipairs(syncedStands) do
        if stand.coords then
            local dist = math.sqrt(
                (stand.coords.x - coordsTable.x)^2 + 
                (stand.coords.y - coordsTable.y)^2 + 
                (stand.coords.z - coordsTable.z)^2
            )
            if dist < 2.0 then
                syncedStands[i].occupied = true
                syncedStands[i].sittingPlayer = src
                found = true
                print('^2[Shoeshine]^7 Player ' .. src .. ' sat on stand. Occupied = true')
                break
            end
        end
    end
    
    if not found then
        print('^1[Shoeshine]^7 Could not find stand for player ' .. src .. ' to sit on!')
    end
    
    -- Send update to ALL clients
    TriggerClientEvent('shoeshine:client:updateStandStatus', -1, coordsTable, true, src)
end)

RegisterNetEvent('shoeshine:server:playerStood', function(coords)
    local coordsTable = vectorToTable(coords)
    
    -- Update stand status in syncedStands
    for i, stand in ipairs(syncedStands) do
        if stand.coords and coordsTable then
            local dist = math.sqrt(
                (stand.coords.x - coordsTable.x)^2 + 
                (stand.coords.y - coordsTable.y)^2 + 
                (stand.coords.z - coordsTable.z)^2
            )
            if dist < 1.0 then
                syncedStands[i].occupied = false
                syncedStands[i].sittingPlayer = nil
                break
            end
        end
    end
    
    TriggerClientEvent('shoeshine:client:updateStandStatus', -1, coordsTable, false, nil)
end)

RegisterNetEvent('shoeshine:server:removeStand', function(coords)
    local coordsTable = vectorToTable(coords)
    
    for i = #syncedStands, 1, -1 do
        local stand = syncedStands[i]
        if stand.coords and coordsTable then
            local dist = math.sqrt(
                (stand.coords.x - coordsTable.x)^2 + 
                (stand.coords.y - coordsTable.y)^2 + 
                (stand.coords.z - coordsTable.z)^2
            )
            if dist < 1.0 then
                print('^1[Shoeshine]^7 Removing stand at ' .. json.encode(stand.coords))
                table.remove(syncedStands, i)
                break
            end
        end
    end
    
    TriggerClientEvent('shoeshine:client:removeStand', -1, coordsTable)
    print('^2[Shoeshine]^7 Remaining stands: ' .. #syncedStands)
end)

-- Rest of your payment events...
RegisterNetEvent('shoeshine:server:checkAndPay', function(targetId, standCoords)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(targetId)
    local Shiner = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not Shiner then return end
    
    local shinePrice = Config.ShinePrice or 5
    local shinerEarnings = Config.ShinerEarnings or 3
    
    if Player.Functions.RemoveMoney('cash', shinePrice, 'shoe-shine-payment') then
        Shiner.Functions.AddMoney('cash', shinerEarnings, 'shoe-shine-earnings')
        
        TriggerClientEvent('shoeshine:client:performShine', src, vectorToTable(standCoords))
        TriggerClientEvent('shoeshine:client:receiveShine', targetId)
        
        TriggerClientEvent('ox_lib:notify', targetId, {
            title = 'Shoe Shine',
            description = 'You paid $' .. shinePrice .. ' for a shoe shine',
            type = 'inform'
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Shoe Shine',
            description = 'Customer does not have enough money!',
            type = 'error'
        })
    end
end)

RegisterNetEvent('shoeshine:server:payForNPCShineNow', function(cost)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then 
        TriggerClientEvent('shoeshine:client:npcShinePaymentResult', src, false, cost)
        return 
    end
    
    local currentCash = Player.Functions.GetMoney('cash')
    
    if currentCash >= cost then
        local removed = Player.Functions.RemoveMoney('cash', cost, 'npc-shoe-shine')
        
        if removed then
            TriggerClientEvent('shoeshine:client:npcShinePaymentResult', src, true, cost)
        else
            TriggerClientEvent('shoeshine:client:npcShinePaymentResult', src, false, cost)
        end
    else
        TriggerClientEvent('shoeshine:client:npcShinePaymentResult', src, false, cost)
    end
end)

RegisterNetEvent('shoeshine:server:refundNPCShine', function(cost)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    Player.Functions.AddMoney('cash', cost, 'npc-shoe-shine-refund')
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Shoe Shine',
        description = 'Refunded $' .. cost .. ' - no shiner available',
        type = 'inform'
    })
end)

RegisterNetEvent('shoeshine:server:npcPayment', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if Player then
        local npcPayAmount = Config.NPCPayAmount or 10
        Player.Functions.AddMoney('cash', npcPayAmount, 'npc-shoe-shine')
    end
end)

-- ============================================
-- CLEANUP
-- ============================================

AddEventHandler('playerDropped', function(reason)
    local src = source
    
    for i = #syncedStands, 1, -1 do
        if syncedStands[i].owner == src then
            local coords = syncedStands[i].coords
            print('^1[Shoeshine]^7 Player ' .. src .. ' dropped. Removing their stand.')
            TriggerClientEvent('shoeshine:client:removeStand', -1, coords)
            table.remove(syncedStands, i)
        end
    end
end)
