local callbacks = {}
ModCallbacks = { MC_POST_TEAR_INIT = 1, MC_POST_FIRE_TEAR = 2 }
local mod = { AddCallback = function(_, id, fn) callbacks[id] = fn end }
local rolls = 0
local nextRoll = 0.14
RNG = function()
    return {
        SetSeed = function(_, seed) assert(seed == 123) end,
        RandomFloat = function()
            rolls = rolls + 1
            return nextRoll
        end,
    }
end
local tagged = 0
local eyeOfSun = { MarkOldGodTear = function() tagged = tagged + 1 end }
local player = {
    Luck = 0,
    ToPlayer = function(self) return self end,
    HasCollectible = function() return true end,
}
local tear = {
    InitSeed = 123,
    SpawnerEntity = player,
    data = {},
    GetData = function(self) return self.data end,
}
local module = dofile("scripts/eye_of_old_god.lua")
module.Register(mod, 1000, eyeOfSun)
callbacks[ModCallbacks.MC_POST_TEAR_INIT](nil, tear)
callbacks[ModCallbacks.MC_POST_FIRE_TEAR](nil, tear)
assert(rolls == 1 and tagged == 1)
assert(module.Chance(0) == 0.15)
assert(module.Chance(14) == 0.5)
assert(module.Chance(30) == 0.5)

local proxy = { ToPlayer = function() return nil end }
local proxyTear = {
    InitSeed = 123,
    SpawnerEntity = proxy,
    data = {},
    GetData = function(self) return self.data end,
}
callbacks[ModCallbacks.MC_POST_FIRE_TEAR](nil, proxyTear)
assert(rolls == 1 and tagged == 1)
print("eye_of_old_god: OK")
