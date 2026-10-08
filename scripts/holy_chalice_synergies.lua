local Synergies = {}
local Damage = include("scripts.holy_chalice_damage")

local BRIM_BALL_KEY = "AscentionHolyChaliceBrimBall"
local RING_KEY = "AscentionHolyChaliceRing"
local BALL_DAMAGE = 0.35
local RING_DAMAGE = 0.35
local BALL_SCALE = 0.75
local EFFECT_SCALE = 0.8
local RING_RADIUS = 30
local COMBO_RING_RADIUS = 13.5
local PROJECTILE_TIMEOUT = 999999

local function childRng(seed, volley)
    local rng = RNG()
    rng:SetSeed(seed or 1, 35 + volley)
    return rng
end

local function nextChildDelay(rng, formation)
    return (formation and 14 or 7) + rng:RandomInt(formation and 9 or 10)
end

local function distanceToRoomBoundary(position, direction)
    local room = Game():GetRoom()
    local distance = 16
    while distance < 1600
        and room:IsPositionInRoom(position + direction * distance, 8) do
        distance = distance + 16
    end
    return distance
end

local function roomTravelTimeout(position, velocity)
    local speed = velocity:Length()
    if speed < 0.1 then return 60 end
    return math.ceil(distanceToRoomBoundary(position,
        velocity:Normalized()) / speed) + 12
end

local function fireBrimBall(player, position, velocity, direction, rng, micro)
    local playerData = player:GetData()
    playerData.HolyChaliceFiringCustom = true
    local ball = player:FireBrimstoneBall(position, velocity)
    playerData.HolyChaliceFiringCustom = nil
    if not ball then return end
    local multiplier = Damage.Roll(rng)
    local size = (micro and 0.25 or BALL_SCALE)
        * math.max(0.75, math.min(1.2, math.sqrt(multiplier)))
        * (0.85 + rng:RandomFloat() * 0.3)
    ball.Position = position
    ball.Velocity = velocity
    ball.SpriteScale = Vector(size, size)
    ball.SizeMulti = Vector(size, size)
    ball.CollisionDamage = player.Damage * (micro and BALL_DAMAGE * 0.5
        or BALL_DAMAGE) * multiplier
    ball.Color = player.LaserColor
    ball:GetSprite().Color = player.LaserColor
    ball.Timeout = PROJECTILE_TIMEOUT
    ball:GetData()[BRIM_BALL_KEY] = {
        owner = EntityPtr(player), direction = direction,
        multiplier = multiplier, size = size, parent = not micro,
        auraScale = micro and player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X)
            and 0.6 * (0.75 + rng:RandomFloat() * 0.5) or nil,
    }
    return ball
end

local function scaleRingChild(laser)
    local child = laser.Child
    local data = laser:GetData()[RING_KEY]
    if child and data and data.brimstone
        and child.Type == EntityType.ENTITY_LASER then
        child.Visible = false
        local childLaser = child:ToLaser()
        if data.radius and childLaser.Radius ~= data.radius then
            childLaser.Radius = data.radius
            childLaser:RecalculateSamplesNextUpdate()
        end
    end
    if child and data and data.brimstone
        and child.Type == EntityType.ENTITY_EFFECT then
        child.Visible = false
    end
    if child and child.Type == EntityType.ENTITY_EFFECT
        and (child.Variant == EffectVariant.LASER_IMPACT
            or child.Variant == EffectVariant.TECH_DOT) then
        local size = data.micro and 0.2 or EFFECT_SCALE
        child.SpriteScale = Vector(size, size)
    end
end

function Synergies.AdoptTechX(player, laser, brimstone)
    if laser:GetData()[RING_KEY] then return end
    local rng = childRng(laser.InitSeed, 0)
    local multiplier = brimstone and Damage.Roll(rng) or 1
    local sizeRoll = brimstone and (0.85 + rng:RandomFloat() * 0.3) or 1
    local radius = math.max(1, laser.Radius * 0.75
        * math.max(0.75, math.min(1.2, math.sqrt(multiplier))) * sizeRoll)
    laser.Radius = radius
    laser.CollisionDamage = laser.CollisionDamage * multiplier
    laser:GetData()[RING_KEY] = {
        stalled = 0, owner = EntityPtr(player), brimstone = brimstone,
        native = true, micro = false, radius = radius,
        nextChild = laser.FrameCount + nextChildDelay(rng, not brimstone),
        volleys = 0,
    }
    laser:RecalculateSamplesNextUpdate()
    scaleRingChild(laser)
end

local function fireRing(player, position, velocity, brimstone, rng, micro,
    parentRadius)
    local playerData = player:GetData()
    local nativeRadius = not brimstone and playerData.HolyChaliceNativeRingRadius
    local nativeScale = not brimstone and playerData.HolyChaliceNativeRingScale
    local multiplier = Damage.Roll(rng)
    local radius
    if brimstone then
        radius = (micro and 5 or COMBO_RING_RADIUS)
            * math.max(0.75, math.min(1.2, math.sqrt(multiplier)))
            * (0.85 + rng:RandomFloat() * 0.3)
    else
        radius = micro and math.max(1, (parentRadius or RING_RADIUS)
            * 0.25 * math.sqrt(multiplier)
            * (0.8 + rng:RandomFloat() * 0.4))
            or math.max(1, (nativeRadius or 40) * 0.75)
    end
    playerData.HolyChaliceFiringCustom = true
    local laser = player:FireTechXLaser(position, velocity,
        radius, player, RING_DAMAGE)
    playerData.HolyChaliceFiringCustom = nil
    if not laser then return end
    laser:SetDisableFollowParent(true)
    laser.Position = position
    laser.Velocity = velocity
    laser.CollisionDamage = player.Damage * (micro and RING_DAMAGE * 0.5
        or RING_DAMAGE) * multiplier
    laser.Radius = radius
    laser:SetTimeout(brimstone and math.min(45,
        roomTravelTimeout(position, velocity))
        or roomTravelTimeout(position, velocity))
    local scale
    if brimstone then
        scale = micro and 0.3 or 0.65
    else
        scale = micro and 1 or math.max(1, nativeScale or 1)
    end
    if not brimstone then laser:SetScale(scale) end
    if brimstone then
        laser.Color = player.LaserColor
        laser:GetSprite().Color = player.LaserColor
    end
    local trackedScale
    if not brimstone then trackedScale = scale end
    local childDelay = not micro and nextChildDelay(rng, not brimstone) or nil
    laser:GetData()[RING_KEY] = {
        stalled = 0, owner = EntityPtr(player), brimstone = brimstone,
        radius = radius, scale = trackedScale,
        micro = micro, nextChild = childDelay,
        volleys = 0,
    }
    laser:RecalculateSamplesNextUpdate()
    scaleRingChild(laser)
    return laser
end

function Synergies.Fire(player, mode, direction, itemId)
    local rng = player:GetCollectibleRNG(itemId)
    local position = player.Position + direction * 12
    local velocity = direction * ((mode == "brim_techx" and 12 or 6)
        * player.ShotSpeed)
    if mode == "brimstone" then
        return Synergies.FireBrimBall(player, position, direction, itemId)
    else
        return fireRing(player, position, velocity,
            mode == "brim_techx", rng)
    end
end

function Synergies.FireBrimBall(player, position, direction, itemId)
    local rng = player:GetCollectibleRNG(itemId)
    local ball = fireBrimBall(player, position,
        direction * (6 * player.ShotSpeed), direction, rng)
    local count = 2 + rng:RandomInt(3)
    for index = 1, count do
        local angle = (index - (count + 1) / 2) * 14
            + (rng:RandomFloat() - 0.5) * 10
        local childDirection = direction:Rotated(angle)
        local speed = (6.5 + rng:RandomFloat() * 2.5) * player.ShotSpeed
        fireBrimBall(player, position, childDirection * speed,
            childDirection, rng, true)
    end
    return ball
end

local function fireChild(player, mode, position, direction, parentRadius, rng)
    local velocity = direction * ((7 + rng:RandomFloat() * 2)
        * player.ShotSpeed)
    if mode == "brimstone" then
        return fireBrimBall(player, position, velocity,
            direction, rng, true)
    else
        return fireRing(player, position, velocity,
            mode == "brim_techx", rng, true, parentRadius)
    end
end

function Synergies.Register(mod)
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, effect)
        local data = effect:GetData()[BRIM_BALL_KEY]
        if not data then return end
        local ownerEntity = data.owner.Ref
        local player = ownerEntity and ownerEntity:ToPlayer()
        if not player or not player:Exists() then
            effect:Remove()
            return
        end
        effect.SpriteScale = Vector(data.size, data.size)
        effect.SizeMulti = Vector(data.size, data.size)
        effect.Color = player.LaserColor
        local sprite = effect:GetSprite()
        sprite.Color = player.LaserColor
        if player:HasCollectible(CollectibleType.COLLECTIBLE_HAEMOLACRIA) then
            sprite.Scale = Vector(1, 1)
        end
        if not Game():GetRoom():IsPositionInRoom(effect.Position, 8) then
            effect:Remove()
            return
        end
        if effect.Velocity:LengthSquared() < 0.25 then
            data.stalled = (data.stalled or 0) + 1
            if data.stalled >= 20 then
                effect:Remove()
                return
            end
        else
            data.stalled = 0
        end
    end, EffectVariant.BRIMSTONE_BALL)

    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, function(_, laser)
        local parent = laser.Parent
        local ballData = parent and parent:GetData()[BRIM_BALL_KEY]
        if ballData and ballData.auraScale then
            local auraData = laser:GetData()
            if not auraData.HolyChaliceBaseRadius and laser.Radius > 0 then
                auraData.HolyChaliceBaseRadius = laser.Radius
                auraData.HolyChaliceBaseScale = laser:GetScale()
            end
            local baseRadius = auraData.HolyChaliceBaseRadius
            if baseRadius then
                local radius = baseRadius * ballData.auraScale
                if laser.Radius ~= radius then
                    laser.Radius = radius
                    laser:RecalculateSamplesNextUpdate()
                end
                local scale = auraData.HolyChaliceBaseScale
                    * ballData.auraScale
                if math.abs(laser:GetScale() - scale) > 0.01 then
                    laser:SetScale(scale)
                end
            end
            return
        end
        local data = laser:GetData()[RING_KEY]
        if not data then return end
        if data.scale and math.abs(laser:GetScale() - data.scale) > 0.01 then
            laser:SetScale(data.scale)
        end
        if data.radius and laser.Radius ~= data.radius then
            laser.Radius = data.radius
            laser:RecalculateSamplesNextUpdate()
        end
        if data.brimstone and not data.native then
            local ownerEntity = data.owner.Ref
            local player = ownerEntity and ownerEntity:ToPlayer()
            if player and player:Exists() then
                laser.Color = player.LaserColor
                laser:GetSprite().Color = player.LaserColor
            end
        end
        scaleRingChild(laser)
        if not data.micro
            and laser.FrameCount >= data.nextChild then
            local ownerEntity = data.owner.Ref
            local player = ownerEntity and ownerEntity:ToPlayer()
            if player and player:Exists() then
                local rng = childRng(laser.InitSeed, data.volleys + 1)
                if data.brimstone then
                    local direction = Vector.FromAngle(rng:RandomFloat() * 360)
                    fireChild(player, "brimstone", laser.Position,
                        direction, laser.Radius, rng)
                else
                    local offset = data.volleys % 2 == 0 and 0 or 45
                    for spoke = 0, 3 do
                        fireChild(player, "techx", laser.Position,
                            Vector.FromAngle(offset + spoke * 90),
                            laser.Radius, rng)
                    end
                end
                data.nextChild = laser.FrameCount
                    + nextChildDelay(rng, not data.brimstone)
            end
            data.volleys = data.volleys + 1
        end
        if data.native then return end
        if not Game():GetRoom():IsPositionInRoom(laser.Position, 8) then
            laser:Remove()
            return
        end
        if laser.Velocity:LengthSquared() < 0.25 then
            data.stalled = (data.stalled or 0) + 1
            if data.stalled >= 20 then laser:Remove() end
        else
            data.stalled = 0
        end
    end)

    local function scaleRingEffect(_, effect)
        local source = effect.SpawnerEntity or effect.Parent
        local parent = effect.Parent
        local ballData = parent and parent:GetData()[BRIM_BALL_KEY]
            or source and source:GetData()[BRIM_BALL_KEY]
        if ballData and ballData.auraScale then
            local auraData = effect:GetData()
            auraData.HolyChaliceBaseScale =
                auraData.HolyChaliceBaseScale or effect.SpriteScale
            local base = auraData.HolyChaliceBaseScale
            effect.SpriteScale = Vector(base.X * ballData.auraScale,
                base.Y * ballData.auraScale)
            return
        end
        local laser = source and source:ToLaser()
        if laser and laser:GetData()[RING_KEY] then
            local data = laser:GetData()[RING_KEY]
            local size = data.micro and 0.2 or EFFECT_SCALE
            effect.SpriteScale = Vector(size, size)
        end
    end
    for _, variant in ipairs({ EffectVariant.LASER_IMPACT,
        EffectVariant.TECH_DOT }) do
        mod:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT,
            scaleRingEffect, variant)
        mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE,
            scaleRingEffect, variant)
    end
end

return Synergies
