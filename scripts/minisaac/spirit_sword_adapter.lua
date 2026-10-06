local MiniIsaacContext = include("scripts.minisaac.arclight_context")
local Adapter = {}

local SWORD_FACTOR_KEY = "AscentionMiniIsaacSpiritSwordFactor"
local SWORD_HIT_UNTIL_KEY = "AscentionMiniIsaacSpiritSwordHitUntil"
local TARGET_DAMAGE = 0.15
local INCUBUS_DAMAGE = 0.75
local HIT_WINDOW = 30

local function damageFactor(proxy)
    local player = proxy.Player
    local nativeMultiplier = player:GetPlayerType() == PlayerType.PLAYER_LILITH
        and 1.0 or INCUBUS_DAMAGE
    return TARGET_DAMAGE / nativeMultiplier
end

local function factorOf(entity)
    if not entity then return nil end
    local knife = entity:ToKnife()
    if knife then
        local factor = knife:GetData()[SWORD_FACTOR_KEY]
        if factor then return factor end
        local parent = knife:GetHitboxParentKnife()
        if parent and parent:Exists() then
            return parent:GetData()[SWORD_FACTOR_KEY]
        end
    end
    local familiar = entity:ToFamiliar()
    if not familiar then return nil end
    local data = familiar:GetData()
    local untilFrame = data[SWORD_HIT_UNTIL_KEY]
    if untilFrame and Game():GetFrameCount() <= untilFrame then
        return data[SWORD_FACTOR_KEY]
    end
    return nil
end

function Adapter.Register(mod)
    local swordSamples = 0
    local damageSamples = 0

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_SWORD, function(_, sword)
        local proxy = MiniIsaacContext.ForProjectile(sword)
        if not proxy then return end
        if not AscentionNative or not AscentionNative.FiringProxySeed
            or AscentionNative.FiringProxySeed() ~= proxy.InitSeed then return end
        local mini = MiniIsaacContext.MiniForSource(proxy)
        if not mini then return end
        local factor = damageFactor(proxy)
        local untilFrame = Game():GetFrameCount() + HIT_WINDOW
        sword:GetData()[SWORD_FACTOR_KEY] = factor
        proxy:GetData()[SWORD_FACTOR_KEY] = factor
        proxy:GetData()[SWORD_HIT_UNTIL_KEY] = untilFrame
        mini:GetData()[SWORD_FACTOR_KEY] = factor
        mini:GetData()[SWORD_HIT_UNTIL_KEY] = untilFrame
        if swordSamples < 8 then
            swordSamples = swordSamples + 1
            Isaac.DebugString("[AscentionMiniIsaac] spirit_sword_native mini="
                .. tostring(mini.InitSeed) .. " sword=" .. tostring(sword.InitSeed)
                .. " factor=" .. tostring(factor))
        end
    end)

    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG,
        function(_, entity, damage, _, source, _, extraSource)
            if not entity:ToNPC() then return end
            local extra = extraSource and extraSource.Entity
            local direct = source and source.Entity
            local factor = factorOf(extra) or factorOf(direct)
            if not factor then return end
            local scaled = damage * factor
            if damageSamples < 8 then
                damageSamples = damageSamples + 1
                Isaac.DebugString("[AscentionMiniIsaac] spirit_sword_damage raw="
                    .. tostring(damage) .. " scaled=" .. tostring(scaled)
                    .. " target=" .. tostring(entity.InitSeed))
            end
            return { Damage = scaled }
        end, EntityType.ENTITY_NPC)
end

return Adapter
