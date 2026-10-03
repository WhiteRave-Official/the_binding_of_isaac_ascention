local WeaponAdapter = {}

local GOLDEN_EYE_DAMAGE_MULTIPLIER = 0.50
local DEFAULT_INCUBUS_DAMAGE_MULTIPLIER = 0.75

local function getProxy(entity)
    local current = entity
    for _ = 1, 4 do
        if not current then
            return nil
        end

        local familiar = current:ToFamiliar()
        if familiar and familiar:GetData().GoldenEyeWeaponProxy then
            return familiar
        end

        current = current.SpawnerEntity or current.Parent
    end
    return nil
end

local function getNativeDamageMultiplier(proxy)
    local player = proxy.Player
    if player and player:GetPlayerType() == PlayerType.PLAYER_LILITH then
        return 1.0
    end
    return DEFAULT_INCUBUS_DAMAGE_MULTIPLIER
end

local function getCorrection(proxy)
    return GOLDEN_EYE_DAMAGE_MULTIPLIER / getNativeDamageMultiplier(proxy)
end

local function markScaled(entity)
    local data = entity:GetData()
    if data.GoldenEyeDamageScaled then
        return false
    end
    data.GoldenEyeDamageScaled = true
    return true
end

function WeaponAdapter.GetProxy(entity)
    return getProxy(entity)
end

function WeaponAdapter.ScaleTear(tear)
    local proxy = getProxy(tear.SpawnerEntity or tear.Parent)
    if proxy then
        tear.TearFlags = tear.TearFlags | TearFlags.TEAR_SPECTRAL
        if markScaled(tear) then
            tear.CollisionDamage = tear.CollisionDamage * getCorrection(proxy)
        end
    end
end

function WeaponAdapter.ScaleLaser(laser)
    local proxy = getProxy(laser.SpawnerEntity or laser.Parent)
    if proxy and markScaled(laser) then
        laser:SetDamageMultiplier(laser:GetDamageMultiplier() * getCorrection(proxy))
    end
end

function WeaponAdapter.ScaleBomb(bomb)
    local proxy = getProxy(bomb.SpawnerEntity or bomb.Parent)
    if proxy and markScaled(bomb) then
        local correction = getCorrection(proxy)
        bomb.ExplosionDamage = bomb.ExplosionDamage * correction
        bomb.RadiusMultiplier = bomb.RadiusMultiplier * math.sqrt(correction)
    end
end

function WeaponAdapter.ScaleKnife(knife)
    local proxy = getProxy(knife.SpawnerEntity or knife.Parent)
    if proxy and markScaled(knife) then
        knife.CollisionDamage = knife.CollisionDamage * getCorrection(proxy)
    end
end

return WeaponAdapter

