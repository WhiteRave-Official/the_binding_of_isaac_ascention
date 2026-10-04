local SplitTears = {}

local SNAPSHOT_KEY = "AscentionMiniIsaacPreAim"
local CHILD_KEY = "AscentionMiniIsaacSplitChild"

local function isProxy(entity)
    local familiar = entity and entity:ToFamiliar()
    return familiar and familiar:GetData().AscentionMiniIsaacWeaponProxy or false
end

function SplitTears.Register(mod)
    if not ModCallbacks.MC_POST_FIRE_SPLIT_TEAR then return end
    local correctedSamples = 0

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
                (sourceData.AscentionMiniIsaacNativeAimed or sourceData[CHILD_KEY])) then
            return
        end

        if source and source:ToTear() and source:Exists() then
            child.Position = source.Position
        elseif snapshot then
            child.Position = snapshot.position
        end
        if snapshot then
            child.Velocity = snapshot.velocity
            child.Scale = snapshot.scale
        end
        data.AscentionMiniIsaacNativeAimed = nil
        data.AscentionMiniIsaacNativeScaled = true
        data[CHILD_KEY] = true
        data[SNAPSHOT_KEY] = nil
        local proxy = child.SpawnerEntity
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
end

return SplitTears
