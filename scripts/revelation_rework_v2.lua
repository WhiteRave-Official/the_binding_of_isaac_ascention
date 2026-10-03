local RevelationReworkV2 = {}

local REVELATION = CollectibleType.COLLECTIBLE_REVELATION
local DATA_KEY = "AscentionRevelationV2"
local CHECKED_KEY = "AscentionRevelationV2Checked"
local SPLIT_GUIDANCE_KEY = "AscentionRevelationV2SplitGuidance"
local SHOT_SPEED_PENALTY = 0.15
local FIRE_RATE_MULTIPLIER = 0.85
local REVELATION_TEAR_FLAGS = TearFlags.TEAR_PIERCING | TearFlags.TEAR_SPECTRAL

local SCATTER_TICKS = 60
local MAX_LIFETIME = 240
local SCATTER_HALF_ANGLE = 24.0
local TARGET_RETRY_INTERVAL = 6
local TARGET_RANGE_BONUS = 10.0 * 40.0
local SPLIT_GUIDANCE_CHANCE = 0.5
local DASH_ACCELERATION = 1.15
local MIN_DASH_MAX_SPEED = 22.0
local DASH_SPEED_MULTIPLIER = 2.2
local TARGET_RADIUS = 1200.0
local ARC_MIN_PROGRESS_SPEED = 0.012
local ARC_MAX_INITIAL_PROGRESS_SPEED = 0.035
local ARC_MAX_PROGRESS_SPEED = 0.075
local ARC_PROGRESS_ACCELERATION = 0.0015
local ARC_MIN_OFFSET = 24.0
local ARC_MAX_OFFSET = 110.0

local TRAIL_DAMAGE_MULTIPLIER = 0.15
local TRAIL_SAMPLE_INTERVAL = 1
local TRAIL_COLLISION_RESOLUTION = 3
local TRAIL_TIMEOUT = 15
local TRAIL_SCALE = 0.28
local TRAIL_BEAM_WIDTH = 0.28
local TRAIL_COLOR = Color(1.0, 0.95, 0.65, 0.82, 0.30, 0.24, 0.05)
local TRAIL_HIDDEN_COLOR = Color(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
local HOLY_BEAM_SOUND_VOLUME = 0.55

local SCATTER_SPIN_SPEED = 11.0
local TURN_VISUAL_SPEED = 24.0
local TEAR_FACING_OFFSET = 90.0

local PHASE_SCATTER = 1
local PHASE_DASH = 2
local sfx = SFXManager()

local GUIDED_SPLIT_TYPES = {
    [SplitTearType.QUAD] = true,
    [SplitTearType.PARASITE] = true,
    [SplitTearType.BURST] = true
}

local trailSprite = Sprite()
trailSprite:Load("gfx/007.005_lightbeam.anm2", true)
trailSprite:Play("LargeRedLaser", true)

local releasedTrails = {}

local function resolvePlayer(entity)
    local current = entity

    for _ = 1, 8 do
        if not current then
            return nil
        end

        local player = current:ToPlayer()
        if player then
            return player
        end

        local familiar = current:ToFamiliar()
        if familiar and familiar.Player then
            return familiar.Player
        end

        current = current.Parent or current.SpawnerEntity
    end

    return nil
end

local function deterministicSpread(initSeed)
    local value = ((initSeed * 1103515245 + 12345) & 0x7fffffff) % 10001
    return ((value / 10000.0) * 2.0 - 1.0) * SCATTER_HALF_ANGLE
end

local function isValidTarget(entity)
    local room = Game():GetRoom()
    return entity
        and entity:Exists()
        and not entity:IsDead()
        and entity:IsActiveEnemy(false)
        and entity:IsVulnerableEnemy()
        and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
        and room:IsPositionInRoom(entity.Position, 0.0)
end

local function findTarget(tear)
    local candidates = Isaac.FindInRadius(
        tear.Position,
        TARGET_RADIUS,
        EntityPartition.ENEMY
    )

    table.sort(candidates, function(left, right)
        local leftDistance = left.Position:DistanceSquared(tear.Position)
        local rightDistance = right.Position:DistanceSquared(tear.Position)
        if leftDistance == rightDistance then
            return left.InitSeed < right.InitSeed
        end
        return leftDistance < rightDistance
    end)

    for _, candidate in ipairs(candidates) do
        if isValidTarget(candidate) then
            return candidate
        end
    end

    return nil
end

local function hasDeferredSplitSynergy(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_HAEMOLACRIA)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_CRICKETS_BODY)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_PARASITE)
end

local function copyVector(vector)
    return Vector(vector.X, vector.Y)
end

local function approachAngle(current, target, maxStep)
    local delta = (target - current + 180.0) % 360.0 - 180.0
    return current + math.max(-maxStep, math.min(maxStep, delta))
end

local function faceVelocity(tear, maxStep)
    if tear.Velocity:LengthSquared() <= 0.001 then
        return
    end

    local sprite = tear:GetSprite()
    local targetRotation = tear.Velocity:GetAngleDegrees() + TEAR_FACING_OFFSET
    sprite.Rotation = approachAngle(sprite.Rotation, targetRotation, maxStep)
end

local function ensureTrailBeam(state)
    if not state.trailBeam then
        state.trailBeam = Beam(trailSprite, 1, false, true)
    end
    return state.trailBeam
end

local function addTrailSample(tear, state)
    state.trailSampleTicks = state.trailSampleTicks + 1
    if state.trailSampleTicks % TRAIL_SAMPLE_INTERVAL ~= 0 then
        return
    end

    local position = copyVector(tear.Position)
    local offset = copyVector(tear.PositionOffset)
    local previous = state.trailSamples[#state.trailSamples]
    if previous and previous.position:DistanceSquared(position) <= 0.25 then
        return
    end

    local beam = ensureTrailBeam(state)
    beam:Add(
        Isaac.WorldToScreen(position + offset),
        32.0,
        TRAIL_BEAM_WIDTH
    )
    table.insert(state.trailSamples, {
        position = position,
        offset = offset
    })
end

local function renderTrail(beam, samples, shrink)
    if not beam or not samples or #samples < 2 then
        return
    end

    shrink = math.max(0.0, math.min(1.0, shrink or 1.0))
    local visibleEnd = math.ceil(#samples * shrink)
    local points = beam:GetPoints()
    for index, point in ipairs(points) do
        local sample = samples[index]
        if sample then
            point:SetPosition(Isaac.WorldToScreen(
                sample.position + sample.offset
            ))
        end

        local visible = index <= visibleEnd and shrink > 0.0
        point:SetColor(visible and TRAIL_COLOR or TRAIL_HIDDEN_COLOR)
        local width = visible and TRAIL_BEAM_WIDTH * shrink or 0.0
        if visible and index <= 2 then
            width = width * math.max(0.15, (index - 1) / 1.5)
        end
        point:SetWidth(width)
    end
    beam:SetPoints(points)
    beam:Render(false)
end

local function spawnDamageSegment(owner, fromSample, toSample, damage)
    local delta = toSample.position - fromSample.position
    if delta:LengthSquared() <= 0.25 then
        return nil
    end

    local laser = Isaac.Spawn(
        EntityType.ENTITY_LASER,
        LaserVariant.LIGHT_BEAM,
        1415,
        fromSample.position,
        Vector.Zero,
        owner
    ):ToLaser()
    if not laser then
        return nil
    end

    laser:GetData().AscentionRevelationV2TrailHitbox = true
    laser.Angle = delta:GetAngleDegrees()
    laser.MaxDistance = delta:Length()
    laser.Timeout = TRAIL_TIMEOUT
    laser:SetScale(TRAIL_SCALE)
    laser.OneHit = false
    laser.CollisionDamage = damage
    laser.PositionOffset = fromSample.offset
    laser.Visible = false
    return laser
end

local function releaseTrail(state)
    if state.trailReleased then
        return
    end
    state.trailReleased = true

    local beam = state.trailBeam
    local samples = state.trailSamples
    if not beam or not samples or #samples < 2 then
        return
    end

    local owner = state.owner
    if not owner or not owner:Exists() then
        return
    end

    local damage = owner.Damage * TRAIL_DAMAGE_MULTIPLIER
    local firstLaser
    local fromIndex = 1
    local index = 1 + TRAIL_COLLISION_RESOLUTION
    while index <= #samples do
        local laser = spawnDamageSegment(
            owner,
            samples[fromIndex],
            samples[index],
            damage
        )
        firstLaser = firstLaser or laser
        fromIndex = index
        index = index + TRAIL_COLLISION_RESOLUTION
    end

    if fromIndex < #samples then
        local laser = spawnDamageSegment(
            owner,
            samples[fromIndex],
            samples[#samples],
            damage
        )
        firstLaser = firstLaser or laser
    end

    if firstLaser then
        sfx:Play(
            SoundEffect.SOUND_ANGEL_BEAM,
            HOLY_BEAM_SOUND_VOLUME,
            0,
            false,
            1.0
        )
        table.insert(releasedTrails, {
            beam = beam,
            samples = samples,
            anchor = EntityPtr(firstLaser),
            initialScale = math.max(0.001, firstLaser.SpriteScale.X),
            expiresAt = Game():GetFrameCount() + TRAIL_TIMEOUT
        })
    end

    state.trailBeam = nil
    state.trailSamples = nil
end

local function initializeTear(tear, owner, splitGuidance)
    local data = tear:GetData()
    local speed = tear.Velocity:Length()
    local direction = tear.Velocity
    if direction:LengthSquared() <= 0.001 then
        direction = owner:GetShootingInput()
    end
    if direction:LengthSquared() <= 0.001 then
        direction = Vector(1.0, 0.0)
    end

    direction = direction:Normalized()
    if not splitGuidance then
        direction = direction:Rotated(deterministicSpread(tear.InitSeed))
    end
    data[DATA_KEY] = {
        owner = owner,
        phase = PHASE_SCATTER,
        phaseTicks = splitGuidance and SCATTER_TICKS or 0,
        lifetime = 0,
        guidanceUsed = false,
        originalSpeed = math.max(1.0, speed),
        fixedHeight = tear.Height,
        targetPosition = nil,
        arcStart = nil,
        arcControlStart = nil,
        arcControlEnd = nil,
        arcEnd = nil,
        arcProgress = 0.0,
        arcProgressSpeed = 0.0,
        arcComplete = false,
        trailBeam = nil,
        trailSamples = {},
        trailSampleTicks = 0,
        trailReleased = false,
        cruiseVelocity = nil,
        baseSpriteScale = copyVector(tear.SpriteScale),
        rangeDistanceTraveled = 0.0,
        maxTravelDistance = math.max(40.0, owner.TearRange),
        lastTravelPosition = copyVector(tear.Position)
    }

    tear.TearFlags = tear.TearFlags | REVELATION_TEAR_FLAGS
    tear.Velocity = direction:Resized(math.max(1.0, speed))
    tear.FallingSpeed = 0.0
    tear.FallingAcceleration = 0.0
end

local function markTear(tear)
    local data = tear:GetData()
    if data[CHECKED_KEY] then
        return data[DATA_KEY]
    end

    local owner = resolvePlayer(tear)
    if not owner then
        if tear.FrameCount > 2 then
            data[CHECKED_KEY] = true
        end
        return nil
    end

    data[CHECKED_KEY] = true
    if not owner:HasCollectible(REVELATION) then
        return nil
    end

    local splitGuidance = data[SPLIT_GUIDANCE_KEY] == true
    if hasDeferredSplitSynergy(owner) and not splitGuidance then
        return nil
    end

    initializeTear(tear, owner, splitGuidance)
    return data[DATA_KEY]
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function deterministicUnit(initSeed, salt)
    local value = (((initSeed ~ salt) * 1103515245 + 12345) & 0x7fffffff)
        % 10001
    return value / 10000.0
end

local function cubicBezier(
    startPosition,
    controlStart,
    controlEnd,
    endPosition,
    time
)
    local inverse = 1.0 - time
    return startPosition * (inverse * inverse * inverse)
        + controlStart * (3.0 * inverse * inverse * time)
        + controlEnd * (3.0 * inverse * time * time)
        + endPosition * (time * time * time)
end

local function sampleArc(state, time)
    return cubicBezier(
        state.arcStart,
        state.arcControlStart,
        state.arcControlEnd,
        state.arcEnd,
        time
    )
end

local function configureArc(tear, state, targetPosition)
    local startPosition = copyVector(tear.Position)
    local endPosition = copyVector(targetPosition)
    local chord = endPosition - startPosition
    local distance = chord:Length()

    if distance <= 0.001 then
        chord = Vector(1.0, 0.0)
        distance = 1.0
        endPosition = startPosition + chord
    end

    local chordDirection = chord:Normalized()
    local startDirection = tear.Velocity
    if startDirection:LengthSquared() <= 0.001 then
        startDirection = chordDirection
    else
        startDirection = startDirection:Normalized()
    end

    local perpendicular = Vector(-chordDirection.Y, chordDirection.X)
    local side = deterministicUnit(tear.InitSeed, 0x45D9F3B) < 0.5
        and -1.0 or 1.0
    local initialProgressSpeed = clamp(
        state.originalSpeed / math.max(1.0, distance * 1.4),
        ARC_MIN_PROGRESS_SPEED,
        ARC_MAX_INITIAL_PROGRESS_SPEED
    )
    local tangentLength = clamp(
        state.originalSpeed / math.max(0.001, 3.0 * initialProgressSpeed),
        28.0,
        math.max(48.0, distance * 0.75)
    )
    local offset = clamp(
        distance * (0.18 + deterministicUnit(tear.InitSeed, 0x27D4EB2D) * 0.24),
        ARC_MIN_OFFSET,
        ARC_MAX_OFFSET
    )

    local controlStart = startPosition + startDirection * tangentLength
    local controlEnd = endPosition - chordDirection * math.max(24.0, distance * 0.22)
    controlEnd = controlEnd + perpendicular * (offset * side)

    state.targetPosition = endPosition
    state.arcStart = startPosition
    state.arcControlStart = controlStart
    state.arcControlEnd = controlEnd
    state.arcEnd = endPosition
    state.arcProgress = 0.0
    state.arcProgressSpeed = initialProgressSpeed
    state.arcComplete = false
end

local function updateScatter(tear, state)
    state.phaseTicks = state.phaseTicks + 1
    tear.SpriteScale = copyVector(state.baseSpriteScale)
    tear:GetSprite().Rotation = tear:GetSprite().Rotation + SCATTER_SPIN_SPEED

    if state.guidanceUsed then
        return
    end

    if state.phaseTicks < SCATTER_TICKS then
        return
    end

    if (state.phaseTicks - SCATTER_TICKS) % TARGET_RETRY_INTERVAL ~= 0 then
        return
    end

    local target = findTarget(tear)
    if not target then
        return
    end

    state.guidanceUsed = true
    state.maxTravelDistance = state.maxTravelDistance + TARGET_RANGE_BONUS
    state.cruiseVelocity = copyVector(tear.Velocity)
    configureArc(tear, state, target.Position)
    state.phase = PHASE_DASH
    state.phaseTicks = 0
    addTrailSample(tear, state)
end

local function updateDash(tear, state)
    if not state.arcComplete then
        state.arcProgressSpeed = math.min(
            ARC_MAX_PROGRESS_SPEED,
            state.arcProgressSpeed + ARC_PROGRESS_ACCELERATION
        )
        state.arcProgress = math.min(
            1.0,
            state.arcProgress + state.arcProgressSpeed
        )
        local nextPosition = sampleArc(state, state.arcProgress)
        local movement = nextPosition - tear.Position
        if movement:LengthSquared() > 0.001 then
            tear.Velocity = movement
        end

        if state.arcProgress >= 1.0 then
            state.arcComplete = true
            local tangent = state.arcEnd - state.arcControlEnd
            if tangent:LengthSquared() > 0.001 then
                local maxSpeed = math.max(
                    MIN_DASH_MAX_SPEED,
                    state.originalSpeed * DASH_SPEED_MULTIPLIER
                )
                local exitSpeed = math.min(maxSpeed, math.max(
                    tear.Velocity:Length(),
                    state.originalSpeed
                ))
                tear.Velocity = tangent:Resized(exitSpeed)
            end
        end
    else
        local direction = tear.Velocity
        if direction:LengthSquared() <= 0.001 then
            direction = state.arcEnd - state.arcControlEnd
        end
        local maxSpeed = math.max(
            MIN_DASH_MAX_SPEED,
            state.originalSpeed * DASH_SPEED_MULTIPLIER
        )
        local speed = math.min(maxSpeed, direction:Length() + DASH_ACCELERATION)
        tear.Velocity = direction:Resized(speed)
    end

    tear.SpriteScale = copyVector(state.baseSpriteScale)
    faceVelocity(tear, TURN_VISUAL_SPEED)
    addTrailSample(tear, state)
end

local function updateTear(_, tear)
    local state = markTear(tear)
    if not state then
        return
    end

    state.lifetime = state.lifetime + 1
    if state.lifetime >= MAX_LIFETIME then
        tear:Remove()
        return
    end

    local currentPosition = copyVector(tear.Position)
    local rangeIsActive = state.phase ~= PHASE_SCATTER
        or state.phaseTicks >= SCATTER_TICKS
    if rangeIsActive then
        state.rangeDistanceTraveled = state.rangeDistanceTraveled
            + currentPosition:Distance(state.lastTravelPosition)
    end
    state.lastTravelPosition = currentPosition
    if state.rangeDistanceTraveled >= state.maxTravelDistance then
        tear:Remove()
        return
    end

    tear.TearFlags = tear.TearFlags | REVELATION_TEAR_FLAGS
    tear.FallingSpeed = 0.0
    tear.FallingAcceleration = 0.0
    tear.Height = state.fixedHeight

    if state.phase == PHASE_SCATTER then
        updateScatter(tear, state)
    else
        updateDash(tear, state)
    end
end

local function onPlayerUpdate(_, player)
    if player:HasCollectible(REVELATION) and player:GetRevelationCharge() ~= 0 then
        player:SetRevelationCharge(0)
    end
end

local function evaluateCache(_, player, cacheFlag)
    if not player:HasCollectible(REVELATION) then
        return
    end

    if cacheFlag == CacheFlag.CACHE_FIREDELAY then
        player.MaxFireDelay = (player.MaxFireDelay + 1.0)
            / FIRE_RATE_MULTIPLIER - 1.0
    elseif cacheFlag == CacheFlag.CACHE_SHOTSPEED then
        player.ShotSpeed = player.ShotSpeed - SHOT_SPEED_PENALTY
    elseif cacheFlag == CacheFlag.CACHE_TEARFLAG then
        player.TearFlags = player.TearFlags | REVELATION_TEAR_FLAGS
    end
end

local function onFireTear(_, tear)
    markTear(tear)
end

local function onFireSplitTear(_, tear, sourceEntity, splitType)
    if not GUIDED_SPLIT_TYPES[splitType] then
        return
    end

    if deterministicUnit(tear.InitSeed, 0x6E624EB7) >= SPLIT_GUIDANCE_CHANCE then
        return
    end

    local owner = resolvePlayer(sourceEntity) or resolvePlayer(tear)
    if not owner or not owner:HasCollectible(REVELATION) then
        return
    end

    local data = tear:GetData()
    data[SPLIT_GUIDANCE_KEY] = true
    data[CHECKED_KEY] = true
    if not data[DATA_KEY] then
        initializeTear(tear, owner, true)
    end
end

local function onEntityRemove(_, entity)
    local tear = entity:ToTear()
    if not tear then
        return
    end

    local state = tear:GetData()[DATA_KEY]
    if state then
        releaseTrail(state)
    end
end

local function onTearRender(_, tear)
    local state = tear:GetData()[DATA_KEY]
    if state and state.trailBeam and state.trailSamples then
        renderTrail(state.trailBeam, state.trailSamples, 1.0)
    end
end

local function onRender()
    for index = #releasedTrails, 1, -1 do
        local released = releasedTrails[index]
        local anchor = released.anchor and released.anchor.Ref
        if anchor and anchor:Exists() then
            local anchorLaser = anchor:ToLaser()
            local spriteShrink = math.max(
                0.0,
                math.min(
                    1.0,
                    anchorLaser
                        and anchorLaser.SpriteScale.X / released.initialScale
                        or 1.0
                )
            )
            local timeoutShrink = math.max(
                0.0,
                math.min(
                    1.0,
                    (released.expiresAt - Game():GetFrameCount())
                        / TRAIL_TIMEOUT
                )
            )
            renderTrail(
                released.beam,
                released.samples,
                math.min(spriteShrink, timeoutShrink)
            )
        else
            table.remove(releasedTrails, index)
        end
    end
end

local function onNewRoom()
    releasedTrails = {}
end

function RevelationReworkV2.Register(mod)
    mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, evaluateCache)
    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, onPlayerUpdate)
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, onFireTear)
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_SPLIT_TEAR, onFireSplitTear)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, updateTear)
    mod:AddCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, onEntityRemove)
    mod:AddCallback(ModCallbacks.MC_PRE_TEAR_RENDER, onTearRender)
    mod:AddCallback(ModCallbacks.MC_POST_RENDER, onRender)
    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, onNewRoom)
end

return RevelationReworkV2
