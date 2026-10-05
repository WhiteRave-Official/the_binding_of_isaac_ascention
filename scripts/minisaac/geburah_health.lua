local GeburahHealth = {}

local GEBURAH = Isaac.GetPlayerTypeByName("Geburah")
local BONUS_HEALTH = 25
local GEBURAH_BASE_MAX_HEALTH = 40
local MAX_DECAY_PER_UPDATE = 0.5
local STATE_KEY = "AscentionGeburahMiniIsaacHealth"

local function isGeburahMini(mini)
    local player = mini and mini.Variant == FamiliarVariant.MINISAAC and mini.Player
    return GEBURAH >= 0 and player and player:GetPlayerType() == GEBURAH
end

function GeburahHealth.Register(mod)
    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, function(_, mini)
        if not isGeburahMini(mini) then return end
        local data = mini:GetData()
        local state = data[STATE_KEY]
        if not state then
            if mini.MaxHitPoints <= 0 then return end
            if mini.MaxHitPoints < GEBURAH_BASE_MAX_HEALTH then
                mini.MaxHitPoints = mini.MaxHitPoints + BONUS_HEALTH
                mini.HitPoints = mini.HitPoints + BONUS_HEALTH
            end
            state = {}
            data[STATE_KEY] = state
        end
        state.beforeUpdate = mini.HitPoints
    end, FamiliarVariant.MINISAAC)

    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity)
        if isGeburahMini(entity:ToFamiliar()) then
            local state = entity:GetData()[STATE_KEY]
            if state then state.lastDamageFrame = Game():GetFrameCount() end
        end
    end, EntityType.ENTITY_FAMILIAR)

    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, function(_, mini)
        local state = mini:GetData()[STATE_KEY]
        if not state or not isGeburahMini(mini) then return end
        local before = state.beforeUpdate
        state.beforeUpdate = nil
        if not before then return end

        local frame = Game():GetFrameCount()
        if state.lastDamageFrame and frame <= state.lastDamageFrame + 1 then return end
        local lost = before - mini.HitPoints
        if lost > 0 and lost <= MAX_DECAY_PER_UPDATE then
            mini.HitPoints = math.min(mini.MaxHitPoints, before)
        end
    end, FamiliarVariant.MINISAAC)
end

return GeburahHealth
