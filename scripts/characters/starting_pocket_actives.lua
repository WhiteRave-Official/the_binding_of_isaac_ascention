local StartingPocketActives = {}

local PRIMARY = ActiveSlot.SLOT_PRIMARY
local POCKET = ActiveSlot.SLOT_POCKET
local function isBaseCharacter(player)
    local config = EntityConfig.GetPlayer(player:GetPlayerType())
    return config ~= nil and not config:IsTainted()
end

local function moveStartingActive(player)
    if not isBaseCharacter(player) or player:GetActiveItem(POCKET) ~= 0 then
        return
    end

    local item = player:GetActiveItem(PRIMARY)
    if item == 0 then return end

    local charge = player:GetActiveCharge(PRIMARY)
    local batteryCharge = player:GetBatteryCharge(PRIMARY)
    player:RemoveCollectible(item, false, PRIMARY)
    player:SetPocketActiveItem(item, POCKET, true)
    player:SetActiveCharge(charge, POCKET)
    if batteryCharge > 0 then
        player:AddActiveCharge(batteryCharge, POCKET, false, true, true)
    end
end

function StartingPocketActives.Register(mod)
    local runStarted = false
    local freshRun = false
    local pending = setmetatable({}, { __mode = "k" })

    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
        runStarted = true
        freshRun = not continued
        if continued then return end
        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            moveStartingActive(player)
            pending[player] = nil
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, function(_, player)
        if runStarted and freshRun then pending[player] = true end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
        if not pending[player] then return end
        pending[player] = nil
        moveStartingActive(player)
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
        runStarted = false
        freshRun = false
        pending = setmetatable({}, { __mode = "k" })
    end)
end

return StartingPocketActives
