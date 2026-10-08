local Flight = {}

local PAUSE_TICKS = 4
local RETURN_POP_RADIUS = 24
local BRAIN_BOOST_TICKS = 8
local SHARP_TURN_DOT = 0.7
local REFLECTION_DRAG = 0.92
local REFLECTION_PULL = 0.018

local function hasTrinket(owner, trinket)
    return owner and owner:HasTrinket(trinket)
end

local function hasReflection(owner)
    return owner and owner:HasCollectible(
        CollectibleType.COLLECTIBLE_MY_REFLECTION)
end

local function nearRoomWall(tear)
    if tear.Velocity:LengthSquared() <= 0.01 then return false end
    local ahead = tear.Position + tear.Velocity:Resized(
        math.max(80, tear.Velocity:Length() * 8))
    return not Game():GetRoom():IsPositionInRoom(ahead, 12)
end

local function steerToOrigin(tear, data)
    local towardOrigin = data.origin - tear.Position
    if towardOrigin:LengthSquared() <= 0.01 then return true end
    -- My Reflection slows the outgoing tear before drawing it back; the
    -- launch point is the anchor so player movement cannot redirect it.
    local pull = towardOrigin * REFLECTION_PULL
    if pull:LengthSquared() > 3.2 ^ 2 then
        pull = pull:Resized(3.2)
    end
    local velocity = tear.Velocity * REFLECTION_DRAG + pull
    if velocity:LengthSquared() > data.returnSpeed ^ 2 then
        velocity = velocity:Resized(data.returnSpeed)
    end
    tear.Velocity = velocity
    return false
end

function Flight.Init(data, tear, owner)
    local speed = math.max(1, data.speed)
    data.origin = Vector(tear.Position.X, tear.Position.Y)
    data.lastPosition = data.origin
    data.extent = 0
    data.maxAge = math.min(240,
        math.max(90, math.ceil(data.range / speed) * 6))
    data.maxAgeRange = data.range
    if tear.Velocity:LengthSquared() > 0.01 then
        data.lastHeading = tear.Velocity:Normalized()
    end
    if hasReflection(owner) and tear.ClearTearFlags then
        tear:ClearTearFlags(TearFlags.TEAR_BOOMERANG)
    end
end

function Flight.Update(tear, data, owner)
    if data.maxAgeRange ~= data.range then
        data.maxAge = math.min(240,
            math.max(90, math.ceil(data.range / math.max(1, data.speed)) * 6))
        data.maxAgeRange = data.range
    end
    data.age = data.age + 1
    data.travel = data.travel + tear.Position:Distance(data.lastPosition)
    data.lastPosition = tear.Position
    data.extent = math.max(data.extent,
        tear.Position:Distance(data.origin))

    local reflection = hasReflection(owner)
    if data.returning then
        data.returnAge = data.returnAge + 1
        local towardOrigin = data.origin - tear.Position
        if data.returnAge >= 3
            and towardOrigin:LengthSquared() <= RETURN_POP_RADIUS ^ 2 then
            return true
        end
        if data.age >= data.maxAge then return true end
        return steerToOrigin(tear, data)
    end

    if reflection and (data.extent >= data.range * 0.5
        or nearRoomWall(tear)
        or data.age >= math.floor(data.maxAge * 0.6)) then
        data.returning = true
        data.returnAge = 0
        data.returnSpeed = math.min(data.speed,
            math.max(1, tear.Velocity:Length()))
        return steerToOrigin(tear, data)
    end

    if data.extent >= data.range or data.age >= data.maxAge then
        if data.keepMomentum or data.age >= data.maxAge then return true end
        data.pause = (data.pause or 0) + 1
        tear.Velocity = Vector.Zero
        return data.pause >= PAUSE_TICKS
    end

    local ring = hasTrinket(owner, TrinketType.TRINKET_RING_WORM)
    local brain = hasTrinket(owner, TrinketType.TRINKET_BRAIN_WORM)
    local velocity = tear.Velocity
    if ring then
        data.lastHeading = velocity:LengthSquared() > 0.01
            and velocity:Normalized() or data.lastHeading
        return false
    end

    if brain and data.lastHeading and velocity:LengthSquared() > 0.01 then
        local heading = velocity:Normalized()
        local dot = heading.X * data.lastHeading.X
            + heading.Y * data.lastHeading.Y
        if dot < SHARP_TURN_DOT then
            data.brainBoost = BRAIN_BOOST_TICKS
        end
    end

    local progress = math.min(1, data.extent / data.range)
    local speed = data.keepMomentum and data.speed
        or data.speed * (0.25 + 0.75 * (1 - progress) ^ 2)
    if brain and (data.brainBoost or 0) > 0 then
        speed = math.max(speed, data.speed * 0.9)
        data.brainBoost = data.brainBoost - 1
    end
    if velocity:LengthSquared() > 0.01 then
        if not brain and not reflection then
            velocity = velocity:Rotated(
                math.sin(data.age * 0.65 + data.driftPhase) * 3.5)
        end
        tear.Velocity = velocity:Resized(speed)
        data.lastHeading = tear.Velocity:Normalized()
    end
    return false
end

return Flight
