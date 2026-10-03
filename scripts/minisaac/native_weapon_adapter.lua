local Adapter = {}

local TARGET_DAMAGE = 0.15
local INCUBUS_DAMAGE = 0.75
local TEAR_SCALE = 0.6
local LASER_SCALE = 0.65

local function proxyOf(entity)
    local current = entity
    for _ = 1, 4 do
        if not current then return nil end
        local familiar = current:ToFamiliar()
        if familiar and familiar:GetData().AscentionMiniIsaacWeaponProxy then
            return familiar
        end
        current = current.SpawnerEntity or current.Parent
    end
    return nil
end

local function correction(proxy)
    local player = proxy.Player
    return TARGET_DAMAGE / (player and player:GetPlayerType() == PlayerType.PLAYER_LILITH
        and 1.0 or INCUBUS_DAMAGE)
end

local function firstScale(entity)
    local data = entity:GetData()
    if data.AscentionMiniIsaacNativeScaled then return false end
    data.AscentionMiniIsaacNativeScaled = true
    return true
end

function Adapter.Register(mod)
    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE, function(_, tear)
        local proxy = proxyOf(tear.SpawnerEntity or tear.Parent)
        if proxy and firstScale(tear) then
            if proxy.Player then
                tear.Velocity = tear.Velocity - proxy.Player.Velocity
            end
            tear.CollisionDamage = tear.CollisionDamage * correction(proxy)
            tear.Scale = tear.Scale * TEAR_SCALE
        end
    end, FamiliarVariant.INCUBUS)

    local function scaleLaser(_, laser)
        local proxy = proxyOf(laser.SpawnerEntity or laser.Parent)
        if proxy and firstScale(laser) then
            laser:SetDamageMultiplier(laser:GetDamageMultiplier() * correction(proxy))
            laser:SetScale(laser:GetScale() * LASER_SCALE)
            laser:ResetSpriteScale()
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_BRIMSTONE,
        scaleLaser, FamiliarVariant.INCUBUS)
    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_TECH_LASER,
        scaleLaser, FamiliarVariant.INCUBUS)
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TECH_X_LASER, scaleLaser)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_BOMB, function(_, bomb)
        local proxy = proxyOf(bomb.SpawnerEntity or bomb.Parent)
        if proxy and firstScale(bomb) then
            bomb.ExplosionDamage = bomb.ExplosionDamage * correction(proxy)
            bomb.RadiusMultiplier = bomb.RadiusMultiplier * 0.6
            bomb.SpriteScale = Vector(0.6, 0.6)
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_KNIFE, function(_, knife)
        local proxy = proxyOf(knife.SpawnerEntity or knife.Parent)
        if proxy and firstScale(knife) then
            knife.CollisionDamage = knife.CollisionDamage * correction(proxy)
            knife.Scale = knife.Scale * 0.6
            knife.SpriteScale = Vector(0.6, 0.6)
        end
    end)
end

return Adapter
