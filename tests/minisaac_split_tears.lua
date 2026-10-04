ModCallbacks = {
    MC_POST_TEAR_INIT = 1,
    MC_POST_FIRE_SPLIT_TEAR = 2,
}
Isaac = { DebugString = function() end }
Vector = function(x, y) return { X = x, Y = y } end

local callbacks = {}
local mod = {
    AddCallback = function(_, id, callback) callbacks[id] = callback end,
}
dofile("scripts/minisaac/split_tears.lua").Register(mod)

local function entity(seed, x, y, familiar, tear)
    local value = {
        InitSeed = seed,
        Position = Vector(x, y),
        Velocity = Vector(4, 2),
        Scale = 0.8,
        data = {},
    }
    function value:GetData() return self.data end
    function value:ToFamiliar() return familiar and self or nil end
    function value:ToTear() return tear and self or nil end
    function value:Exists() return true end
    return value
end

local proxy = entity(1, 0, 0, true, false)
proxy.data.AscentionMiniIsaacWeaponProxy = true
local source = entity(2, 100, 120, false, true)
source.data.AscentionMiniIsaacNativeAimed = true

local child = entity(3, 100, 120, false, true)
child.SpawnerEntity = proxy
callbacks[ModCallbacks.MC_POST_TEAR_INIT](nil, child)
child.Position = Vector(20, 30)
child.Velocity = Vector(8, 0)
child.Scale = 0.48
child.data.AscentionMiniIsaacNativeAimed = true
callbacks[ModCallbacks.MC_POST_FIRE_SPLIT_TEAR](nil, child, source)
assert(child.Position.X == 100 and child.Position.Y == 120)
assert(child.Velocity.X == 4 and child.Velocity.Y == 2)
assert(child.Scale == 0.8)
assert(child.data.AscentionMiniIsaacSplitChild)
assert(child.data.AscentionMiniIsaacNativeScaled)
assert(not child.data.AscentionMiniIsaacNativeAimed)

local inherited = entity(4, 10, 10, false, true)
inherited.SpawnerEntity = source
callbacks[ModCallbacks.MC_POST_TEAR_INIT](nil, inherited)
callbacks[ModCallbacks.MC_POST_FIRE_SPLIT_TEAR](nil, inherited, source)
assert(inherited.Position.X == 100 and inherited.Position.Y == 120)
assert(inherited.data.AscentionMiniIsaacSplitChild)

local unrelated = entity(5, 10, 10, false, true)
callbacks[ModCallbacks.MC_POST_FIRE_SPLIT_TEAR](nil, unrelated, nil)
assert(unrelated.Position.X == 10 and unrelated.Position.Y == 10)
assert(not unrelated.data.AscentionMiniIsaacSplitChild)
