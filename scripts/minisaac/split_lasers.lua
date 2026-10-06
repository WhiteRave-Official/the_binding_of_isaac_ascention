local SplitLasers = {}

local TARGET_DAMAGE = 0.15
local INCUBUS_DAMAGE = 0.75
local LASER_SCALE = 0.65
local SCALED_KEY = "AscentionMiniIsaacNativeScaled"

local function sourceTear(entity, depth)
    if not entity or depth > 4 then return nil end
    local tear = entity:ToTear()
    if tear then
        local data = tear:GetData()
        if data.AscentionMiniIsaacSplitChild or data.AscentionMiniIsaacNativeAimed then
            return tear
        end
    end
    return sourceTear(entity.SpawnerEntity, depth + 1)
        or sourceTear(entity.Parent, depth + 1)
end

function SplitLasers.Register(mod)
    local samples = 0
    local unmatchedSamples = 0
    local pending = {}

    function SplitLasers.CorrectSplit(child, source)
        local entry = pending[child.InitSeed]
        if not entry or Game():GetFrameCount() - entry.frame > 2 then return end
        pending[child.InitSeed] = nil
        local entity = entry.laser.Ref
        local laser = entity and entity:ToLaser()
        if not laser or not laser:Exists() then return end

        -- This synergy spawns the laser as a player projectile, even when
        -- the split callback identifies its source as a Mini Isaac tear.
        local beforeDamage = child.CollisionDamage
        local targetDamage = beforeDamage * TARGET_DAMAGE
        local laserDamage = laser.CollisionDamage
        local beforeScale = laser:GetScale()
        local beforeMultiplier = laser:GetDamageMultiplier()
        laser:GetData()[SCALED_KEY] = true
        laser:GetData().AscentionMiniIsaacOwner =
            child:GetData().AscentionMiniIsaacOwner
        if laserDamage > 0 then
            laser:SetDamageMultiplier(beforeMultiplier * targetDamage / laserDamage)
        end
        child.CollisionDamage = targetDamage
        laser.CollisionDamage = targetDamage
        laser:SetScale(beforeScale * LASER_SCALE)
        laser:ResetSpriteScale()

        if samples < 20 then
            samples = samples + 1
            Isaac.DebugString("[AscentionMiniIsaac] split_laser_matched source="
                .. tostring(source and source.InitSeed)
                .. " child=" .. tostring(child.InitSeed)
                .. " child_type=" .. tostring(child.Type)
                .. " laser_type=" .. tostring(laser.Type)
                .. " child_before=" .. tostring(beforeDamage)
                .. " laser_before=" .. tostring(laserDamage)
                .. " damage_after=" .. tostring(laser.CollisionDamage)
                .. " multiplier_before=" .. tostring(beforeMultiplier)
                .. " multiplier_after=" .. tostring(laser:GetDamageMultiplier())
                .. " scale_before=" .. tostring(beforeScale)
                .. " scale_after=" .. tostring(laser:GetScale()))
        end
    end

    local function correctLaser(_, laser)
        if laser:GetData()[SCALED_KEY] then return end
        local source = sourceTear(laser.SpawnerEntity, 1)
            or sourceTear(laser.Parent, 1)
        if not source then
            if laser.FrameCount == 0 and unmatchedSamples < 12 then
                local spawner = laser.SpawnerEntity
                local parent = laser.Parent
                local player = (spawner and spawner:ToPlayer())
                    or (parent and parent:ToPlayer())
                if player and player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
                    and player:HasCollectible(CollectibleType.COLLECTIBLE_HAEMOLACRIA) then
                    pending[laser.InitSeed] = {
                        laser = EntityPtr(laser),
                        frame = Game():GetFrameCount(),
                    }
                    unmatchedSamples = unmatchedSamples + 1
                    Isaac.DebugString("[AscentionMiniIsaac] split_laser_unmatched laser="
                        .. tostring(laser.InitSeed)
                        .. " spawner_type=" .. tostring(spawner and spawner.Type)
                        .. " parent_type=" .. tostring(parent and parent.Type)
                        .. " damage=" .. tostring(laser.CollisionDamage)
                        .. " scale=" .. tostring(laser:GetScale()))
                end
            end
            if laser.FrameCount == 0 and unmatchedSamples >= 12 then
                local spawner = laser.SpawnerEntity
                local player = spawner and spawner:ToPlayer()
                if player and player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
                    and player:HasCollectible(CollectibleType.COLLECTIBLE_HAEMOLACRIA) then
                    pending[laser.InitSeed] = {
                        laser = EntityPtr(laser),
                        frame = Game():GetFrameCount(),
                    }
                end
            end
            return
        end

        local beforeDamage = laser.CollisionDamage
        local beforeScale = laser:GetScale()
        local beforeMultiplier = laser:GetDamageMultiplier()
        local player = source.Parent and source.Parent:ToPlayer()
        laser:GetData().AscentionMiniIsaacOwner =
            source:GetData().AscentionMiniIsaacOwner
        local factor = TARGET_DAMAGE / (player
            and player:GetPlayerType() == PlayerType.PLAYER_LILITH
            and 1.0 or INCUBUS_DAMAGE)

        laser:GetData()[SCALED_KEY] = true
        laser:SetDamageMultiplier(laser:GetDamageMultiplier() * factor)
        laser:SetScale(beforeScale * LASER_SCALE)
        laser:ResetSpriteScale()

        if samples < 20 then
            samples = samples + 1
            Isaac.DebugString("[AscentionMiniIsaac] split_laser source="
                .. tostring(source.InitSeed)
                .. " child=" .. tostring(source:GetData().AscentionMiniIsaacSplitChild)
                .. " source_damage=" .. tostring(source.CollisionDamage)
                .. " laser=" .. tostring(laser.InitSeed)
                .. " damage_before=" .. tostring(beforeDamage)
                .. " damage_after=" .. tostring(laser.CollisionDamage)
                .. " multiplier_before=" .. tostring(beforeMultiplier)
                .. " multiplier_after=" .. tostring(laser:GetDamageMultiplier())
                .. " scale_before=" .. tostring(beforeScale)
                .. " scale_after=" .. tostring(laser:GetScale())
                .. " factor=" .. tostring(factor))
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_LASER_INIT, correctLaser)
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, function(_, laser)
        if laser.FrameCount <= 2 then correctLaser(nil, laser) end
        if laser.FrameCount > 2 then pending[laser.InitSeed] = nil end
    end)
    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
        local frame = Game():GetFrameCount()
        if frame % 30 ~= 0 then return end
        for seed, entry in pairs(pending) do
            if frame - entry.frame > 2 then pending[seed] = nil end
        end
    end)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() pending = {} end)
end

return SplitLasers
