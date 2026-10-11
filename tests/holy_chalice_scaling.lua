package.preload.json = function()
    return { encode = function(value) return value end,
        decode = function(value) return value end }
end

ModCallbacks = { MC_POST_GAME_STARTED = 1,
    MC_POST_PLAYER_INIT = 2, MC_PRE_GAME_EXIT = 3 }
local callbacks = {}
local savedData
local mod = {
    AddCallback = function(_, id, callback) callbacks[id] = callback end,
    HasData = function() return savedData ~= nil end,
    LoadData = function() return savedData end,
    SaveData = function(_, value) savedData = value end,
}
local function player(rate, range)
    return {
        MaxFireDelay = 30 / rate - 1, TearRange = range, count = 0,
        GetCollectibleNum = function(self) return self.count end,
        GetData = function(self)
            self.data = self.data or {}
            return self.data
        end,
    }
end
local players = { player(2.3, 220), player(3, 260) }
Game = function() return { GetNumPlayers = function() return #players end } end
Isaac = { GetPlayer = function(index) return players[index + 1] end }

local Scaling = dofile("scripts/holy_chalice_scaling.lua")
Scaling.Register(mod, 9)
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.001,
        ("expected %.3f, got %.3f"):format(expected, actual))
end
local function setRate(actor, rate)
    actor.MaxFireDelay = 30 / rate - 1
end

callbacks[ModCallbacks.MC_POST_GAME_STARTED](nil, false)
players[1].count = 1
setRate(players[1], 2.6)
near(Scaling.StreamInterval(players[1], 9), 12 / 2.6)
near(Scaling.StreamInterval(players[1], 9, 2), 12 / 2.6 * 1.35)
near(Scaling.Range(players[1]), 220)

setRate(players[1], 3.6)
players[1].TearRange = 320
near(Scaling.StreamInterval(players[1], 9), 12 / 3.3)
near(Scaling.Range(players[1]), 270)
near(30 / (players[1].MaxFireDelay + 1), 3.6)
near(players[1].TearRange, 320)

CollectibleType = { COLLECTIBLE_INNER_EYE = 1,
    COLLECTIBLE_MUTANT_SPIDER = 2, COLLECTIBLE_20_20 = 3,
    COLLECTIBLE_THE_WIZ = 4 }
PlayerForm = { PLAYERFORM_BABY = 1 }
local Multishot = dofile("scripts/holy_chalice_multishot.lua")
local layout = {
    items = {}, forms = {},
    GetCollectibleNum = function(self, id) return self.items[id] or 0 end,
    HasCollectible = function(self, id) return (self.items[id] or 0) > 0 end,
    HasPlayerForm = function(self, id) return self.forms[id] or false end,
}
near(Multishot.ExpectedProjectiles(layout), 1)
near(Multishot.CooldownProjectiles(layout), 1)
near(Multishot.CooldownMultiplier(layout), 1)
layout.items[CollectibleType.COLLECTIBLE_20_20] = 1
near(Multishot.ExpectedProjectiles(layout), 2)
near(Multishot.CooldownProjectiles(layout), 2)
layout.items[CollectibleType.COLLECTIBLE_20_20] = nil
layout.items[CollectibleType.COLLECTIBLE_INNER_EYE] = 1
near(Multishot.ExpectedProjectiles(layout), 6)
layout.items[CollectibleType.COLLECTIBLE_INNER_EYE] = nil
layout.items[CollectibleType.COLLECTIBLE_MUTANT_SPIDER] = 1
near(Multishot.ExpectedProjectiles(layout), 12)
near(Multishot.CooldownProjectiles(layout), 12)
layout.items[CollectibleType.COLLECTIBLE_THE_WIZ] = 1
near(Multishot.ExpectedProjectiles(layout), 24)
near(Multishot.CooldownProjectiles(layout), 24)
layout.items[CollectibleType.COLLECTIBLE_MUTANT_SPIDER] = nil
layout.items[CollectibleType.COLLECTIBLE_THE_WIZ] = nil
layout.forms[PlayerForm.PLAYERFORM_BABY] = true
near(Multishot.ExpectedProjectiles(layout), 6)
near(Multishot.CooldownProjectiles(layout), 1)
near(Multishot.CooldownMultiplier(layout), 1.10)
near(Scaling.StreamInterval(players[1], 9,
    Multishot.CooldownProjectiles(layout), Multishot.CooldownMultiplier(layout)),
    12 / 3.3 * 1.10)
local rng = { RandomInt = function()
    error("Conjoined's expected count must not consume RNG")
end }
local lanes = Multishot.Clusters(layout, rng)
near(#lanes, 3)
near(lanes[1].angle, -30)
near(lanes[2].angle, 0)
near(lanes[3].angle, 30)
assert(lanes[1].size == 2 and lanes[2].size == 2
    and lanes[3].size == 2,
    "each Conjoined direction must have a two-bubble stream")
layout.items[CollectibleType.COLLECTIBLE_THE_WIZ] = 1
near(Multishot.ExpectedProjectiles(layout), 12)
near(Multishot.CooldownProjectiles(layout), 2)
lanes = Multishot.Clusters(layout, rng)
near(#lanes, 6)
near(lanes[1].angle, -75)
near(lanes[6].angle, 75)
layout.items[CollectibleType.COLLECTIBLE_THE_WIZ] = nil
layout.items[CollectibleType.COLLECTIBLE_INNER_EYE] = 1
near(Multishot.ExpectedProjectiles(layout), 27)
near(Multishot.CooldownProjectiles(layout), 6)
layout.items[CollectibleType.COLLECTIBLE_INNER_EYE] = nil
layout.items[CollectibleType.COLLECTIBLE_20_20] = 1
near(Multishot.ExpectedProjectiles(layout), 12)
near(Multishot.CooldownProjectiles(layout), 2)
layout.items[CollectibleType.COLLECTIBLE_20_20] = nil
layout.items[CollectibleType.COLLECTIBLE_MUTANT_SPIDER] = 1
near(Multishot.ExpectedProjectiles(layout), 48)
near(Multishot.CooldownProjectiles(layout), 12)
near(Multishot.CooldownMultiplier(layout), 1.10)
near(Scaling.StreamInterval(players[1], 9, Multishot.CooldownProjectiles(layout)),
    12 / 3.3 * (1 + 11 * 0.35))
near(Scaling.StreamInterval(players[1], 9,
    Multishot.CooldownProjectiles(layout), Multishot.CooldownMultiplier(layout)),
    12 / 3.3 * (1 + 11 * 0.35) * 1.10)
layout.forms[PlayerForm.PLAYERFORM_BABY] = nil
near(Multishot.CooldownProjectiles(layout), 12)
near(Multishot.CooldownMultiplier(layout), 1)
near(Scaling.StreamInterval(players[1], 9, 12),
    12 / 3.3 * (1 + 11 * 0.35))

players[2].count = 1
setRate(players[2], 4.3)
players[2].TearRange = 360
near(Scaling.StreamInterval(players[2], 9), 3)
near(Scaling.Range(players[2]), 310)

savedData = { goldenEyeKills = { ["0"] = 17 } }
callbacks[ModCallbacks.MC_PRE_GAME_EXIT](nil)
assert(savedData.goldenEyeKills["0"] == 17)
near(savedData.holyChaliceBaseStats["0"].rate, 2.3)
assert(savedData.holyChaliceBaseStats["1"].range == 260)

players[1].data = {}
players[2].data = {}
callbacks[ModCallbacks.MC_POST_GAME_STARTED](nil, true)
near(Scaling.StreamInterval(players[1], 9), 12 / 3.3)
near(Scaling.Range(players[1]), 270)

print("holy_chalice_scaling: OK")
