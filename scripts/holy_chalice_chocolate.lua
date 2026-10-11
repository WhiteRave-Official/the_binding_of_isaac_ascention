local Chocolate = {}

local TRAIL_INTERVAL = 5
local MAX_TRAIL_BUBBLES = 10
local MAX_VOLLEY_TRAILS = 24
local TRAIL_DAMAGE = 0.28

function Chocolate.CanLeaveTrail(damage, ownerDamage, sourceDamageFactor)
    return damage >= ownerDamage * sourceDamageFactor
end

function Chocolate.BeginShot(holder, tear, owner, frame, nativeDamageMultiplier)
    local tearData = tear:GetData()
    if tearData.HolyChaliceChocolateProcessed then return nil end
    tearData.HolyChaliceChocolateProcessed = true

    local holderData = holder:GetData()
    if holderData.HolyChaliceChocolateVolleyFrame ~= frame then
        holderData.HolyChaliceChocolateVolleyFrame = frame
        holderData.HolyChaliceChocolateVolley = { trails = 0 }
    end
    return math.max(0.1, tear.CollisionDamage
        / math.max(0.1, owner.Damage * nativeDamageMultiplier)),
        holderData.HolyChaliceChocolateVolley
end

function Chocolate.SpawnTrail(tear, data, owner, itemId, bubbleKey, fireBubble)
    if not data.chocolateTrailEligible or data.age == 0
        or data.age % TRAIL_INTERVAL ~= 0
        or (data.chocolateTrailCount or 0) >= MAX_TRAIL_BUBBLES
        or (data.chocolateVolley
            and data.chocolateVolley.trails >= MAX_VOLLEY_TRAILS)
        or tear.Velocity:LengthSquared() <= 0.01 then return end

    local rng = owner:GetCollectibleRNG(itemId)
    local direction = tear.Velocity:Normalized()
    local position = tear.Position - direction * 12
    local velocity = direction:Rotated((rng:RandomFloat() - 0.5) * 50)
        * ((2.5 + rng:RandomFloat() * 1.5) * owner.ShotSpeed)
    local damageFactor = TRAIL_DAMAGE * data.chocolateChargeFactor
        * data.chocolateSourceDamageFactor
    local bubble = fireBubble(owner, itemId, position, velocity,
        0.36 + rng:RandomFloat() * 0.16, damageFactor, 0, nil,
        false, owner.Damage)
    if not bubble then return end
    data.chocolateTrailCount = (data.chocolateTrailCount or 0) + 1
    if data.chocolateVolley then
        data.chocolateVolley.trails = data.chocolateVolley.trails + 1
    end
    local bubbleData = bubble:GetData()[bubbleKey]
    bubbleData.damageFactor = damageFactor
    bubbleData.range = math.min(bubbleData.range, 90)
end

return Chocolate
