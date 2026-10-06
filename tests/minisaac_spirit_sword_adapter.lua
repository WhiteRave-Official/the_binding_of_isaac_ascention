local proxy, mini
include = function(path)
    assert(path == "scripts.minisaac.arclight_context")
    return {
        ForProjectile = function() return proxy end,
        MiniForSource = function() return mini end,
    }
end
PlayerType = { PLAYER_LILITH = 7 }
EntityType = { ENTITY_NPC = 5 }
ModCallbacks = { MC_POST_FIRE_SWORD = 1, MC_ENTITY_TAKE_DMG = 2 }
local callbacks = {}
local mod = { AddCallback = function(_, id, fn) callbacks[id] = fn end }
local frame = 100
Game = function() return { GetFrameCount = function() return frame end } end
Isaac = { DebugString = function() end }
AscentionNative = { FiringProxySeed = function() return proxy.InitSeed end }

local function entity(seed)
    local value = { InitSeed = seed, data = {} }
    function value:GetData() return self.data end
    function value:Exists() return true end
    function value:ToKnife() return nil end
    function value:ToFamiliar() return nil end
    return value
end
local player = entity(1)
function player:GetPlayerType() return 0 end
mini = entity(2)
function mini:ToFamiliar() return self end
proxy = entity(3)
proxy.Player = player
function proxy:ToFamiliar() return self end
local sword = entity(4)
function sword:ToKnife() return self end
function sword:GetHitboxParentKnife() return nil end
function sword:GetIsSpinAttack() return self.spin or false end
function sword:SetIsSpinAttack(value) self.spin = value end
function sword:GetSprite()
    return {
        HasAnimation = function(_, name) return name == "SpinRight" end,
        Play = function(_, name) self.animation = name end,
    }
end
local npc = entity(5)
function npc:ToNPC() return self end

dofile("scripts/minisaac/spirit_sword_adapter.lua").Register(mod)
callbacks[ModCallbacks.MC_POST_FIRE_SWORD](nil, sword)
assert(not sword:GetIsSpinAttack())
AscentionNative.FiringProxySeed = function() return 0 end
local externalSword = entity(7)
function externalSword:ToKnife() return self end
callbacks[ModCallbacks.MC_POST_FIRE_SWORD](nil, externalSword)
assert(externalSword.data.AscentionMiniIsaacSpiritSwordFactor == nil)
AscentionNative.FiringProxySeed = function() return proxy.InitSeed end
local factor = 0.15 / 0.75
assert(sword.data.AscentionMiniIsaacSpiritSwordFactor == factor)
assert(callbacks[ModCallbacks.MC_ENTITY_TAKE_DMG](nil, npc, 20, 0,
    { Entity = sword }, 0).Damage == 20 * factor)

local hitbox = entity(6)
function hitbox:ToKnife() return self end
function hitbox:GetHitboxParentKnife() return sword end
assert(callbacks[ModCallbacks.MC_ENTITY_TAKE_DMG](nil, npc, 20, 0,
    { Entity = hitbox }, 0).Damage == 20 * factor)
assert(callbacks[ModCallbacks.MC_ENTITY_TAKE_DMG](nil, npc, 20, 0,
    { Entity = mini }, 0).Damage == 20 * factor)
frame = 131
assert(callbacks[ModCallbacks.MC_ENTITY_TAKE_DMG](nil, npc, 20, 0,
    { Entity = mini }, 0) == nil)
assert(callbacks[ModCallbacks.MC_ENTITY_TAKE_DMG](nil, npc, 20, 0,
    { Entity = player }, 0) == nil)
print("minisaac_spirit_sword_adapter: OK")
