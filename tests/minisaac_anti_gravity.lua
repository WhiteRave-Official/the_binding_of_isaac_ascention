local vectorMeta = {}
vectorMeta.__index = vectorMeta

Vector = function(x, y)
    return setmetatable({ X = x, Y = y }, vectorMeta)
end

function vectorMeta.__add(a, b) return Vector(a.X + b.X, a.Y + b.Y) end
function vectorMeta.__sub(a, b) return Vector(a.X - b.X, a.Y - b.Y) end
function vectorMeta.__mul(a, b)
    if type(a) == "number" then return Vector(a * b.X, a * b.Y) end
    return Vector(a.X * b, a.Y * b)
end
function vectorMeta:LengthSquared() return self.X * self.X + self.Y * self.Y end
function vectorMeta:GetAngleDegrees()
    return math.deg(math.atan(self.Y, self.X))
end
function vectorMeta:Rotated(angle)
    local radians = math.rad(angle)
    local cosine, sine = math.cos(radians), math.sin(radians)
    return Vector(self.X * cosine - self.Y * sine,
        self.X * sine + self.Y * cosine)
end

local nextCallback = 0
ModCallbacks = setmetatable({}, { __index = function(self, key)
    nextCallback = nextCallback + 1
    rawset(self, key, nextCallback)
    return nextCallback
end })
CollectibleType = { COLLECTIBLE_MONSTROS_LUNG = 1,
    COLLECTIBLE_TECHNOLOGY = 2, COLLECTIBLE_ANTI_GRAVITY = 3 }
PlayerType = { PLAYER_LILITH = 1 }
FamiliarVariant = { INCUBUS = 80 }
EntityType = { ENTITY_NPC = 1 }
TearFlags = { TEAR_SPECTRAL = 1, TEAR_FETUS = 2 }
TearVariant = { FETUS = 50 }
Isaac = { DebugString = function() end }
Game = function() return { GetFrameCount = function() return 42 end } end

local callbacks = {}
local mod = { AddCallback = function(_, id, callback)
    callbacks[id] = callback
end }
dofile("scripts/minisaac/native_weapon_adapter.lua").Register(mod)

local player = { Velocity = Vector(0, 0), antiGravity = true }
function player:GetPlayerType() return 0 end
function player:ToPlayer() return self end
function player:HasCollectible(id)
    return id == CollectibleType.COLLECTIBLE_ANTI_GRAVITY and self.antiGravity
end

local mini = { data = { AscentionMiniIsaacAim = Vector(0, 10) } }
function mini:GetData() return self.data end
function mini:Exists() return true end

local proxy = {
    InitSeed = 10,
    Position = Vector(100, 100),
    Player = player,
    data = {
        AscentionMiniIsaacWeaponProxy = true,
        AscentionMiniIsaacProxyOwner = { Ref = mini },
    },
}
function proxy:GetData() return self.data end
function proxy:ToFamiliar() return self end

local tear = {
    InitSeed = 11,
    SpawnerEntity = proxy,
    Position = Vector(100, 100),
    Velocity = Vector(0, 0),
    ContinueVelocity = Vector(10, 0),
    WaitFrames = 60,
    Scale = 1,
    data = {},
}
function tear:GetData() return self.data end
function tear:HasTearFlags() return false end

callbacks[ModCallbacks.MC_POST_TEAR_INIT](nil, tear)
assert(math.abs(tear.ContinueVelocity.X) < 0.001)
assert(math.abs(tear.ContinueVelocity.Y - 10) < 0.001)
assert(tear.Velocity:LengthSquared() == 0)
assert(tear.Scale == 0.6)

tear.ContinueVelocity = Vector(-10, 0)
tear.FrameCount = 2
callbacks[ModCallbacks.MC_PRE_TEAR_UPDATE](nil, tear)
assert(math.abs(tear.ContinueVelocity.Y - 10) < 0.001)

tear.WaitFrames = 0
tear.ContinueVelocity = Vector(0, 10)
callbacks[ModCallbacks.MC_PRE_TEAR_UPDATE](nil, tear)
assert(tear.ContinueVelocity.Y == 10)

proxy.data.AscentionMiniIsaacTearSourceFrame = nil
local late = {
    InitSeed = 12,
    SpawnerEntity = proxy,
    Position = Vector(100, 100),
    Velocity = Vector(10, 0),
    ContinueVelocity = Vector(0, 0),
    WaitFrames = 0,
    Scale = 1,
    data = {},
}
function late:GetData() return self.data end
function late:HasTearFlags() return false end
callbacks[ModCallbacks.MC_POST_TEAR_INIT](nil, late)
late.WaitFrames = 60
late.ContinueVelocity = Vector(10, 0)
late.FrameCount = 2
callbacks[ModCallbacks.MC_PRE_TEAR_UPDATE](nil, late)
assert(math.abs(late.ContinueVelocity.X) < 0.001)
assert(math.abs(late.ContinueVelocity.Y - 10) < 0.001)

local fetus = {
    InitSeed = 13,
    Variant = TearVariant.FETUS,
    SpawnerEntity = proxy,
    Parent = player,
    Position = Vector(100, 100),
    Velocity = Vector(10, 0),
    ContinueVelocity = Vector(0, 0),
    WaitFrames = 0,
    Scale = 1,
    SpriteScale = Vector(1.2, 1.2),
    CollisionDamage = 3,
    FrameCount = 1,
    data = {},
}
function fetus:GetData() return self.data end
function fetus:HasTearFlags() return false end
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](nil, fetus)
assert(math.abs(fetus.SpriteScale.X - 0.72) < 0.001)
assert(math.abs(fetus.SpriteScale.Y - 0.72) < 0.001)
assert(math.abs(fetus.CollisionDamage - 0.6) < 0.001)
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](nil, fetus)
assert(math.abs(fetus.SpriteScale.X - 0.72) < 0.001)
assert(math.abs(fetus.CollisionDamage - 0.6) < 0.001)
print("minisaac_anti_gravity: OK")
