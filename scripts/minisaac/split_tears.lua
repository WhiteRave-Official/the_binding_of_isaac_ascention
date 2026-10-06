local SplitTears = {}

local SNAPSHOT_KEY = "AscentionMiniIsaacPreAim"
local CHILD_KEY = "AscentionMiniIsaacSplitChild"
local SWORD_FACTOR_KEY = "AscentionMiniIsaacSpiritSwordFactor"
local SWORD_DAMAGE_CAP_KEY = "AscentionMiniIsaacSpiritSwordDamageCap"

local function isProxy(entity)
    local familiar = entity and entity:ToFamiliar()
    return familiar and familiar:GetData().AscentionMiniIsaacWeaponProxy or false
end

function SplitTears.Register(mod, splitLasers)
    if not ModCallbacks.MC_POST_FIRE_SPLIT_TEAR then return end
    local correctedSamples = 0
    local damageSamples = 0

    -- Registered before native_weapon_adapter: capture the engine's split
    -- trajectory before the generic proxy tear redirect can modify it.
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, function(_, tear)
        if not isProxy(tear.SpawnerEntity) then return end
        tear:GetData()[SNAPSHOT_KEY] = {
            position = Vector(tear.Position.X, tear.Position.Y),
            velocity = Vector(tear.Velocity.X, tear.Velocity.Y),
            scale = tear.Scale,
        }
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_SPLIT_TEAR, function(_, child, source)
        local data = child:GetData()
        local snapshot = data[SNAPSHOT_KEY]
        local sourceData = source and source:GetData()
        if not snapshot and not (sourceData and
                (sourceData.AscentionMiniIsaacNativeAimed or sourceData[CHILD_KEY]
                    or sourceData[SWORD_FACTOR_KEY])) then
            return
        end

        local damageBefore = child.CollisionDamage
        local sourceDamage = source and source.CollisionDamage
        local sourceScaled = sourceData and sourceData.AscentionMiniIsaacNativeScaled
        local childScaled = data.AscentionMiniIsaacNativeScaled
        local proxy = child.SpawnerEntity
        data.AscentionMiniIsaacOwner = sourceData
            and sourceData.AscentionMiniIsaacOwner
            or (isProxy(proxy) and proxy:GetData().AscentionMiniIsaacProxyOwner)

        if source and source:ToTear() and source:Exists() then
            child.Position = source.Position
        elseif snapshot then
            child.Position = snapshot.position
        end
        if snapshot then
            child.Velocity = snapshot.velocity
            child.Scale = snapshot.scale
        end
        if splitLasers then splitLasers.CorrectSplit(child, source) end
        -- Sword-generated split tears bypass the normal Incubus tear damage path.
        local swordFactor = sourceData and sourceData[SWORD_FACTOR_KEY]
        if swordFactor then
            child.CollisionDamage = math.min(child.CollisionDamage * swordFactor,
                sourceData[SWORD_DAMAGE_CAP_KEY])
        end
        data.AscentionMiniIsaacNativeAimed = nil
        data.AscentionMiniIsaacNativeScaled = true
        data[CHILD_KEY] = true
        data[SNAPSHOT_KEY] = nil
        if damageSamples < 20 then
            damageSamples = damageSamples + 1
            local player = isProxy(proxy) and proxy.Player
            data.AscentionMiniIsaacSplitDamageLog = true
            Isaac.DebugString("[AscentionMiniIsaac] split_damage stage=spawn frame="
                .. tostring(Game():GetFrameCount())
                .. " child=" .. tostring(child.InitSeed)
                .. " source=" .. tostring(source and source.InitSeed)
                .. " player=" .. tostring(player and player.Damage)
                .. " source_damage=" .. tostring(sourceDamage)
                .. " source_scaled=" .. tostring(sourceScaled)
                .. " child_before=" .. tostring(damageBefore)
                .. " child_before_scaled=" .. tostring(childScaled)
                .. " child_after=" .. tostring(child.CollisionDamage)
                .. " child_after_scaled=" .. tostring(data.AscentionMiniIsaacNativeScaled))
        end
        if isProxy(proxy) then
            local proxyData = proxy:GetData()
            if proxyData.AscentionMiniIsaacTearSourceSeed == child.InitSeed then
                proxyData.AscentionMiniIsaacTearSourceFrame = nil
                proxyData.AscentionMiniIsaacTearSource = nil
                proxyData.AscentionMiniIsaacTearSourceSeed = nil
            end
        end
        if correctedSamples < 6 then
            correctedSamples = correctedSamples + 1
            Isaac.DebugString("[AscentionMiniIsaac] split_restore child="
                .. tostring(child.InitSeed) .. " source="
                .. tostring(source and source.InitSeed)
                .. " position=" .. tostring(child.Position.X) .. ","
                .. tostring(child.Position.Y))
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
        local data = tear:GetData()
        if not data.AscentionMiniIsaacSplitDamageLog or tear.FrameCount < 1 then return end
        data.AscentionMiniIsaacSplitDamageLog = nil
        Isaac.DebugString("[AscentionMiniIsaac] split_damage stage=update frame="
            .. tostring(Game():GetFrameCount())
            .. " child=" .. tostring(tear.InitSeed)
            .. " damage=" .. tostring(tear.CollisionDamage)
            .. " scaled=" .. tostring(data.AscentionMiniIsaacNativeScaled))
    end)
end

return SplitTears
