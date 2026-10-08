local callbacks = {}
ModCallbacks = {
    MC_EVALUATE_CACHE = 1,
    MC_PRE_ADD_COLLECTIBLE = 2,
    MC_POST_TRIGGER_COLLECTIBLE_ADDED = 3,
    MC_POST_TRIGGER_COLLECTIBLE_REMOVED = 4,
    MC_POST_PLAYER_UPDATE = 5,
    MC_POST_TRIGGER_TRINKET_ADDED = 6,
    MC_POST_TRIGGER_TRINKET_REMOVED = 7,
}
CacheFlag = {
    CACHE_DAMAGE = 1, CACHE_FIREDELAY = 2, CACHE_SPEED = 4,
    CACHE_RANGE = 8, CACHE_SHOTSPEED = 16, CACHE_LUCK = 32,
}
Isaac = { GetItemConfig = function()
    return { GetCollectible = function(_, id)
        if id == 42 then return { CacheFlags = CacheFlag.CACHE_DAMAGE } end
        if id == 43 then return { CacheFlags = CacheFlag.CACHE_RANGE } end
        if id == 44 then return { CacheFlags = CacheFlag.CACHE_LUCK } end
    end }
end }

local mod = { AddCallback = function(_, id, fn) callbacks[id] = fn end }
local player = {
    trinkets = 0, data = {}, Damage = 3.5, MaxFireDelay = 10,
    MoveSpeed = 1, TearRange = 260, ShotSpeed = 1, Luck = 0,
    raw = { Damage = 3.5, MaxFireDelay = 10, MoveSpeed = 1, TearRange = 260 },
    GetData = function(self) return self.data end,
    GetTrinketMultiplier = function(self) return self.trinkets end,
    AddCacheFlags = function(self, flags) self.cacheFlags = flags end,
}

dofile("scripts/broken_pendant.lua").Register(mod, 1001)
local evaluate = callbacks[ModCallbacks.MC_EVALUATE_CACHE]
local flags = { CacheFlag.CACHE_DAMAGE, CacheFlag.CACHE_FIREDELAY,
    CacheFlag.CACHE_SPEED, CacheFlag.CACHE_RANGE }
local properties = {
    [CacheFlag.CACHE_DAMAGE] = "Damage",
    [CacheFlag.CACHE_FIREDELAY] = "MaxFireDelay",
    [CacheFlag.CACHE_SPEED] = "MoveSpeed",
    [CacheFlag.CACHE_RANGE] = "TearRange",
}
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001,
        tostring(actual) .. " ~= " .. tostring(expected))
end
local function evaluateRaw(flag, value)
    local property = properties[flag]
    player.raw[property] = value
    player[property] = value
    evaluate(nil, player, flag)
end
player.EvaluateItems = function(self)
    self.evaluations = (self.evaluations or 0) + 1
    for _, flag in ipairs(flags) do
        if self.cacheFlags & flag ~= 0 then
            local property = properties[flag]
            self[property] = self.raw[property]
            evaluate(nil, self, flag)
        end
    end
end
local function addItem(id)
    callbacks[ModCallbacks.MC_PRE_ADD_COLLECTIBLE](nil, id, 0, true, 0, 0, player)
    callbacks[ModCallbacks.MC_POST_TRIGGER_COLLECTIBLE_ADDED](nil, player, id, true, false)
end
local function removeItem(id)
    callbacks[ModCallbacks.MC_POST_TRIGGER_COLLECTIBLE_REMOVED](nil, player, id)
    callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](nil, player)
end

for _, flag in ipairs(flags) do evaluate(nil, player, flag) end
player.trinkets = 1
evaluateRaw(CacheFlag.CACHE_DAMAGE, 2.5)
near(player.Damage, 2.7)
evaluateRaw(CacheFlag.CACHE_SPEED, 0.7)
near(player.MoveSpeed, 0.76)
evaluateRaw(CacheFlag.CACHE_FIREDELAY, 14)
near(30 / (player.MaxFireDelay + 1), 2 + (30 / 11 - 2) * 0.2)

-- Dead Eye-like temporary damage must not become a permanent reference.
evaluateRaw(CacheFlag.CACHE_DAMAGE, 6)
near(player.Damage, 6)
evaluateRaw(CacheFlag.CACHE_DAMAGE, 3.5)
near(player.Damage, 3.5)

-- Adding an item during a temporary boost records only the item's delta.
evaluateRaw(CacheFlag.CACHE_DAMAGE, 6)
addItem(42)
player.raw.Damage = 7
callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](nil, player)
near(player.Damage, 7)
evaluateRaw(CacheFlag.CACHE_DAMAGE, 4.5)
near(player.Damage, 4.5)
evaluateRaw(CacheFlag.CACHE_DAMAGE, 3.5)
near(player.Damage, 3.7)

-- The permanent range gain is a reference for later flat range penalties.
evaluateRaw(CacheFlag.CACHE_RANGE, 260)
addItem(43)
player.raw.TearRange = 380
callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](nil, player)
near(player.TearRange, 380)
evaluateRaw(CacheFlag.CACHE_RANGE, 300)
near(player.TearRange, 316)

-- Removing the item drops only its affected reference back to the base stat.
player.raw.Damage = 3.5
removeItem(42)
near(player.Damage, 3.5)
evaluateRaw(CacheFlag.CACHE_DAMAGE, 3)
near(player.Damage, 3.1)
evaluateRaw(CacheFlag.CACHE_RANGE, 300)
near(player.TearRange, 316)

-- Losing an item during a temporary boost must not lock that boost in.
evaluateRaw(CacheFlag.CACHE_DAMAGE, 6)
addItem(42)
player.raw.Damage = 7
callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](nil, player)
player.raw.Damage = 6
removeItem(42)
near(player.Damage, 6)
evaluateRaw(CacheFlag.CACHE_DAMAGE, 3.5)
near(player.Damage, 3.5)

player.raw.TearRange = 260
removeItem(43)
near(player.TearRange, 260)

local evaluations = player.evaluations
removeItem(44)
assert(player.evaluations == evaluations)
evaluate(nil, player, CacheFlag.CACHE_SHOTSPEED)
evaluate(nil, player, CacheFlag.CACHE_LUCK)
near(player.ShotSpeed, 1)
near(player.Luck, 0)

player.trinkets = 2
evaluateRaw(CacheFlag.CACHE_DAMAGE, 2.5)
near(player.Damage, 2.9)
player.trinkets = 0
player.raw.Damage = 2.5
callbacks[ModCallbacks.MC_POST_TRIGGER_TRINKET_REMOVED](nil, player, 1001)
near(player.Damage, 2.5)
assert(player.cacheFlags == 15)
print("broken_pendant: OK")
