local Aggro = {}

local RADIUS_SQUARED = 90 * 90
local REFRESH_INTERVAL = 6
local TARGET_DURATION = 10
local cachedFrame = -1
local minis = {}

local function activeMinis()
    local frame = Game():GetFrameCount()
    if cachedFrame ~= frame then
        cachedFrame = frame
        minis = Isaac.FindByType(EntityType.ENTITY_FAMILIAR,
            FamiliarVariant.MINISAAC)
    end
    return minis
end

function Aggro.Register(mod)
    mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, function(_, npc)
        if (Game():GetFrameCount() + npc.InitSeed) % REFRESH_INTERVAL ~= 0
            or not npc:IsActiveEnemy(false)
            or npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            or npc:HasEntityFlags(EntityFlag.FLAG_NO_STATUS_EFFECTS) then
            return
        end

        local nearest, distance = nil, RADIUS_SQUARED
        for _, mini in ipairs(activeMinis()) do
            if mini:Exists() and mini.HitPoints > 0 then
                local current = npc.Position:DistanceSquared(mini.Position)
                if current < distance
                    or (current == distance and nearest
                        and mini.InitSeed < nearest.InitSeed) then
                    nearest, distance = mini, current
                end
            end
        end

        if nearest then npc:TryForceTarget(nearest, TARGET_DURATION) end
    end)
end

return Aggro
