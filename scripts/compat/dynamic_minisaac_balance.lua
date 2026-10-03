local Balance = {}

local DAMAGE_MULTIPLIER = 0.15
local TECH_X_RADIUS_MULTIPLIER = 0.65
local LASER_SCALE_MULTIPLIER = 0.65
local OWNER_KEY = "AscentionDynamicMinisaacOwner"
local TECH_X_SCALE_KEY = "AscentionDynamicMinisaacTechXScaled"
local LASER_SCALE_KEY = "AscentionDynamicMinisaacLaserScaled"
local NEXT_ATTACK_FRAME_KEY = "AscentionDynamicMinisaacNextAttackFrame"

local function asMiniIsaac(entity)
    if entity
        and entity:Exists()
        and entity.Type == EntityType.ENTITY_FAMILIAR
        and entity.Variant == FamiliarVariant.MINISAAC
    then
        return entity:ToFamiliar()
    end
end

local function sameEntity(first, second)
    return first and second and GetPtrHash(first) == GetPtrHash(second)
end

local function getStoredOwner(entity)
    local owner = entity:GetData()[OWNER_KEY]
    if owner and owner:Exists() then
        return asMiniIsaac(owner)
    end
end

local function resolveOwner(entity)
    return getStoredOwner(entity)
        or asMiniIsaac(entity.Parent)
        or asMiniIsaac(entity.SpawnerEntity)
end

local function storeOwner(entity, familiar)
    if entity and familiar then
        entity:GetData()[OWNER_KEY] = familiar
    end
end

local function damageFor(familiar)
    local player = familiar and familiar.Player
    return player and player.Damage * DAMAGE_MULTIPLIER or nil
end

local function playerOwnsEntity(player, entity)
    local spawner = entity.SpawnerEntity
    local sourcePlayer = spawner and spawner:ToPlayer()
    return sourcePlayer and sameEntity(sourcePlayer, player)
end

local function associateNearbyOutputs(familiar, technicalTear)
    local player = familiar.Player
    if not player then return end

    for _, entity in ipairs(Isaac.FindInRadius(
        familiar.Position,
        3.0,
        EntityPartition.ALL
    )) do
        if entity.FrameCount <= 1
            and not sameEntity(entity, technicalTear)
            and playerOwnsEntity(player, entity)
        then
            local isAttack = entity.Type == EntityType.ENTITY_TEAR
                or entity.Type == EntityType.ENTITY_LASER
                or entity.Type == EntityType.ENTITY_BOMB
                or entity.Type == EntityType.ENTITY_KNIFE
            local isRocket = entity.Type == EntityType.ENTITY_EFFECT
                and entity:GetData().IsMinisaacRocket

            if isAttack or isRocket then
                storeOwner(entity, familiar)
            end
        end
    end
end

local function attackInterval(player)
    return math.max(1, math.floor(player.MaxFireDelay + 1.5))
end

local function onTearInit(_, tear)
    local familiar = asMiniIsaac(tear.SpawnerEntity)
    if not familiar or not familiar.Player then return end

    storeOwner(tear, familiar)
    familiar:GetData()[NEXT_ATTACK_FRAME_KEY]
        = Game():GetFrameCount() + attackInterval(familiar.Player)

    -- Dynamic Minisaacs creates some attacks with the player as their source.
    -- Associate those fresh entities while the technical tear still identifies
    -- the Mini Isaac that fired them.
    associateNearbyOutputs(familiar, tear)
end

local function updateFamiliarCooldown(_, familiar)
    if familiar.Variant ~= FamiliarVariant.MINISAAC then return end

    local nextFrame = familiar:GetData()[NEXT_ATTACK_FRAME_KEY]
    if not nextFrame then return end

    local remaining = nextFrame - Game():GetFrameCount()
    if remaining > 0 then
        familiar.FireCooldown = remaining
    else
        familiar.FireCooldown = 0
        familiar:GetData()[NEXT_ATTACK_FRAME_KEY] = nil
    end
end

local function normalizeTear(_, tear)
    local familiar = resolveOwner(tear)
    local damage = damageFor(familiar)
    if damage then
        tear.CollisionDamage = damage
    end
end

local function normalizeLaser(_, laser)
    local familiar = resolveOwner(laser)
    local damage = damageFor(familiar)
    if not damage then return end

    laser.CollisionDamage = damage
    local data = laser:GetData()
    if not data[LASER_SCALE_KEY] then
        laser:SetScale(laser:GetScale() * LASER_SCALE_MULTIPLIER)
        laser:ResetSpriteScale()
        data[LASER_SCALE_KEY] = true
    end
end

local function normalizeBomb(_, bomb)
    local familiar = resolveOwner(bomb)
    local damage = damageFor(familiar)
    if damage then
        bomb.ExplosionDamage = damage
    end
end

local function normalizeKnife(_, knife)
    local familiar = resolveOwner(knife)
    local damage = damageFor(familiar)
    if damage then
        knife.CollisionDamage = damage
    end
end

local function normalizeRocket(_, effect)
    if not effect:GetData().IsMinisaacRocket then return end

    local familiar = resolveOwner(effect)
    local damage = damageFor(familiar)
    if damage then
        effect.DamageSource = damage
    end
end

local function onTechXLaserFired(_, laser)
    local familiar = resolveOwner(laser)
    if not familiar then
        local spawner = laser.SpawnerEntity
        local player = spawner and spawner:ToPlayer()
        if player then
            for _, entity in ipairs(Isaac.FindInRadius(
                laser.Position,
                3.0,
                EntityPartition.FAMILIAR
            )) do
                local candidate = asMiniIsaac(entity)
                if candidate and sameEntity(candidate.Player, player) then
                    familiar = candidate
                    break
                end
            end
        end
    end

    if not familiar then return end
    storeOwner(laser, familiar)

    local data = laser:GetData()
    if not data[TECH_X_SCALE_KEY] then
        laser.Radius = laser.Radius * TECH_X_RADIUS_MULTIPLIER
        data[TECH_X_SCALE_KEY] = true
    end

    local damage = damageFor(familiar)
    if damage then
        laser.CollisionDamage = damage
    end
end

function Balance.Register(mod)
    if type(DynamicMinisaacContinued) ~= "table" then
        Isaac.DebugString(
            "[Ascention] Dynamic Minisaac balance support skipped: API unavailable"
        )
        return
    end

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, onTearInit)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, normalizeTear)
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, normalizeLaser)
    mod:AddCallback(ModCallbacks.MC_POST_BOMB_UPDATE, normalizeBomb)
    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, normalizeKnife)
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, normalizeRocket)
    mod:AddCallback(
        ModCallbacks.MC_FAMILIAR_UPDATE,
        updateFamiliarCooldown,
        FamiliarVariant.MINISAAC
    )
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TECH_X_LASER, onTechXLaserFired)
end

return Balance

