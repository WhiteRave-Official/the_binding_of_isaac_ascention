ModCallbacks = { MC_PRE_FAMILIAR_UPDATE = 1, MC_ENTITY_TAKE_DMG = 2,
    MC_FAMILIAR_UPDATE = 3 }
FamiliarVariant = { MINISAAC = 1, INCUBUS = 2 }
EntityType = { ENTITY_FAMILIAR = 3 }
Isaac = { GetPlayerTypeByName = function() return 41 end,
    DebugString = function() end }
Game = function() return { GetFrameCount = function() return 1 end } end

local callbacks = {}
local mod = { AddCallback = function(_, kind, callback, filter)
    callbacks[kind] = callbacks[kind] or {}
    callbacks[kind][#callbacks[kind] + 1] = { callback, filter }
end }
local function run(kind, filter, entity)
    for _, entry in ipairs(callbacks[kind] or {}) do
        if entry[2] == filter then entry[1](mod, entity) end
    end
end

local bonus = 0
local player = { MaxFireDelay = 119,
    GetPlayerType = function() return 41 end }
local mini = { Variant = FamiliarVariant.MINISAAC, Player = player,
    InitSeed = 1, SubType = 7345, HitPoints = 20, MaxHitPoints = 20,
    data = {} }
function mini:GetData() return self.data end
local tiara = { HealthBonus = function() return bonus end }
dofile("scripts/minisaac/geburah_health.lua").Register(mod, tiara)
run(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, FamiliarVariant.MINISAAC, mini)
assert(mini.MaxHitPoints == 25 and mini.HitPoints == 25)
bonus = 10
run(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, FamiliarVariant.MINISAAC, mini)
assert(mini.MaxHitPoints == 35 and mini.HitPoints == 35)
mini.HitPoints = 12
run(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, FamiliarVariant.MINISAAC, mini)
assert(mini.HitPoints == 12, "existing damage must not be healed every frame")
bonus = 0
run(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, FamiliarVariant.MINISAAC, mini)
assert(mini.MaxHitPoints == 25 and mini.HitPoints == 2)
mini.MaxHitPoints = 30
mini.HitPoints = 30
bonus = 10
run(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, FamiliarVariant.MINISAAC, mini)
assert(mini.MaxHitPoints == 42 and mini.HitPoints == 42,
    "tier IV health must retain existing multiplicative health bonuses")
bonus = 0
run(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, FamiliarVariant.MINISAAC, mini)
assert(mini.MaxHitPoints == 30 and mini.HitPoints == 30)

local charge = 30
local fireDelay = 119
local weapon = {
    GetFireDelay = function() return fireDelay end,
    SetFireDelay = function(_, value) fireDelay = value end,
    GetMaxCharge = function() return 120 end,
    GetCharge = function() return charge end,
    SetCharge = function(_, value) charge = value end,
}
local proxy = { data = { AscentionMiniIsaacProxyOwner = { Ref = mini } },
    GetData = function(self) return self.data end,
    GetWeapon = function() return weapon end }
function mini:Exists() return true end
local rate = dofile("scripts/minisaac/geburah_fire_rate.lua")
rate.Register(mod)
run(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, FamiliarVariant.INCUBUS, proxy)
assert(fireDelay == 59 and charge == 30,
    "native proxy handles charge acceleration")
assert(rate.MaximumCycle(player) == 60)
assert(rate.EffectiveCharge(player, 120) == 59)
assert(rate.EffectiveCooldown(player, 120) == 60)
assert(rate.MinimumRate(player) == 0.5)
local other = { MaxFireDelay = 119, GetPlayerType = function() return 0 end }
assert(rate.EffectiveCharge(other, 120) == 120)
assert(rate.EffectiveCooldown(other, 120) == 120)
assert(rate.MinimumRate(other) == nil)
assert(rate.MaximumCycle(other) == nil)
print("geburah minisaac stats: OK")
