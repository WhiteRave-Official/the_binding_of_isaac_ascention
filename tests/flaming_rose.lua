local names = {
    "MC_POST_TEAR_INIT", "MC_POST_FIRE_TEAR", "MC_POST_FIRE_SPLIT_TEAR",
    "MC_POST_TEAR_UPDATE", "MC_POST_ENTITY_TAKE_DMG", "MC_POST_EFFECT_UPDATE",
    "MC_POST_LASER_INIT", "MC_POST_FIRE_TECH_LASER",
    "MC_POST_FIRE_TECH_X_LASER", "MC_POST_FIRE_KNIFE",
    "MC_POST_FIRE_BOMB", "MC_POST_LASER_UPDATE",
}
ModCallbacks = {}
for index, name in ipairs(names) do ModCallbacks[name] = index end
DamageFlag = { DAMAGE_POISON_BURN = 2 }
EntityType = { ENTITY_NPC = 5, ENTITY_EFFECT = 1000 }
EntityFlag = { FLAG_FRIENDLY = 1 }
EffectVariant = { RED_CANDLE_FLAME = 52 }
EntityPtr = function(entity) return { Ref = entity } end
EntityRef = function(entity) return { Entity = entity } end

local vectorMeta = {}
vectorMeta.__add = function(a, b) return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y }, vectorMeta) end
vectorMeta.__mul = function(a, b) return setmetatable({ X = a.X * b, Y = a.Y * b }, vectorMeta) end
Vector = {
    FromAngle = function(degrees)
        local radians = math.rad(degrees)
        return setmetatable({ X = math.cos(radians), Y = math.sin(radians) }, vectorMeta)
    end,
}
setmetatable(Vector, {
    __call = function(_, x, y)
        return setmetatable({ X = x, Y = y }, vectorMeta)
    end,
})
RNG = function()
    return {
        SetSeed = function(self, seed) self.seed = seed end,
        RandomInt = function(self, limit) return self.seed % limit end,
    }
end

local callbacks = {}
local mod = { AddCallback = function(_, id, callback) callbacks[id] = callback end }
local flames = {}
local frame = 0
Game = function() return { GetFrameCount = function() return frame end } end
Isaac = {
    Spawn = function(_, variant, _, position, velocity, owner)
        assert(variant == EffectVariant.RED_CANDLE_FLAME)
        local effect = { Position = position, Velocity = velocity, SpawnerEntity = owner, data = {} }
        function effect:ToEffect() return self end
        function effect:GetData() return self.data end
        flames[#flames + 1] = effect
        return effect
    end,
}

local owner = { HasCollectible = function() return true end, Exists = function() return true end }
function owner:ToPlayer() return self end
function owner:ToTear() return nil end
function owner:ToLaser() return nil end
function owner:ToKnife() return nil end
function owner:ToBomb() return nil end
local sprite = { filename = "gfx/002.000_tear.anm2", animation = "" }
function sprite:GetFilename() return self.filename end
function sprite:Load(path) self.filename = path end
function sprite:GetAnimation() return self.animation end
function sprite:Play(animation) self.animation = animation end
local tear = {
    InitSeed = 123, CollisionDamage = 2.5, SpawnerEntity = owner,
    Velocity = Vector.FromAngle(0), data = {}, flags = 0,
}
function tear:GetData() return self.data end
function tear:GetSprite() return sprite end
function tear:ToTear() return self end
function tear:ToLaser() return nil end
function tear:ToKnife() return nil end
function tear:ToBomb() return nil end
function tear:AddTearFlags(flag) self.flags = self.flags | flag end
function tear:HasTearFlags(flag) return (self.flags & flag) ~= 0 end
local npc = { InitSeed = 456, Position = Vector.FromAngle(0), Size = 12 }
function npc:GetData()
    self.data = self.data or {}
    return self.data
end
function npc:ToNPC() return self end
function npc:IsActiveEnemy() return true end
function npc:HasEntityFlags() return false end
function npc:AddBurn(source, duration, damage, ignoreBosses)
    self.burn = { source = source, duration = duration,
        damage = damage, ignoreBosses = ignoreBosses }
end

dofile("scripts/flaming_rose.lua").Register(mod, 900)
callbacks[ModCallbacks.MC_POST_TEAR_INIT](nil, tear)
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](nil, tear)
assert(tear.flags == 0)
assert(sprite.filename == "gfx/002.005_fire tear.anm2")
assert(sprite.animation == "MoveHori")
assert(sprite.Scale.X == 0.5 and sprite.Scale.Y == 0.5)
tear.Velocity = Vector(-1, 0)
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](nil, tear)
assert(sprite.FlipX and not sprite.FlipY)
tear.Velocity = Vector(0, -1)
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](nil, tear)
assert(sprite.FlipY and not sprite.FlipX and sprite.animation == "MoveVert")

local onDamage = callbacks[ModCallbacks.MC_POST_ENTITY_TAKE_DMG]
onDamage(nil, npc, 2.5, 0, { Entity = tear }, 0, nil)
assert(#flames == 1 and flames[1].CollisionDamage == 5)
assert(flames[1].Timeout == 210 and flames[1].State == 1)
assert(npc.burn.duration == 90 and npc.burn.damage == 1)
assert(npc.burn.ignoreBosses)
local previousSpeed = flames[1].Velocity.X ^ 2 + flames[1].Velocity.Y ^ 2
callbacks[ModCallbacks.MC_POST_EFFECT_UPDATE](nil, flames[1])
local newSpeed = flames[1].Velocity.X ^ 2 + flames[1].Velocity.Y ^ 2
assert(newSpeed < previousSpeed)

onDamage(nil, npc, 1, DamageFlag.DAMAGE_POISON_BURN,
    { Entity = tear }, 0, nil)
assert(#flames == 1)

local child = {
    InitSeed = 789, CollisionDamage = 1, data = {}, flags = 0,
}
for _, method in ipairs({ "GetData", "AddTearFlags", "HasTearFlags",
    "ToTear", "ToLaser", "ToKnife", "ToBomb" }) do
    child[method] = tear[method]
end
callbacks[ModCallbacks.MC_POST_FIRE_SPLIT_TEAR](nil, child, tear)
assert(child:GetData().AscentionFlamingRoseTear)
onDamage(nil, npc, 1, 0, { Entity = child }, 0, nil)
assert(#flames == 2 and flames[2].CollisionDamage == 2)

local function weapon(kind, seed)
    local value = { InitSeed = seed, Parent = owner, data = {}, FrameCount = 0 }
    function value:GetData() return self.data end
    function value:ToPlayer() return nil end
    function value:ToFamiliar() return nil end
    function value:ToTear() return nil end
    function value:ToLaser() return kind == "laser" and self or nil end
    function value:ToKnife() return kind == "knife" and self or nil end
    function value:ToBomb() return kind == "bomb" and self or nil end
    return value
end

local laser = weapon("laser", 301)
callbacks[ModCallbacks.MC_POST_LASER_INIT](nil, laser)
onDamage(nil, npc, 3, 0, { Entity = owner }, 0, { Entity = laser })
assert(#flames == 3 and flames[3].CollisionDamage == 6)
frame = 1
onDamage(nil, npc, 3, 0, { Entity = owner }, 0, { Entity = laser })
assert(#flames == 3 and npc.burn.duration == 90)

frame = 12
local knife = weapon("knife", 302)
callbacks[ModCallbacks.MC_POST_FIRE_KNIFE](nil, knife)
onDamage(nil, npc, 4, 0, { Entity = knife }, 0, nil)
assert(#flames == 4 and flames[4].CollisionDamage == 8)

local bomb = weapon("bomb", 303)
callbacks[ModCallbacks.MC_POST_FIRE_BOMB](nil, bomb)
onDamage(nil, npc, 5, 0, { Entity = bomb }, 0, nil)
assert(#flames == 5 and flames[5].CollisionDamage == 10)

print("flaming_rose: OK")
