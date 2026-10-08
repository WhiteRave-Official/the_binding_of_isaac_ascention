local vectorMeta = {}
local function vector(x, y)
    return setmetatable({ x = x, y = y, X = x, Y = y, Rotated = function(_, degrees)
        local angle = math.rad(degrees)
        return vector(x * math.cos(angle) - y * math.sin(angle),
            x * math.sin(angle) + y * math.cos(angle))
    end, GetAngleDegrees = function() return math.deg(math.atan(y, x)) end,
        LengthSquared = function() return x * x + y * y end,
        Length = function() return math.sqrt(x * x + y * y) end,
        Normalized = function()
            local length = math.sqrt(x * x + y * y)
            return vector(x / length, y / length)
        end }, vectorMeta)
end
vectorMeta.__add = function(a, b) return vector(a.x + b.x, a.y + b.y) end
vectorMeta.__mul = function(a, b) return vector(a.x * b, a.y * b) end
Vector = setmetatable({ Zero = vector(0, 0), FromAngle = function(degrees)
    return vector(math.cos(math.rad(degrees)), math.sin(math.rad(degrees)))
end }, { __call = function(_, x, y) return vector(x, y) end })
EntityPtr = function(entity)
    return { Ref = entity }
end
EntityType = { ENTITY_EFFECT = 1000, ENTITY_LASER = 7 }
CollectibleType = { COLLECTIBLE_INNER_EYE = 3,
    COLLECTIBLE_MUTANT_SPIDER = 4, COLLECTIBLE_20_20 = 5,
    COLLECTIBLE_THE_WIZ = 6, COLLECTIBLE_HAEMOLACRIA = 7,
    COLLECTIBLE_TECH_X = 8 }
EffectVariant = {
    BRIMSTONE_BALL = 113, TEAR_POOF_A = 15,
    LASER_IMPACT = 16, TECH_DOT = 17, BRIMSTONE_SWIRL = 18,
}
LaserVariant = { THICK_RED = 1 }
ModCallbacks = {
    MC_POST_EFFECT_UPDATE = 1,
    MC_POST_LASER_UPDATE = 2,
    MC_POST_EFFECT_INIT = 3,
}
Color = function(r, g, b, a) return { r, g, b, a } end
local room = { IsPositionInRoom = function(_, pos)
    return pos.x >= -400 and pos.x <= 400
        and pos.y >= -400 and pos.y <= 400
end }
Game = function() return { GetRoom = function() return room end,
    GetFrameCount = function() return 12 end } end

local balls, rings, beams, poofs = {}, {}, {}, {}
local ringLogs = {}
local function laser()
    return {
        FrameCount = 0,
        CollisionDamage = 12,
        ToLaser = function(self) return self end,
        SetDisableFollowParent = function() end,
        SetTimeout = function(self, value) self.timeout = value end,
        GetScale = function(self) return self.scale or 1 end,
        SetScale = function(self, value) self.scale = value end,
        RecalculateSamplesNextUpdate = function(self)
            self.recalculations = (self.recalculations or 0) + 1
        end,
        GetData = function(self) self.data = self.data or {}; return self.data end,
        GetSprite = function(self)
            self.sprite = self.sprite or { Scale = vector(1, 1) }
            return self.sprite
        end,
        Remove = function(self) self.removed = true end,
        Exists = function(self) return not self.removed end,
    }
end
EntityLaser = { ShootAngle = function(_, position, angle)
    local beam = laser()
    beam.Position = position
    beam.angle = angle
    beams[#beams + 1] = beam
    return beam
end }
Isaac = { DebugString = function(message)
    ringLogs[#ringLogs + 1] = message
end, FindByType = function() return {} end,
    Spawn = function(_, _, _, position)
    local poof = { Position = position }
    poofs[#poofs + 1] = poof
    return poof
end }

local player = {
    Damage = 12, ShotSpeed = 1, TearRange = 200, Position = vector(0, 0),
    items = {},
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end,
    ToPlayer = function(self) return self end,
    HasCollectible = function(self, id) return self.items[id] or false end,
    GetCollectibleNum = function(self, id) return self.items[id] or 0 end,
    LaserColor = { name = "player laser palette" },
    Exists = function() return true end,
    GetCollectibleRNG = function()
        return {
            RandomInt = function() return 0 end,
            RandomFloat = function() return rngValue or 0.5 end,
        }
    end,
    FireBrimstoneBall = function(_, position, velocity)
        local ball = {
            Position = position, Velocity = velocity, FrameCount = 0,
            GetData = function(self) self.data = self.data or {}; return self.data end,
            GetSprite = function(self)
                self.sprite = self.sprite or {}
                return self.sprite
            end,
            Remove = function(self) self.removed = true end,
            Exists = function(self) return not self.removed end,
        }
        balls[#balls + 1] = ball
        return ball
    end,
    FireTechXLaser = function(_, position, velocity, radius)
        local ring = laser()
        ring.Child = { Type = EntityType.ENTITY_EFFECT,
            Variant = EffectVariant.LASER_IMPACT,
            SpriteScale = vector(1, 1) }
        ring.Position = position
        ring.Velocity = velocity
        ring.radius = radius
        rings[#rings + 1] = ring
        return ring
    end,
}

local callbacks = {}
local mod = { AddCallback = function(_, id, fn, variant)
    callbacks[id .. ":" .. tostring(variant or 0)] = fn
end }
include = function(path)
    return dofile(path:gsub("%.", "/") .. ".lua")
end
RNG = function()
    return { SetSeed = function() end,
        RandomInt = function() return 0 end,
        RandomFloat = function() return rngValue or 0.5 end }
end
local synergies = dofile("scripts/holy_chalice_synergies.lua")
synergies.Register(mod)
synergies.Fire(player, "brimstone", vector(1, 0), 9)
assert(#balls == 3 and #rings == 0,
    "charge releases one large and two to four small balls")
assert(balls[1].SpriteScale.x > 0.7)
assert(balls[1]:GetData().AscentionHolyChaliceBrimBall.parent)
balls[1].FrameCount = 12
balls[1].InitSeed = 123
callbacks["1:113"](mod, balls[1])
assert(#balls == 3, "Brimstone's mini balls belong to the initial volley")
assert(balls[2].SpriteScale.x < balls[1].SpriteScale.x)
assert(not balls[2]:GetData().AscentionHolyChaliceBrimBall.parent)
assert(balls[2].Velocity:Length() > 0,
    "Brimstone ball velocity must be applied to the spawned effect")
assert(#beams == 0, "old forward beam must be gone")
player.items[CollectibleType.COLLECTIBLE_HAEMOLACRIA] = true
balls[1]:GetSprite().Scale = vector(999, 999)
balls[1].FrameCount = 0
callbacks["1:113"](mod, balls[1])
assert(balls[1]:GetSprite().Scale.x == 1,
    "Haemolacria must not stretch the Brimstone ball across the room")
player.items[CollectibleType.COLLECTIBLE_HAEMOLACRIA] = nil

synergies.Fire(player, "techx", vector(1, 0), 9)
assert(#rings == 1 and rings[1].radius == 30)
assert(rings[1].scale == 1)
player:GetData().HolyChaliceNativeRingRadius = 52
player:GetData().HolyChaliceNativeRingScale = 1.25
synergies.Fire(player, "techx", vector(1, 0), 9)
assert(rings[2].radius == 39,
    "full-size ring must be 25% smaller than the native Tech X radius")
assert(rings[2].scale == 1.25,
    "full-size ring must inherit the native Tech X scale")
rings[2].scale = 0.2
callbacks["2:0"](mod, rings[2])
assert(rings[2].scale == 1.25,
    "engine updates must not shrink the large Tech X ring")
rings[2].removed = true
rings[1].FrameCount = 18
rings[1].InitSeed = 456
callbacks["2:0"](mod, rings[1])
assert(#rings == 6, "Tech X must emit four mini rings in a plus")
for spoke = 0, 3 do
    local expected = Vector.FromAngle(spoke * 90)
    local velocity = rings[spoke + 3].Velocity:Normalized()
    assert(math.abs(velocity.X - expected.X) < 0.001
        and math.abs(velocity.Y - expected.Y) < 0.001,
        "first Tech X volley must form a plus")
end
assert(math.abs(rings[3].radius - 7.5 * math.sqrt(0.9)) < 0.001)
assert(rings[3].scale == 1)
rings[1].FrameCount = 40
callbacks["2:0"](mod, rings[1])
assert(#rings == 10, "second Tech X volley must have four rings")
for spoke = 0, 3 do
    local expected = Vector.FromAngle(45 + spoke * 90)
    local velocity = rings[spoke + 7].Velocity:Normalized()
    assert(math.abs(velocity.X - expected.X) < 0.001
        and math.abs(velocity.Y - expected.Y) < 0.001,
        "second Tech X volley must form a diagonal cross")
end

synergies.Fire(player, "brim_techx", vector(1, 0), 9)
local comboRing = rings[#rings]
assert(#rings == 11 and comboRing:GetData().AscentionHolyChaliceRing.brimstone)
local comboRadius = 13.5 * math.sqrt(0.9)
assert(math.abs(comboRing.radius - comboRadius) < 0.001
    and comboRing.scale == nil,
    "Brimstone + Tech X must keep native ring scaling")
assert(comboRing.timeout <= 45,
    "combo ring must not grow for the full room-travel timeout")
local comboChild = laser()
comboChild.Type = EntityType.ENTITY_LASER
comboChild.Visible = true
comboChild.Radius = 999
comboRing.Child = comboChild
comboRing.Radius = 999
callbacks["2:0"](mod, comboRing)
assert(math.abs(comboRing.Radius - comboRadius) < 0.001
    and not comboChild.Visible
    and math.abs(comboChild.Radius - comboRadius) < 0.001,
    "combo must hide the flashing secondary layer while clamping geometry")
assert(comboRing.scale == nil,
    "combo update must not force SetScale on the native Brimstone ring")
local nativeRings = { laser(), laser(), laser() }
for _, ring in ipairs(nativeRings) do
    ring.Radius = 37
    ring.Velocity = vector(8, 0)
    synergies.AdoptTechX(player, ring, false)
    assert(ring.Radius == 27.75 and ring.scale == nil,
        "adoption must reduce each native multishot ring by 25%")
    assert(ring:GetData().AscentionHolyChaliceRing,
        "native multishot ring must gain Chalice's secondary attacks")
end
local nativeCombo = laser()
nativeCombo.Radius = 18
nativeCombo.Velocity = vector(12, 0)
nativeCombo.Position = vector(0, 0)
nativeCombo.InitSeed = 654
nativeCombo.FrameCount = 0
nativeCombo.Child = { Type = EntityType.ENTITY_EFFECT,
    Variant = EffectVariant.LASER_IMPACT, Visible = true }
synergies.AdoptTechX(player, nativeCombo, true)
assert(not nativeCombo.Child.Visible and nativeCombo.scale == nil
    and math.abs(nativeCombo.Radius - comboRadius) < 0.001
    and math.abs(nativeCombo.CollisionDamage - 10.8) < 0.001,
    "native Brimstone + Tech X ring must receive Chalice damage and size rolls")
local rolledCombos = {}
for _, roll in ipairs({ 0.1, 0.9 }) do
    rngValue = roll
    local ring = laser()
    ring.Radius = 18
    ring.Velocity = vector(12, 0)
    ring.Position = vector(0, 0)
    synergies.AdoptTechX(player, ring, true)
    rolledCombos[#rolledCombos + 1] = ring
end
rngValue = nil
assert(rolledCombos[1].Radius < rolledCombos[2].Radius
    and rolledCombos[1].CollisionDamage
        < rolledCombos[2].CollisionDamage,
    "combo's native ring must vary both damage and size")
local ballsBeforeCombo = #balls
local ringsBeforeCombo = #rings
player.items[CollectibleType.COLLECTIBLE_TECH_X] = true
nativeCombo.FrameCount = 12
callbacks["2:0"](mod, nativeCombo)
assert(#balls == ballsBeforeCombo + 1 and #rings == ringsBeforeCombo,
    "native combo ring must fire a mini ball, not a replacement ring")
assert(#balls == ballsBeforeCombo + 1,
    "native combo ring adds exactly one mini ball")
local auraBall = balls[#balls]
local auraScale = auraBall:GetData().AscentionHolyChaliceBrimBall.auraScale
assert(math.abs(auraScale - 0.6) < 0.001,
    "combo mini-ball aura must be 40% smaller at the midpoint roll")
local auraChild = laser()
auraChild.Type = EntityType.ENTITY_LASER
auraChild.Radius = 20
auraChild.Parent = auraBall
callbacks["2:0"](mod, auraChild)
assert(math.abs(auraChild.Radius - 12) < 0.001,
    "aura laser radius must follow the mini-ball aura scale")
assert(math.abs(auraChild.scale - 0.6) < 0.001,
    "aura laser width must follow the mini-ball aura scale")
callbacks["2:0"](mod, auraChild)
assert(math.abs(auraChild.Radius - 12) < 0.001,
    "aura radius must not shrink again on later updates")
local auraEffect = {
    Parent = auraBall, SpriteScale = vector(1, 1),
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end,
}
callbacks["1:17"](mod, auraEffect)
assert(math.abs(auraEffect.SpriteScale.X - 0.6) < 0.001,
    "detached Tech X aura effects must also be reduced")

rngValue = 0
nativeCombo.FrameCount = 30
callbacks["2:0"](mod, nativeCombo)
local lowAura = balls[#balls]:GetData().AscentionHolyChaliceBrimBall.auraScale
rngValue = 1
nativeCombo.FrameCount = 50
callbacks["2:0"](mod, nativeCombo)
local highAura = balls[#balls]:GetData().AscentionHolyChaliceBrimBall.auraScale
rngValue = nil
assert(lowAura < highAura, "combo mini-ball aura size must vary with RNG")

player.ShotSpeed = 2
nativeCombo.FrameCount = 70
callbacks["2:0"](mod, nativeCombo)
assert(balls[#balls].Velocity:Length() >= 14
    and balls[#balls].Velocity:Length() <= 18,
    "combo's bonus ball speed must follow the player's shot speed")
local techChildParent = rings[1]
for tick = 40, 140 do
    techChildParent.FrameCount = tick
    callbacks["2:0"](mod, techChildParent)
end
assert(techChildParent:GetData().AscentionHolyChaliceRing.volleys > 4,
    "Tech X must keep releasing mini rings while the parent is alive")
assert(rings[#rings].Velocity:Length() >= 14
    and rings[#rings].Velocity:Length() <= 18,
    "Tech X bonus ring speed must follow the player's shot speed")
player.ShotSpeed = 1

for _ = 1, 30 do synergies.Fire(player, "brimstone", vector(1, 0), 9) end
local live = 0
for _, ball in ipairs(balls) do
    if ball:Exists() then live = live + 1 end
end
for _, ring in ipairs(rings) do
    if ring:Exists() then live = live + 1 end
end
assert(live > 24,
    "Tech X and Brimstone projectiles must not be capped by Chalice")
rngValue = 0
local variationParent = synergies.Fire(player, "techx", vector(1, 0), 9)
variationParent.FrameCount = 18
callbacks["2:0"](mod, variationParent)
local smallRing = rings[#rings]
rngValue = 1
variationParent.FrameCount = 40
callbacks["2:0"](mod, variationParent)
local largeRing = rings[#rings]
assert(smallRing.radius < largeRing.radius
    and smallRing.CollisionDamage < largeRing.CollisionDamage,
    "mini Tech X rings must vary in size and damage")
rngValue = 0
local lowBallStart = #balls
synergies.Fire(player, "brimstone", vector(1, 0), 9)
local lowBall = balls[lowBallStart + 1]
rngValue = 1
local highBallStart = #balls
synergies.Fire(player, "brimstone", vector(1, 0), 9)
local highBall = balls[highBallStart + 1]
assert(lowBall.SpriteScale.x < highBall.SpriteScale.x
    and lowBall.CollisionDamage < highBall.CollisionDamage,
    "large Brimstone balls must vary in size and damage")
print("holy chalice synergies: OK")
