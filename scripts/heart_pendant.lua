local HeartPendant = {}

local HEALTH_COUNT_KEY = "AscentionHeartPendantHealthCount"
local HEALTH_BASE_KEY = "AscentionHeartPendantBaseHealth"
local COOLDOWN_KEY = "AscentionHeartPendantCooldown"

local function ownerOf(entity, depth)
    if not entity or depth > 5 then return nil end
    local player = entity:ToPlayer()
    if player then return player end
    local familiar = entity:ToFamiliar()
    if familiar and familiar.Player then return familiar.Player end
    return ownerOf(entity.SpawnerEntity, depth + 1)
        or ownerOf(entity.Parent, depth + 1)
end

local function allyOf(entity, depth)
    if not entity or depth > 5 or entity:ToPlayer() then return nil end
    local familiar = entity:ToFamiliar()
    if familiar then return familiar end
    local npc = entity:ToNPC()
    if npc and npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return npc end
    return allyOf(entity.SpawnerEntity, depth + 1)
        or allyOf(entity.Parent, depth + 1)
end

local function healthBonus(ally, count)
    local maxHp = ally.MaxHitPoints
    if not maxHp or maxHp <= 0 then return end
    local data = ally:GetData()
    local previous = data[HEALTH_COUNT_KEY] or 0
    local baseMax = data[HEALTH_BASE_KEY] or maxHp
    local expected = baseMax * (1 + previous * 0.2)
    if maxHp ~= expected then
        -- Another familiar handler may restore its base HP every update.
        if maxHp ~= baseMax then
            baseMax = maxHp / (1 + previous * 0.2)
        end
    elseif previous == count then
        return
    end
    local desired = baseMax * (1 + count * 0.2)
    ally.MaxHitPoints = desired
    ally.HitPoints = math.min(desired,
        math.max(0.01, ally.HitPoints + desired - maxHp))
    data[HEALTH_COUNT_KEY] = count
    data[HEALTH_BASE_KEY] = baseMax
end

local function fasterCooldown(familiar, count)
    local data = familiar:GetData()
    local state = data[COOLDOWN_KEY]
    if not state then
        state = { previous = 0, base = 0, fraction = 0 }
        data[COOLDOWN_KEY] = state
    end
    local weapon = familiar.GetWeapon and familiar:GetWeapon()
    local usesWeapon = weapon ~= nil
    if state.usesWeapon ~= usesWeapon then
        state.previous = 0
        state.base = 0
        state.fraction = 0
        state.usesWeapon = usesWeapon
    end
    local current = usesWeapon and weapon:GetFireDelay() or familiar.FireCooldown
    if not current or current <= 0 or count <= 0 then
        state.previous = current or 0
        state.fraction = 0
        return
    end
    if current > state.previous then
        state.base = usesWeapon
            and math.max(current, weapon:GetMaxFireDelay()) or current
        state.fraction = 0
    end
    local base = state.base > 0 and state.base or current
    -- +1 shot per second adds d/30 cooldown progress each frame.
    state.fraction = state.fraction + count * base / 30
    local extra = math.floor(state.fraction)
    state.fraction = state.fraction - extra
    if extra > 0 then
        local shortened = math.max(0, current - extra)
        if usesWeapon then
            weapon:SetFireDelay(shortened)
        else
            familiar.FireCooldown = shortened
        end
    end
    state.previous = usesWeapon and weapon:GetFireDelay()
        or familiar.FireCooldown
end

function HeartPendant.Register(mod, itemId)
    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, function(_, familiar)
        local owner = familiar.Player
        if not owner then return end
        local count = owner:GetCollectibleNum(itemId)
        healthBonus(familiar, count)
        if not familiar:GetData().AscentionMiniIsaacWeaponProxy then
            fasterCooldown(familiar, count)
        end
    end)

    mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, function(_, npc)
        if not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
        local owner = ownerOf(npc.SpawnerEntity, 0)
            or ownerOf(npc.Parent, 0)
        if owner then healthBonus(npc, owner:GetCollectibleNum(itemId)) end
    end)

    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG,
        function(_, target, damage, _, source, _, extraSource)
            if not target:ToNPC() or target:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
                return
            end
            local extra = extraSource and extraSource.Entity
            local direct = source and source.Entity
            local ally = allyOf(extra, 0) or allyOf(direct, 0)
            if not ally then return end
            local owner = ownerOf(ally, 0)
            local count = owner and owner:GetCollectibleNum(itemId) or 0
            if count > 0 then
                return { Damage = damage * (1 + 0.1 * count) }
            end
        end, EntityType.ENTITY_NPC)
end

return HeartPendant
