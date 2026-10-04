local Adapter = {}

local TARGET_DAMAGE = 0.15
local INCUBUS_DAMAGE = 0.75
local TEAR_SCALE = 0.6
local LASER_SCALE = 0.65
local MONSTROS_LUNG = CollectibleType.COLLECTIBLE_MONSTROS_LUNG
local TECHNOLOGY = CollectibleType.COLLECTIBLE_TECHNOLOGY

local function chargedTechnology(player)
    return player and player:HasCollectible(MONSTROS_LUNG)
        and player:HasCollectible(TECHNOLOGY)
end

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

local function directProxy(entity)
    local familiar = entity and entity:ToFamiliar()
    return familiar and familiar:GetData().AscentionMiniIsaacWeaponProxy
        and familiar or nil
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
    local redirectedSamples = 0
    local chargedTearSamples = 0
    local chargedLaserSamples = 0
    local function redirectTear(tear, proxy, stage)
        local data = tear:GetData()
        if data.AscentionMiniIsaacNativeAimed or data.AscentionMiniIsaacSplitChild then return end
        local player = proxy.Player
        if not player then return end
        local owner = proxy:GetData().AscentionMiniIsaacProxyOwner
        local mini = owner and owner.Ref
        local aim = mini and mini:Exists() and mini:GetData().AscentionMiniIsaacAim
        if not aim or aim:LengthSquared() < 0.01 then return end
        local velocity = tear.Velocity - player.Velocity * 1.2
        if velocity:LengthSquared() < 0.01 then return end
        local frame = Game():GetFrameCount()
        local proxyData = proxy:GetData()
        if proxyData.AscentionMiniIsaacTearSourceFrame ~= frame then
            proxyData.AscentionMiniIsaacTearSourceFrame = frame
            proxyData.AscentionMiniIsaacTearSource = velocity
            proxyData.AscentionMiniIsaacTearSourceSeed = tear.InitSeed
        end
        local source = proxyData.AscentionMiniIsaacTearSource
        local angle = aim:GetAngleDegrees() - source:GetAngleDegrees()
        tear.Velocity = velocity:Rotated(angle)
        tear.Position = proxy.Position + (tear.Position - proxy.Position):Rotated(angle)
        tear.Scale = tear.Scale * TEAR_SCALE
        data.AscentionMiniIsaacNativeAimed = true
        if mini and mini:Exists() then
            mini:GetData().AscentionMiniIsaacTearShotFrame = frame
        end
        if redirectedSamples < 6 then
            redirectedSamples = redirectedSamples + 1
            Isaac.DebugString("[AscentionMiniIsaac] tear_redirect seed="
                .. tostring(tear.InitSeed) .. " proxy=" .. tostring(proxy.InitSeed)
                .. " stage=" .. tostring(stage)
                .. " angle=" .. tostring(angle)
                .. " velocity=" .. tostring(tear.Velocity.X) .. ","
                .. tostring(tear.Velocity.Y))
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, function(_, tear)
        -- Regular Incubus tears bypass Familiar::FireProjectile but retain its
        -- SpawnerEntity. Aim and visual scale must be set before first render.
        local proxy = directProxy(tear.SpawnerEntity)
        if proxy then redirectTear(tear, proxy, "init") end
        if proxy and chargedTechnology(proxy.Player) and chargedTearSamples < 12 then
            chargedTearSamples = chargedTearSamples + 1
            Isaac.DebugString("[AscentionMiniIsaac] charged_technology_tear seed="
                .. tostring(tear.InitSeed)
                .. " spawner=" .. tostring(tear.SpawnerEntity and tear.SpawnerEntity.Type)
                .. " parent=" .. tostring(tear.Parent and tear.Parent.Type)
                .. " damage=" .. tostring(tear.CollisionDamage))
        end
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_TEAR_UPDATE, function(_, tear)
        if tear.FrameCount > 1 then return end
        local proxy = directProxy(tear.SpawnerEntity)
        if proxy and not tear:GetData().AscentionMiniIsaacNativeAimed then
            redirectTear(tear, proxy, "pre_update")
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
        if tear.FrameCount ~= 1 then return end
        local proxy = directProxy(tear.SpawnerEntity)
        local player = tear.Parent and tear.Parent:ToPlayer()
        if not proxy or not player then return end
        redirectTear(tear, proxy, "post_update")
        if firstScale(tear) then
            tear.CollisionDamage = tear.CollisionDamage * correction(proxy)
            if not tear:GetData().AscentionMiniIsaacNativeAimed then
                tear.Scale = tear.Scale * TEAR_SCALE
            end
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE, function(_, tear)
        local proxy = proxyOf(tear.SpawnerEntity) or proxyOf(tear.Parent)
        if proxy and firstScale(tear) then
            local proxyData = proxy:GetData()
            local samples = proxyData.AscentionMiniIsaacTearSamples or 0
            if samples < 4 then
                proxyData.AscentionMiniIsaacTearSamples = samples + 1
                local owner = proxyData.AscentionMiniIsaacProxyOwner
                local mini = owner and owner.Ref
                local aim = mini and mini:Exists()
                    and mini:GetData().AscentionMiniIsaacAim
                Isaac.DebugString("[AscentionMiniIsaac] tear velocity="
                    .. tostring(tear.Velocity.X) .. "," .. tostring(tear.Velocity.Y)
                    .. " aim=" .. tostring(aim and aim.X) .. ","
                    .. tostring(aim and aim.Y)
                    .. " player_velocity=" .. tostring(proxy.Player and proxy.Player.Velocity.X)
                    .. "," .. tostring(proxy.Player and proxy.Player.Velocity.Y))
            end
            tear.CollisionDamage = tear.CollisionDamage * correction(proxy)
            if not tear:GetData().AscentionMiniIsaacNativeAimed then
                tear.Scale = tear.Scale * TEAR_SCALE
            end
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
    mod:AddCallback(ModCallbacks.MC_POST_LASER_INIT, function(_, laser)
        local spawner = laser.SpawnerEntity
        local parent = laser.Parent
        local player = (spawner and spawner:ToPlayer())
            or (parent and parent:ToPlayer())
        local proxy = proxyOf(spawner) or proxyOf(parent)
        if not chargedTechnology(player or (proxy and proxy.Player)) then return end
        local beforeDamage = laser.CollisionDamage
        local beforeScale = laser:GetScale()
        if proxy and firstScale(laser) then
            local targetDamage = proxy.Player.Damage * TARGET_DAMAGE
            if beforeDamage > 0 then
                laser:SetDamageMultiplier(laser:GetDamageMultiplier()
                    * targetDamage / beforeDamage)
            end
            laser.CollisionDamage = targetDamage
            laser:SetScale(beforeScale * LASER_SCALE)
            laser:ResetSpriteScale()
            laser:GetData().AscentionMiniIsaacChargedTechDamage = targetDamage
        end
        if chargedLaserSamples < 20 then
            chargedLaserSamples = chargedLaserSamples + 1
            Isaac.DebugString("[AscentionMiniIsaac] charged_technology_laser seed="
                .. tostring(laser.InitSeed)
                .. " spawner=" .. tostring(spawner and spawner.Type)
                .. " parent=" .. tostring(parent and parent.Type)
                .. " proxy=" .. tostring(proxy and proxy.InitSeed)
                .. " damage_before=" .. tostring(beforeDamage)
                .. " damage_after=" .. tostring(laser.CollisionDamage)
                .. " player_damage=" .. tostring(proxy and proxy.Player.Damage)
                .. " scale_before=" .. tostring(beforeScale)
                .. " scale_after=" .. tostring(laser:GetScale()))
        end
    end)
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, function(_, laser)
        if laser.FrameCount > 1 then return end
        local expected = laser:GetData().AscentionMiniIsaacChargedTechDamage
        if expected and laser.CollisionDamage > expected then
            laser.CollisionDamage = expected
        end
    end)
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
