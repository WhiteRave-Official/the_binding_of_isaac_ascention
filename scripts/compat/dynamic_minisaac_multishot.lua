local Multishot = {}

local MAX_FORMATION_SHOTS = 16
local FORMATION_POSITION_SCALE = 4.0
local MONSTRO_EXTRA_PELLETS_PER_LANE = 2.4
local OWNER_KEY = "AscentionDynamicMinisaacOwner"
local EXPANDED_KEY = "AscentionDynamicMinisaacMultishotExpanded"
local CLONE_KEY = "AscentionDynamicMinisaacMultishotClone"
local KNIFE_INDEX_KEY = "AscentionDynamicMinisaacKnifeIndex"
local KNIFE_ANGLE_KEY = "AscentionDynamicMinisaacKnifeAngleOffset"
local EXTRA_KNIFE_KEY = "AscentionDynamicMinisaacExtraKnife"
local KNIFE_VOLLEY_KEY = "AscentionDynamicMinisaacKnifeVolleyActive"
local TEAR_SCALE_SOURCE_KEY = "AscentionDynamicMinisaacScaleSource"
local TEAR_SCALE_SYNC_KEY = "AscentionDynamicMinisaacScaleSyncTicks"
local BURST_MEMBER_KEY = "AscentionDynamicMinisaacBurstMember"
local LASER_SCALE_KEY = "AscentionDynamicMinisaacLaserScaled"
local ATTACK_FRAME_KEY = "AscentionDynamicMinisaacAttackFrame"
local SPIRIT_SPIN_KEY = "AscentionDynamicMinisaacSpiritSpin"
local SPIRIT_PROCESSED_KEY = "AscentionDynamicMinisaacSpiritProcessed"

local spawningClone = false

local RECURSIVE_SPLIT_FLAGS = TearFlags.TEAR_SPLIT
    | TearFlags.TEAR_QUADSPLIT
    | TearFlags.TEAR_BONE
    | TearFlags.TEAR_BURSTSPLIT
    | TearFlags.TEAR_ABSORB
    | TearFlags.TEAR_LASERSHOT
    | TearFlags.TEAR_SPORE

local BRIMSTONE_VARIANTS = {
    [LaserVariant.THICK_RED] = true,
    [LaserVariant.SHOOP] = true,
    [LaserVariant.BRIM_TECH] = true,
    [LaserVariant.THICKER_RED] = true,
    [LaserVariant.THICKER_BRIM_TECH] = true,
    [LaserVariant.GIANT_BRIM_TECH] = true,
}

local function asMiniIsaac(entity)
    if entity
        and entity:Exists()
        and entity.Type == EntityType.ENTITY_FAMILIAR
        and entity.Variant == FamiliarVariant.MINISAAC
    then
        return entity:ToFamiliar()
    end
end

local function sameEntity(first, second)
    return first and second and GetPtrHash(first) == GetPtrHash(second)
end

local function resolveOwner(entity)
    local stored = entity:GetData()[OWNER_KEY]
    if stored and stored:Exists() then
        return asMiniIsaac(stored)
    end

    local direct = asMiniIsaac(entity.Parent)
        or asMiniIsaac(entity.SpawnerEntity)
    if direct then return direct end

    local parent = entity.Parent
    local parentOwner = parent and parent:GetData()[OWNER_KEY]
    if parentOwner and parentOwner:Exists() then
        entity:GetData()[OWNER_KEY] = parentOwner
        return asMiniIsaac(parentOwner)
    end

    -- Dynamic Minisaacs creates some special attacks with the player as owner.
    -- Only claim outputs created during an actual Mini Isaac attack frame.
    local spawner = entity.SpawnerEntity
    local sourcePlayer = spawner and spawner:ToPlayer()
    if not sourcePlayer or entity.FrameCount > 2 then return nil end

    local frame = Game():GetFrameCount()
    local nearest
    local nearestDistance = math.huge
    for _, candidateEntity in ipairs(Isaac.FindInRadius(
        entity.Position,
        32,
        EntityPartition.FAMILIAR
    )) do
        local candidate = asMiniIsaac(candidateEntity)
        local attackFrame = candidate
            and candidate:GetData()[ATTACK_FRAME_KEY]
        if candidate
            and sameEntity(candidate.Player, sourcePlayer)
            and attackFrame
            and frame - attackFrame >= 0
            and frame - attackFrame <= 2
        then
            local distance = candidate.Position:DistanceSquared(entity.Position)
            if distance < nearestDistance then
                nearest = candidate
                nearestDistance = distance
            end
        end
    end

    if nearest then
        entity:GetData()[OWNER_KEY] = nearest
    end
    return nearest
end

local function storeOwner(entity, familiar)
    entity:GetData()[OWNER_KEY] = familiar
end

local function directionForFamiliar(familiar)
    if familiar.ShootDirection == Direction.LEFT then
        return Vector(-1, 0)
    elseif familiar.ShootDirection == Direction.RIGHT then
        return Vector(1, 0)
    elseif familiar.ShootDirection == Direction.UP then
        return Vector(0, -1)
    elseif familiar.ShootDirection == Direction.DOWN then
        return Vector(0, 1)
    end
    return Vector(0, 1)
end

local function hasSpecialWeapon(player)
    return player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE)
        or player:HasWeaponType(WeaponType.WEAPON_LASER)
        or player:HasWeaponType(WeaponType.WEAPON_TECH_X)
        or player:HasWeaponType(WeaponType.WEAPON_KNIFE)
        or player:HasWeaponType(WeaponType.WEAPON_MONSTROS_LUNGS)
        or player:HasWeaponType(WeaponType.WEAPON_SPIRIT_SWORD)
        or player:HasWeaponType(WeaponType.WEAPON_BOMBS)
        or player:HasWeaponType(WeaponType.WEAPON_FETUS)
        or player:HasWeaponType(WeaponType.WEAPON_ROCKETS)
end

local function weaponTypeFor(entity, player)
    if entity.Type == EntityType.ENTITY_BOMB then
        return WeaponType.WEAPON_BOMBS
    elseif entity.Type == EntityType.ENTITY_KNIFE then
        -- Spirit Sword reports zero native spread. Knife params preserve the
        -- same multishot count while providing the expected fan formation.
        return WeaponType.WEAPON_KNIFE
    elseif entity.Type == EntityType.ENTITY_LASER then
        local laser = entity:ToLaser()
        if laser:IsCircleLaser() then
            return WeaponType.WEAPON_TECH_X
        elseif BRIMSTONE_VARIANTS[laser.Variant] then
            return WeaponType.WEAPON_BRIMSTONE
        end
        return WeaponType.WEAPON_LASER
    elseif entity.Type == EntityType.ENTITY_TEAR then
        local tear = entity:ToTear()
        if tear:HasTearFlags(TearFlags.TEAR_FETUS) then
            return WeaponType.WEAPON_FETUS
        elseif player:HasWeaponType(WeaponType.WEAPON_MONSTROS_LUNGS) then
            -- Monstro's Lung params intentionally expose no spread angle.
            -- Each pellet still needs the regular tear multishot fan.
            return WeaponType.WEAPON_TEARS
        end
        return WeaponType.WEAPON_TEARS
    end
    return WeaponType.WEAPON_TEARS
end

local function entityDirection(entity, familiar)
    if entity.Type == EntityType.ENTITY_LASER then
        local laser = entity:ToLaser()
        if laser:IsCircleLaser() and laser.Velocity:LengthSquared() > 0 then
            return laser.Velocity:Normalized(), laser.Velocity:Length()
        end
        return Vector.FromAngle(laser.AngleDegrees), 1
    elseif entity.Type == EntityType.ENTITY_KNIFE then
        return Vector.FromAngle(entity:ToKnife().Rotation), 1
    elseif entity.Velocity:LengthSquared() > 0 then
        return entity.Velocity:Normalized(), entity.Velocity:Length()
    end
    return directionForFamiliar(familiar), 10
end

local function multishotScore(params)
    local score = math.max(1, params:GetNumTears())
        + math.max(0, params:GetNumEyesActive() - 1)
        + math.max(0, params:GetNumRandomDirTears())
    if params:IsShootingBackwards() then score = score + 1 end
    if params:IsShootingSideways() then score = score + 2 end
    return score
end

local function resolveMultishotParams(player, weaponType)
    local weaponParams = player:GetMultiShotParams(weaponType)
    if weaponType == WeaponType.WEAPON_TEARS then
        return weaponParams, weaponType
    end

    -- Several special weapon types report a single native shot even when the
    -- player's tear formation contains 20/20, Inner Eye, Mutant Spider, etc.
    -- Use the regular tear formation when it carries more multishot data.
    local tearParams = player:GetMultiShotParams(WeaponType.WEAPON_TEARS)
    if multishotScore(tearParams) > multishotScore(weaponParams) then
        return tearParams, WeaponType.WEAPON_TEARS
    end
    return weaponParams, weaponType
end

local function buildFormation(player, familiar, weaponType, direction, speed, params)
    params = params or player:GetMultiShotParams(weaponType)
    local count = math.max(1, math.min(MAX_FORMATION_SHOTS, params:GetNumTears()))
    local formation = {}

    for index = 0, count - 1 do
        local posVel = player:GetMultiShotPositionVelocity(
            index,
            weaponType,
            direction,
            speed,
            params
        )
        table.insert(formation, {
            position = posVel.Position * FORMATION_POSITION_SCALE,
            velocity = posVel.Velocity,
        })
    end

    if params:IsShootingBackwards() then
        table.insert(formation, {
            position = Vector.Zero,
            velocity = direction:Rotated(180):Resized(speed),
        })
    end
    if params:IsShootingSideways() then
        table.insert(formation, {
            position = Vector.Zero,
            velocity = direction:Rotated(90):Resized(speed),
        })
        table.insert(formation, {
            position = Vector.Zero,
            velocity = direction:Rotated(-90):Resized(speed),
        })
    end

    local randomShots = math.min(
        params:GetNumRandomDirTears(),
        MAX_FORMATION_SHOTS - #formation
    )
    local rng = familiar:GetDropRNG()
    for _ = 1, math.max(0, randomShots) do
        table.insert(formation, {
            position = Vector.Zero,
            velocity = Vector.FromAngle(rng:RandomFloat() * 360):Resized(speed),
        })
    end

    return formation
end

local function copyCommonData(source, target, familiar)
    local data = target:GetData()
    data[CLONE_KEY] = true
    data[EXPANDED_KEY] = true
    data[OWNER_KEY] = familiar
    target.Color = source.Color
    target.SpriteScale = source.SpriteScale
end

local function cloneTear(source, familiar, position, velocity)
    spawningClone = true
    local clone = Isaac.Spawn(
        EntityType.ENTITY_TEAR,
        source.Variant,
        source.SubType,
        position,
        velocity,
        familiar
    ):ToTear()
    spawningClone = false

    copyCommonData(source, clone, familiar)
    clone.CollisionDamage = source.CollisionDamage
    clone.TearFlags = source.TearFlags
    clone.Scale = source.Scale
    clone.Height = source.Height
    clone.FallingSpeed = source.FallingSpeed
    clone.FallingAcceleration = source.FallingAcceleration
    clone:GetData()[TEAR_SCALE_SOURCE_KEY] = source
    clone:GetData()[TEAR_SCALE_SYNC_KEY] = 3
    return clone
end

local function cloneBomb(source, familiar, position, velocity)
    spawningClone = true
    local clone = Isaac.Spawn(
        EntityType.ENTITY_BOMB,
        source.Variant,
        source.SubType,
        position,
        velocity,
        familiar
    ):ToBomb()
    spawningClone = false

    copyCommonData(source, clone, familiar)
    clone.ExplosionDamage = source.ExplosionDamage
    clone.RadiusMultiplier = source.RadiusMultiplier
    clone.Flags = source.Flags
    clone:SetExplosionCountdown(source:GetExplosionCountdown())
    return clone
end

local function copyLaser(source, target, familiar)
    copyCommonData(source, target, familiar)
    target.Parent = familiar
    target.ParentOffset = source.ParentOffset
    target.PositionOffset = source.PositionOffset
    target.CollisionDamage = source.CollisionDamage
    target.TearFlags = source.TearFlags
    target.Radius = source.Radius
    target.MaxDistance = source.MaxDistance
    target.Timeout = source.Timeout
    target:SetScale(source:GetScale())
    if source:GetData()[LASER_SCALE_KEY] then
        target:GetData()[LASER_SCALE_KEY] = true
    end
    target:SetNumChainedLasers(source:GetNumChainedLasers())
    target.DisableFollowParent = source.DisableFollowParent
end

local function cloneLaser(source, familiar, position, velocity)
    local player = familiar.Player
    local clone
    spawningClone = true
    if source:IsCircleLaser() then
        clone = player:FireTechXLaser(
            position,
            velocity,
            source.Radius,
            familiar,
            1
        )
    elseif BRIMSTONE_VARIANTS[source.Variant] then
        clone = player:FireBrimstone(
            velocity:Normalized(),
            familiar,
            1
        )
    else
        -- ShootAngle can turn Dynamic's one-frame Technology attack into an
        -- attached persistent beam. Clone its raw laser variant instead.
        clone = Isaac.Spawn(
            EntityType.ENTITY_LASER,
            source.Variant,
            source.SubType,
            position,
            Vector.Zero,
            familiar
        ):ToLaser()
    end
    spawningClone = false

    copyLaser(source, clone, familiar)
    if clone:IsCircleLaser() then
        clone.Velocity = velocity
    else
        clone.AngleDegrees = velocity:GetAngleDegrees()
        clone.Timeout = math.max(1, source.Timeout)
    end
    return clone
end

local function cloneKnife(source, familiar, position, velocity, baseDirection)
    spawningClone = true
    local clone = Isaac.Spawn(
        EntityType.ENTITY_KNIFE,
        source.Variant,
        source.SubType,
        position,
        Vector.Zero,
        familiar
    ):ToKnife()
    spawningClone = false

    copyCommonData(source, clone, familiar)
    clone.Parent = familiar
    clone.CollisionDamage = source.CollisionDamage
    clone.TearFlags = source.TearFlags
    clone.Scale = source.Scale
    clone.Rotation = velocity:GetAngleDegrees()
    clone:GetData()[KNIFE_ANGLE_KEY]
        = velocity:GetAngleDegrees() - baseDirection:GetAngleDegrees()

    local sourceData = source:GetData()
    if sourceData.DisappearMinisaac then
        local cloneData = clone:GetData()
        cloneData.DisappearMinisaac = true
        cloneData[SPIRIT_PROCESSED_KEY] = true
        cloneData[SPIRIT_SPIN_KEY] = sourceData[SPIRIT_SPIN_KEY]
        clone:GetSprite():Play(source:GetSprite():GetAnimation(), true)
        clone:SetIsSwinging(source:GetIsSwinging())
        clone:SetIsSpinAttack(source:GetIsSpinAttack())
    end
    return clone
end

local function placeOriginal(entity, origin, shot, baseDirection)
    entity.Position = origin + shot.position
    if entity.Type == EntityType.ENTITY_LASER then
        local laser = entity:ToLaser()
        if laser:IsCircleLaser() then
            laser.Velocity = shot.velocity
        else
            laser.AngleDegrees = shot.velocity:GetAngleDegrees()
        end
    elseif entity.Type == EntityType.ENTITY_KNIFE then
        local knife = entity:ToKnife()
        knife.Rotation = shot.velocity:GetAngleDegrees()
        knife:GetData()[KNIFE_ANGLE_KEY]
            = shot.velocity:GetAngleDegrees() - baseDirection:GetAngleDegrees()
    else
        entity.Velocity = shot.velocity
    end
end

local function expandEntity(entity, familiar, paramsByWeapon)
    local data = entity:GetData()
    if data[EXPANDED_KEY] or data[BURST_MEMBER_KEY] or data.RemoveMinisaacTimer then return end

    local player = familiar.Player
    if not player then return end

    local weaponType = weaponTypeFor(entity, player)
    local cached = paramsByWeapon[weaponType]
    if not cached then
        local params, formationWeaponType = resolveMultishotParams(
            player,
            weaponType
        )
        cached = {
            params = params,
            weaponType = formationWeaponType,
        }
        paramsByWeapon[weaponType] = cached
    end
    local direction, speed = entityDirection(entity, familiar)
    local formation = buildFormation(
        player,
        familiar,
        cached.weaponType,
        direction,
        speed,
        cached.params
    )
    data[EXPANDED_KEY] = true
    storeOwner(entity, familiar)

    if #formation <= 1 then return end

    local origin = entity.Position
    placeOriginal(entity, origin, formation[1], direction)

    for index = 2, #formation do
        local shot = formation[index]
        local position = origin + shot.position
        if entity.Type == EntityType.ENTITY_TEAR then
            cloneTear(entity:ToTear(), familiar, position, shot.velocity)
        elseif entity.Type == EntityType.ENTITY_BOMB then
            cloneBomb(entity:ToBomb(), familiar, position, shot.velocity)
        elseif entity.Type == EntityType.ENTITY_LASER then
            cloneLaser(entity:ToLaser(), familiar, position, shot.velocity)
        elseif entity.Type == EntityType.ENTITY_KNIFE then
            cloneKnife(
                entity:ToKnife(),
                familiar,
                position,
                shot.velocity,
                direction
            )
        end
    end
end

local function collectFreshAttacks(familiar, technicalTear)
    local attacks = {}
    for _, entity in ipairs(Isaac.FindInRadius(
        familiar.Position,
        24,
        EntityPartition.ALL
    )) do
        local owner = resolveOwner(entity)
        if entity.FrameCount <= 1
            and not sameEntity(entity, technicalTear)
            and owner
            and sameEntity(owner, familiar)
            and (entity.Type == EntityType.ENTITY_TEAR
                or entity.Type == EntityType.ENTITY_LASER
                or entity.Type == EntityType.ENTITY_BOMB
                or entity.Type == EntityType.ENTITY_KNIFE)
        then
            table.insert(attacks, entity)
        end
    end

    if technicalTear
        and not technicalTear:GetData().RemoveMinisaacTimer
    then
        table.insert(attacks, technicalTear)
    end
    return attacks
end

local function expandMonstroBurst(attacks, familiar, paramsByWeapon)
    local player = familiar.Player
    if not player
        or not player:HasWeaponType(WeaponType.WEAPON_MONSTROS_LUNGS)
    then
        return false
    end

    local pellets = {}
    for _, attack in ipairs(attacks) do
        if attack.Type == EntityType.ENTITY_TEAR
            and not attack:GetData().RemoveMinisaacTimer
        then
            table.insert(pellets, attack:ToTear())
        end
    end

    -- One Monstro burst already contains multiple scattered pellets. Multishot
    -- adds pellets per lane and complete bursts per active eye; expanding every
    -- pellet as a normal multishot entity would multiply the barrage twice.
    if #pellets < 5 then return false end

    local params = paramsByWeapon[WeaponType.WEAPON_TEARS]
    if not params then
        params = player:GetMultiShotParams(WeaponType.WEAPON_TEARS)
        paramsByWeapon[WeaponType.WEAPON_TEARS] = params
    end

    local baseVelocities = {}
    for index, pellet in ipairs(pellets) do
        pellet:GetData()[EXPANDED_KEY] = true
        baseVelocities[index] = pellet.Velocity
    end

    local rng = familiar:GetDropRNG()
    local baseDirection = directionForFamiliar(familiar)
    local eyeCount = math.max(1, math.min(
        MAX_FORMATION_SHOTS,
        params:GetNumEyesActive()
    ))
    local lanesPerEye = math.max(1, params:GetNumLanesPerEye())
    local multiEyeAngle = params:GetMultiEyeAngle()
    local bonusPerEye = math.floor(
        MONSTRO_EXTRA_PELLETS_PER_LANE * (lanesPerEye - 1)
    )

    local function eyeAngle(index)
        if eyeCount <= 1 then return 0 end
        return -multiEyeAngle
            + multiEyeAngle * 2 * ((index - 1) / (eyeCount - 1))
    end

    local function cloneBasePellet(sourceIndex, angle)
        local source = pellets[((sourceIndex - 1) % #pellets) + 1]
        return cloneTear(
            source,
            familiar,
            familiar.Position,
            baseVelocities[((sourceIndex - 1) % #pellets) + 1]:Rotated(angle)
        )
    end

    local function spawnBonusPellet(direction, sourceIndex)
        local source = pellets[((sourceIndex - 1) % #pellets) + 1]
        local speed = math.max(1, source.Velocity:Length())
            * (0.85 + rng:RandomFloat() * 0.3)
        local velocity = direction:Rotated(
            -18 + rng:RandomFloat() * 36
        ):Resized(speed)
        cloneTear(source, familiar, familiar.Position, velocity)
    end

    -- Reuse the original burst as the first eye and clone full barrages for
    -- additional eyes, preserving each pellet's own random spread.
    local firstAngle = eyeAngle(1)
    for index, pellet in ipairs(pellets) do
        pellet.Velocity = baseVelocities[index]:Rotated(firstAngle)
    end
    for eye = 1, eyeCount do
        local angle = eyeAngle(eye)
        local direction = baseDirection:Rotated(angle)
        if eye > 1 then
            for index = 1, #pellets do
                cloneBasePellet(index, angle)
            end
        end
        for index = 1, bonusPerEye do
            spawnBonusPellet(direction, index + eye)
        end
    end

    local burstDirections = {}
    if params:IsShootingBackwards() then
        table.insert(burstDirections, baseDirection:Rotated(180))
    end
    if params:IsShootingSideways() then
        table.insert(burstDirections, baseDirection:Rotated(90))
        table.insert(burstDirections, baseDirection:Rotated(-90))
    end
    for _, direction in ipairs(burstDirections) do
        for index = 1, #pellets do
            spawnBonusPellet(direction, index)
        end
    end

    local randomBursts = math.min(params:GetNumRandomDirTears(), 3)
    for burst = 1, randomBursts do
        local direction = Vector.FromAngle(rng:RandomFloat() * 360)
        for index = 1, math.max(1, math.floor(#pellets * 0.4)) do
            spawnBonusPellet(direction, index + burst)
        end
    end

    return true
end
local function trackTechnicalAttack(_, tear)
    if spawningClone then return end

    local familiar = asMiniIsaac(tear.SpawnerEntity)
    if familiar then
        familiar:GetData()[ATTACK_FRAME_KEY] = Game():GetFrameCount()
        if familiar.Player and hasSpecialWeapon(familiar.Player) then
            DynamicMinisaacContinued:RemoveDefaultTear(tear)
            if familiar.Player:HasWeaponType(WeaponType.WEAPON_KNIFE) then
                familiar:GetData().IsShootingMinisaacKnife = true
            end
        end
    end
end

local function isSplitChild(tear)
    local parent = tear.Parent
    local spawner = tear.SpawnerEntity
    return (parent and parent.Type == EntityType.ENTITY_TEAR)
        or (spawner and spawner.Type == EntityType.ENTITY_TEAR)
end

local function sanitizeSplitChild(_, tear)
    if not isSplitChild(tear) then return end
    if resolveOwner(tear) then
        tear:ClearTearFlags(RECURSIVE_SPLIT_FLAGS)
        tear:GetData()[EXPANDED_KEY] = true
    end
end

local function sanitizeFiredSplitTear(_, tear, sourceEntity)
    local familiar = sourceEntity and resolveOwner(sourceEntity)
    if not familiar then return end

    storeOwner(tear, familiar)
    tear:ClearTearFlags(RECURSIVE_SPLIT_FLAGS)
    tear:GetData()[EXPANDED_KEY] = true
end

local function expandDeferredLaser(_, laser)
    if spawningClone then return end
    local data = laser:GetData()
    if data[EXPANDED_KEY] or data[BURST_MEMBER_KEY] then return end

    local familiar = resolveOwner(laser)
    if not familiar or not familiar.Player then return end
    expandEntity(laser, familiar, {})
end

local function expandDeferredTear(_, tear)
    if spawningClone then return end
    local data = tear:GetData()
    if data[EXPANDED_KEY] or data[CLONE_KEY] or data.RemoveMinisaacTimer then
        return
    end

    local familiar = resolveOwner(tear)
    if not familiar or not familiar.Player then return end

    -- Special weapons are represented by their actual laser/knife/burst
    -- entities. Their technical tears must never become visible multishots.
    if hasSpecialWeapon(familiar.Player) then return end

    expandEntity(tear, familiar, {})
end

local function expandDeferredKnife(_, knife)
    if spawningClone then return end
    local data = knife:GetData()
    if data[EXPANDED_KEY] or not data.DisappearMinisaac then return end

    local familiar = resolveOwner(knife)
    if not familiar or not familiar.Player then return end
    expandEntity(knife, familiar, {})
end

local function collectPersistentKnives(familiar)
    local knives = {}
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_KNIFE,
        -1,
        -1,
        false,
        false
    )) do
        local knife = entity:ToKnife()
        local owner = resolveOwner(knife)
        if owner
            and sameEntity(owner, familiar)
            and knife.Variant ~= 10
            and knife.Variant ~= 11
        then
            table.insert(knives, knife)
        end
    end
    return knives
end

local function maintainKnifeFormation(_, familiar)
    if familiar.Variant ~= FamiliarVariant.MINISAAC then return end
    local player = familiar.Player
    if not player or not player:HasWeaponType(WeaponType.WEAPON_KNIFE) then
        for _, knife in ipairs(collectPersistentKnives(familiar)) do
            if knife:GetData()[EXTRA_KNIFE_KEY] then
                knife:Remove()
            end
        end
        return
    end

    local params = player:GetMultiShotParams(WeaponType.WEAPON_KNIFE)
    local desired = math.max(1, math.min(
        MAX_FORMATION_SHOTS,
        params:GetNumTears()
    ))
    local knives = collectPersistentKnives(familiar)
    if #knives == 0 then return end

    table.sort(knives, function(first, second)
        return first.InitSeed < second.InitSeed
    end)

    local base = knives[1]
    while #knives < desired do
        spawningClone = true
        local clone = Isaac.Spawn(
            EntityType.ENTITY_KNIFE,
            base.Variant,
            base.SubType,
            familiar.Position,
            Vector.Zero,
            familiar
        ):ToKnife()
        spawningClone = false
        copyCommonData(base, clone, familiar)
        clone.Parent = familiar
        clone.Scale = base.Scale
        clone.TearFlags = base.TearFlags
        clone:GetData()[EXTRA_KNIFE_KEY] = true
        table.insert(knives, clone)
    end

    for index = #knives, desired + 1, -1 do
        if knives[index]:GetData()[EXTRA_KNIFE_KEY] then
            knives[index]:Remove()
            table.remove(knives, index)
        end
    end

    local direction = directionForFamiliar(familiar)
    for index, knife in ipairs(knives) do
        local posVel = player:GetMultiShotPositionVelocity(
            index - 1,
            WeaponType.WEAPON_KNIFE,
            direction,
            1,
            params
        )
        local data = knife:GetData()
        data[KNIFE_INDEX_KEY] = index - 1
        data[KNIFE_ANGLE_KEY]
            = posVel.Velocity:GetAngleDegrees() - direction:GetAngleDegrees()
        if not knife:IsFlying() then
            knife.Position = familiar.Position + posVel.Position * FORMATION_POSITION_SCALE
        end
    end

    local familiarData = familiar:GetData()
    local anyFlying = false
    for _, knife in ipairs(knives) do
        if knife:IsFlying() then
            anyFlying = true
            break
        end
    end
    if anyFlying and not familiarData[KNIFE_VOLLEY_KEY] then
        local speedMultiplier = 1
        if DynamicMinisaacContinued.PlayerHasBFFS
            and DynamicMinisaacContinued:PlayerHasBFFS(familiar)
        then
            speedMultiplier = 1.4
        end
        for _, knife in ipairs(knives) do
            if not knife:IsFlying() then
                knife:Shoot(
                    0.7 * speedMultiplier,
                    190 * speedMultiplier
                )
            end
        end
    end
    familiarData[KNIFE_VOLLEY_KEY] = anyFlying
end

local function updateKnifeAngle(_, knife)
    local familiar = resolveOwner(knife)
    if not familiar then return end

    local data = knife:GetData()
    local offset = data[KNIFE_ANGLE_KEY] or 0
    local baseAngle = directionForFamiliar(familiar):GetAngleDegrees()
    if not data.DisappearMinisaac and data[KNIFE_ANGLE_KEY] then
        knife.Rotation = baseAngle + offset
    end
end

local function synchronizeCloneScale(_, tear)
    local data = tear:GetData()
    local ticks = data[TEAR_SCALE_SYNC_KEY]
    if not ticks then return end

    local source = data[TEAR_SCALE_SOURCE_KEY]
    if source and source:Exists() then
        tear.Scale = source.Scale
        tear.SpriteScale = source.SpriteScale
        tear.Size = source.Size
    end

    ticks = ticks - 1
    if ticks <= 0 or not source or not source:Exists() then
        data[TEAR_SCALE_SOURCE_KEY] = nil
        data[TEAR_SCALE_SYNC_KEY] = nil
    else
        data[TEAR_SCALE_SYNC_KEY] = ticks
    end
end
local function overrideCloneProcessing()
    if spawningClone then
        return true
    end
end

function Multishot.Register(mod)
    if type(DynamicMinisaacContinued) ~= "table" then
        Isaac.DebugString(
            "[Ascention] Dynamic Minisaac multishot support skipped: API unavailable"
        )
        return
    end

    local callbacks = DynamicMinisaacContinued.CustomCallbacks
    local overrideCallback = callbacks
        and callbacks.NEBUKA_PRE_CHECK_LOGICOVERRIDE
    if overrideCallback then
        mod:AddCallback(overrideCallback, overrideCloneProcessing)
    end

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, trackTechnicalAttack)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, sanitizeSplitChild)
    if ModCallbacks.MC_POST_FIRE_SPLIT_TEAR then
        mod:AddCallback(
            ModCallbacks.MC_POST_FIRE_SPLIT_TEAR,
            sanitizeFiredSplitTear
        )
    end
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, synchronizeCloneScale)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, sanitizeSplitChild)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, expandDeferredTear)
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, expandDeferredLaser)
    mod:AddCallback(
        ModCallbacks.MC_FAMILIAR_UPDATE,
        maintainKnifeFormation,
        FamiliarVariant.MINISAAC
    )
    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, expandDeferredKnife)
    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, updateKnifeAngle)
end

return Multishot
