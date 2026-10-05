local GeburahHealth = {}

local GEBURAH = Isaac.GetPlayerTypeByName("Geburah")
local GEBURAH_MAX_HEALTH = 25
local MAX_DECAY_PER_UPDATE = 0.5
local STATE_KEY = "AscentionGeburahMiniIsaacHealth"
local LOG_INTERVAL = 60

local function logHealth(mini, event, detail)
    Isaac.DebugString("[AscentionMiniIsaacHP] " .. event
        .. " seed=" .. tostring(mini.InitSeed)
        .. " subtype=" .. tostring(mini.SubType)
        .. " hp=" .. tostring(mini.HitPoints)
        .. "/" .. tostring(mini.MaxHitPoints)
        .. (detail and " " .. detail or ""))
end

local function isGeburahMini(mini)
    local player = mini and mini.Variant == FamiliarVariant.MINISAAC and mini.Player
    return GEBURAH >= 0 and player and player:GetPlayerType() == GEBURAH
end

function GeburahHealth.Register(mod)
    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, function(_, mini)
        local frame = Game():GetFrameCount()
        local data = mini:GetData()
        if frame % LOG_INTERVAL == mini.InitSeed % LOG_INTERVAL then
            logHealth(mini, "status", "geburah=" .. tostring(not not isGeburahMini(mini)))
        end
        if not isGeburahMini(mini) then return end
        local state = data[STATE_KEY]
        if not state then
            if mini.MaxHitPoints <= 0 then return end
            if mini.MaxHitPoints ~= GEBURAH_MAX_HEALTH then
                local original = mini.HitPoints
                mini.HitPoints = mini.HitPoints + GEBURAH_MAX_HEALTH - mini.MaxHitPoints
                mini.MaxHitPoints = GEBURAH_MAX_HEALTH
                mini.HitPoints = math.min(mini.HitPoints, GEBURAH_MAX_HEALTH)
                logHealth(mini, "health_adjusted", "before=" .. tostring(original))
            end
            state = {}
            data[STATE_KEY] = state
        end
        state.beforeUpdate = mini.HitPoints
    end, FamiliarVariant.MINISAAC)

    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
        local mini = entity:ToFamiliar()
        if not mini or mini.Variant ~= FamiliarVariant.MINISAAC then return end
        local sourceEntity = source and source.Entity
        logHealth(mini, "damage_event", "amount=" .. tostring(amount)
            .. " flags=" .. tostring(flags)
            .. " source=" .. tostring(sourceEntity and sourceEntity.Type or "none"))
        if isGeburahMini(mini) then
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
        local lost = before - mini.HitPoints
        if lost ~= 0 then
            logHealth(mini, "hp_change", "before=" .. tostring(before)
                .. " delta=" .. tostring(-lost)
                .. " damage_frame=" .. tostring(state.lastDamageFrame or "none"))
        end
        if state.lastDamageFrame and frame <= state.lastDamageFrame + 1 then return end
        if lost > 0 and lost <= MAX_DECAY_PER_UPDATE then
            mini.HitPoints = math.min(mini.MaxHitPoints, before)
            logHealth(mini, "decay_restored", "before=" .. tostring(before)
                .. " lost=" .. tostring(lost))
        end
    end, FamiliarVariant.MINISAAC)
end

return GeburahHealth
