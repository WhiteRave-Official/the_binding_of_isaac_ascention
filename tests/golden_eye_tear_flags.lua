package.loaded.json = { encode = function() end, decode = function() end }

FamiliarVariant = { INCUBUS = 1 }
local nextCallbackId = 1
ModCallbacks = setmetatable({ MC_EVALUATE_CACHE = 1 }, {
    __index = function(self, key)
        nextCallbackId = nextCallbackId + 1
        rawset(self, key, nextCallbackId)
        return nextCallbackId
    end,
})
CacheFlag = { CACHE_FAMILIARS = 1, CACHE_FIREDELAY = 2, CACHE_TEARFLAG = 3 }
TearFlags = { TEAR_HOMING = 1, TEAR_SPECTRAL = 2 }

local callbacks = {}
local mod = {
    AddCallback = function(_, id, callback)
        callbacks[id] = callback
    end,
}
local goldenEye = dofile("scripts/golden_eye.lua")
goldenEye.Register(mod, 1234, 5678, {})

local player = {
    TearFlags = 0,
    HasCollectible = function(_, id) return id == 1234 end,
}
callbacks[ModCallbacks.MC_EVALUATE_CACHE](mod, player, CacheFlag.CACHE_TEARFLAG)
assert(player.TearFlags & TearFlags.TEAR_HOMING ~= 0)
assert(player.TearFlags & TearFlags.TEAR_SPECTRAL ~= 0)

local otherPlayer = {
    TearFlags = 0,
    HasCollectible = function() return false end,
}
callbacks[ModCallbacks.MC_EVALUATE_CACHE](mod, otherPlayer, CacheFlag.CACHE_TEARFLAG)
assert(otherPlayer.TearFlags == 0)
print("golden eye tear flags: OK")