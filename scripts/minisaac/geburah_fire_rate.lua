local GeburahFireRate = {}

local GEBURAH = Isaac.GetPlayerTypeByName("Geburah")
local MAX_CYCLE_FRAMES = 30 / 0.5
local MAX_FIRE_DELAY = MAX_CYCLE_FRAMES - 1

function GeburahFireRate.MaximumCycle(player)
    return GEBURAH >= 0 and player:GetPlayerType() == GEBURAH
        and MAX_CYCLE_FRAMES or nil
end

function GeburahFireRate.EffectiveCharge(player, maxCharge)
    if not GeburahFireRate.MaximumCycle(player) then
        return maxCharge
    end
    return math.min(maxCharge, MAX_CYCLE_FRAMES - 1)
end

function GeburahFireRate.EffectiveCooldown(player, cooldown)
    if GEBURAH >= 0 and player:GetPlayerType() == GEBURAH then
        return math.min(cooldown, MAX_FIRE_DELAY + 1)
    end
    return cooldown
end

function GeburahFireRate.MinimumRate(player)
    return GEBURAH >= 0 and player:GetPlayerType() == GEBURAH
        and 0.5 or nil
end

function GeburahFireRate.Register(mod)
    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, function(_, proxy)
        local pointer = proxy:GetData().AscentionMiniIsaacProxyOwner
        local mini = pointer and pointer.Ref
        local player = mini and mini:Exists() and mini.Player
        if not player or GEBURAH < 0 or player:GetPlayerType() ~= GEBURAH then
            return
        end
        local weapon = proxy:GetWeapon()
        if not weapon then return end

        if weapon:GetFireDelay() > MAX_FIRE_DELAY then
            weapon:SetFireDelay(MAX_FIRE_DELAY)
        end
    end, FamiliarVariant.INCUBUS)
end

return GeburahFireRate
