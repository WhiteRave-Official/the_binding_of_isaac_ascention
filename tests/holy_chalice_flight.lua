local vectorMeta = {}
vectorMeta.__index = vectorMeta
local function vector(x, y)
    return setmetatable({ X = x, Y = y }, vectorMeta)
end
vectorMeta.__add = function(a, b) return vector(a.X + b.X, a.Y + b.Y) end
vectorMeta.__sub = function(a, b) return vector(a.X - b.X, a.Y - b.Y) end
vectorMeta.__mul = function(a, n) return vector(a.X * n, a.Y * n) end
function vectorMeta:LengthSquared() return self.X ^ 2 + self.Y ^ 2 end
function vectorMeta:Distance(other)
    return (self - other):Length()
end
function vectorMeta:Length() return math.sqrt(self:LengthSquared()) end
function vectorMeta:Normalized() return self:Resized(1) end
function vectorMeta:Resized(length)
    local current = self:Length()
    return vector(self.X * length / current, self.Y * length / current)
end
function vectorMeta:Rotated(degrees)
    local angle = math.rad(degrees)
    return vector(self.X * math.cos(angle) - self.Y * math.sin(angle),
        self.X * math.sin(angle) + self.Y * math.cos(angle))
end
Vector = setmetatable({ Zero = vector(0, 0) }, {
    __call = function(_, x, y) return vector(x, y) end,
})
CollectibleType = { COLLECTIBLE_MY_REFLECTION = 5 }
TrinketType = { TRINKET_RING_WORM = 11, TRINKET_BRAIN_WORM = 144 }
TearFlags = { TEAR_BOOMERANG = 256 }
local roomRight = 500
Game = function()
    return { GetRoom = function()
        return { IsPositionInRoom = function(_, position, margin)
            return position.X <= roomRight - margin
        end }
    end }
end

local Flight = dofile("scripts/holy_chalice_flight.lua")
local owner = {
    Position = vector(0, 0), items = {}, trinkets = {},
    HasCollectible = function(self, id) return self.items[id] or false end,
    HasTrinket = function(self, id) return self.trinkets[id] or false end,
    Exists = function() return true end,
}
local function bubble(range)
    local tear = { Position = vector(0, 0), Velocity = vector(10, 0),
        TearFlags = TearFlags.TEAR_BOOMERANG,
        ClearTearFlags = function(self, flags)
            self.TearFlags = self.TearFlags & ~flags
        end,
    }
    local data = { range = range, speed = 10, driftPhase = 0,
        age = 0, travel = 0 }
    Flight.Init(data, tear, owner)
    return tear, data
end

owner.trinkets[TrinketType.TRINKET_RING_WORM] = true
local ring, ringData = bubble(120)
for step = 1, 20 do
    local angle = math.rad(step * 45)
    ring.Position = vector(50 * math.cos(angle), 50 * math.sin(angle))
    ring.Velocity = vector(-10 * math.sin(angle), 10 * math.cos(angle))
    local before = ring.Velocity
    assert(not Flight.Update(ring, ringData, owner))
    assert(ring.Velocity == before,
        "Ring Worm must retain its engine-controlled velocity")
end
assert(ringData.travel > ringData.range and ringData.extent < ringData.range,
    "circling must not consume the bubble's entire range")
ring.Position = vector(125, 0)
for step = 1, 4 do
    local popped = Flight.Update(ring, ringData, owner)
    assert(popped == (step == 4))
end
owner.trinkets[TrinketType.TRINKET_RING_WORM] = nil

owner.trinkets[TrinketType.TRINKET_BRAIN_WORM] = true
local brain, brainData = bubble(120)
brain.Position = vector(30, 0)
Flight.Update(brain, brainData, owner)
brain.Position = vector(30, 2)
brain.Velocity = vector(0, 1.5)
Flight.Update(brain, brainData, owner)
assert(brain.Velocity.Y >= 9 and math.abs(brain.Velocity.X) < 0.001,
    "Brain Worm's sharp turn must restore usable forward speed")
owner.trinkets[TrinketType.TRINKET_BRAIN_WORM] = nil

owner.items[CollectibleType.COLLECTIBLE_MY_REFLECTION] = true
local reflected, reflectedData = bubble(100)
reflected.Position = vector(50, 0)
assert(not Flight.Update(reflected, reflectedData, owner)
    and reflectedData.returning and not reflectedData.pause,
    "My Reflection must turn after half of the total tear range")
assert(reflected.TearFlags == 0 and reflected.Velocity.X > 0
    and reflected.Velocity.X < 10,
    "custom reflection must suppress native homing and first slow the tear")
assert(reflectedData.returnSpeed == 10,
    "reflection must capture the outgoing speed at the turn")
owner.Position = vector(0, 150)
local returned = false
local reversed = false
local reversalTick
for tick = 1, 70 do
    reflected.Position = reflected.Position + reflected.Velocity
    if Flight.Update(reflected, reflectedData, owner) then
        returned = true
        break
    end
    assert(reflected.Velocity:Length() <= reflectedData.returnSpeed + 0.001,
        "returning bubbles must not accelerate beyond their outgoing speed")
    if reflected.Velocity.X < 0 then
        reversed = true
        reversalTick = reversalTick or tick
    end
end
assert(returned and reversed and reversalTick >= 4
    and reflected.Position:Distance(reflectedData.origin) <= 24
    and reflected.Position:Distance(owner.Position) > 24,
    "My Reflection bubble must pop near its fixed launch point")
owner.Position = vector(0, 0)
roomRight = 130
local wallTear, wallData = bubble(300)
wallTear.Position = vector(95, 0)
assert(not Flight.Update(wallTear, wallData, owner)
    and wallData.returning and wallTear.Position.X < roomRight - 12,
    "My Reflection must turn before reaching the room wall")
for _ = 1, 12 do
    wallTear.Position = wallTear.Position + wallTear.Velocity
    assert(wallTear.Position.X < roomRight - 12,
        "the slow turn must not push a bubble into the wall")
    if Flight.Update(wallTear, wallData, owner) then break end
end
roomRight = 500
local slowTear, slowData = bubble(100)
slowTear.Position = vector(50, 0)
slowTear.Velocity = vector(4, 0)
assert(not Flight.Update(slowTear, slowData, owner)
    and slowData.returnSpeed == 4,
    "reflection must preserve an already slowed bubble's speed")
for _ = 1, 30 do
    slowTear.Position = slowTear.Position + slowTear.Velocity
    if Flight.Update(slowTear, slowData, owner) then break end
    assert(slowTear.Velocity:Length() <= 4.001,
        "the return must not restore the initial ten-unit shot speed")
end
print("holy chalice flight: OK")
