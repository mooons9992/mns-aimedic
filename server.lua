local QBCore = exports['qb-core']:GetCoreObject()

-- Debug logging function
local function DebugLog(message)
    if Config.Debug then
        print("[MNS-AIMedic] " .. message)
    end
end

-- Process payment for revive (no email)
RegisterNetEvent('mns-aimedic:server:PayForRevive', function(amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if Player then
        -- Get current bank balance
        local bankBalance = Player.PlayerData.money['bank']
        
        -- Check if player has enough money
        if bankBalance >= amount then
            -- Remove money from bank
            Player.Functions.RemoveMoney('bank', amount, "ai-medic-services")
            
            -- Send success callback to client
            TriggerClientEvent('mns-aimedic:client:PaymentProcessed', src, true, amount)
            DebugLog("Player " .. src .. " paid $" .. amount .. " for medical services")
        else
            -- Not enough money
            TriggerClientEvent('mns-aimedic:client:PaymentProcessed', src, false, amount)
            DebugLog("Player " .. src .. " does not have enough money for medical services")
        end
    end
end)

-- Get EMS count
QBCore.Functions.CreateCallback('mns-aimedic:server:GetEMSCount', function(source, cb)
    local emsCount = 0
    local players = QBCore.Functions.GetQBPlayers()
    
    for _, player in pairs(players) do
        if player.PlayerData.job.name == Config.EMSJobName then
            emsCount = emsCount + 1
        end
    end
    
    cb(emsCount)
end)

-- Create server callback for getting online EMS count
QBCore.Functions.CreateCallback('mns-aimedic:server:GetOnlineEMS', function(source, cb)
    local emsCount = 0
    local players = QBCore.Functions.GetPlayers()
    
    for _, v in pairs(players) do
        local Player = QBCore.Functions.GetPlayer(v)
        if Player and Player.PlayerData.job.name == Config.EMSJobName then
            emsCount = emsCount + 1
        end
    end
    
    cb(emsCount)
end)