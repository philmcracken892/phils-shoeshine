local RSGCore = exports['rsg-core']:GetCoreObject()

local syncedStands = {}



RSGCore.Functions.CreateUseableItem('shoeshine', function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    TriggerClientEvent('shoeshine:client:useItem', src)
end)



RegisterNetEvent('shoeshine:server:syncStand', function(data)
    local src = source
    data.owner = src
    table.insert(syncedStands, data)
    TriggerClientEvent('shoeshine:client:syncStands', -1, syncedStands)
end)

RegisterNetEvent('shoeshine:server:playerSat', function(coords)
    local src = source
    TriggerClientEvent('shoeshine:client:updateStandStatus', -1, coords, true, src)
end)

RegisterNetEvent('shoeshine:server:playerStood', function(coords)
    TriggerClientEvent('shoeshine:client:updateStandStatus', -1, coords, false, nil)
end)

RegisterNetEvent('shoeshine:server:removeStand', function(coords)
    for i, stand in pairs(syncedStands) do
        if #(stand.coords - coords) < 1.0 then
            table.remove(syncedStands, i)
            break
        end
    end
    TriggerClientEvent('shoeshine:client:removeStand', -1, coords)
end)

RegisterNetEvent('shoeshine:server:requestSync', function()
    local src = source
    TriggerClientEvent('shoeshine:client:syncStands', src, syncedStands)
end)



RegisterNetEvent('shoeshine:server:checkAndPay', function(targetId, standCoords)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(targetId)
    local Shiner = RSGCore.Functions.GetPlayer(src)
    
    if not Player or not Shiner then return end
    
    local shinePrice = Config.ShinePrice or 5
    local shinerEarnings = Config.ShinerEarnings or 3
    
    if Player.Functions.RemoveMoney('cash', shinePrice, 'shoe-shine-payment') then
        Shiner.Functions.AddMoney('cash', shinerEarnings, 'shoe-shine-earnings')
        
        TriggerClientEvent('shoeshine:client:performShine', src, standCoords)
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
            TriggerClientEvent('shoeshine:client:removeStand', -1, coords)
            table.remove(syncedStands, i)
        end
    end
end)