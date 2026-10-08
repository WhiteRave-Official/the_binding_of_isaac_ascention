local callbacks = {}
ModCallbacks = {
    MC_FAMILIAR_UPDATE = 1,
    MC_NPC_UPDATE = 2,
    MC_ENTITY_TAKE_DMG = 3,
}
EntityType = { ENTITY_NPC = 5 }
EntityFlag = { FLAG_FRIENDLY = 1 }
local mod = { AddCallback = function(_, id, fn) callbacks[id] = fn end }
local player = {
    count = 1,
    ToPlayer = function(self) return self end,
    GetCollectibleNum = function(self) return self.count end,
}
local familiar = {
    Player = player,
    MaxHitPoints = 10,
    HitPoints = 10,
    FireCooldown = 30,
    data = {},
    ToPlayer = function() return nil end,
    ToFamiliar = function(self) return self end,
    GetData = function(self) return self.data end,
}
local npc = {
    ToNPC = function(self) return self end,
    HasEntityFlags = function() return false end,
}
local pendant = dofile("scripts/heart_pendant.lua")
pendant.Register(mod, 1001)
callbacks[ModCallbacks.MC_FAMILIAR_UPDATE](nil, familiar)
assert(familiar.MaxHitPoints == 12 and familiar.HitPoints == 12)
for _ = 2, 16 do
    familiar.FireCooldown = familiar.FireCooldown - 1
    callbacks[ModCallbacks.MC_FAMILIAR_UPDATE](nil, familiar)
end
assert(familiar.FireCooldown == 0)
familiar.MaxHitPoints = 10
familiar.HitPoints = 10
callbacks[ModCallbacks.MC_FAMILIAR_UPDATE](nil, familiar)
assert(familiar.MaxHitPoints == 12 and familiar.HitPoints == 12)
local hit = callbacks[ModCallbacks.MC_ENTITY_TAKE_DMG](nil, npc, 10,
    0, { Entity = familiar }, 0)
assert(hit.Damage == 11)
assert(callbacks[ModCallbacks.MC_ENTITY_TAKE_DMG](nil, npc, 10,
    0, { Entity = player }, 0) == nil)

local weapon = {
    delay = 30,
    GetFireDelay = function(self) return self.delay end,
    GetMaxFireDelay = function() return 30 end,
    SetFireDelay = function(self, value) self.delay = value end,
}
local incubus = {
    Player = player,
    FireCooldown = 30,
    data = {},
    GetWeapon = function() return weapon end,
    GetData = function(self) return self.data end,
}
callbacks[ModCallbacks.MC_FAMILIAR_UPDATE](nil, incubus)
assert(weapon.delay == 29 and incubus.FireCooldown == 30)
for _ = 2, 16 do
    weapon.delay = weapon.delay - 1
    callbacks[ModCallbacks.MC_FAMILIAR_UPDATE](nil, incubus)
end
assert(weapon.delay == 0)

player.count = 0
callbacks[ModCallbacks.MC_FAMILIAR_UPDATE](nil, familiar)
assert(familiar.MaxHitPoints == 10 and familiar.HitPoints == 10)
assert(callbacks[ModCallbacks.MC_ENTITY_TAKE_DMG](nil, npc, 10,
    0, { Entity = familiar }, 0) == nil)
print("heart_pendant: OK")
