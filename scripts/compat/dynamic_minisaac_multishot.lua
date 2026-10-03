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

local spawningClone = false

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
    return asMiniIsaac(entity.Parent) or asMiniIsaac(entity.SpawnerEntity)
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
    else
        clone = EntityLaser.ShootAngle(
            source.Variant,
            position,
            velocity:GetAngleDegrees(),
            math.max(1, source.Timeout),
            source.PositionOffset,
            familiar
        ):ToLaser()
    end
    spawningClone = false

    copyLaser(source, clone, familiar)
    if clone:IsCircleLaser() then
        clone.Velocity = velocity
    else
        clone.AngleDegrees = velocity:GetAngleDegrees()
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
        clone:GetData().DisappearMinisaac = true
        clone:GetSprite():Play(source:GetSprite():GetAnimation(), true)
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
    local params = paramsByWeapon[weaponType]
    if not params then
        params = player:GetMultiShotParams(weaponType)
        paramsByWeapon[weaponType] = params
    end
    local direction, speed = entityDirection(entity, familiar)
    local formation = buildFormation(
        player,
        familiar,
        weaponType,
        direction,
        speed,
        params
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

    if not technicalTear:GetData().RemoveMinisaacTimer then
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
local function onTearInit(_, tear)
    if spawningClone then return end

    local familiar = asMiniIsaac(tear.SpawnerEntity)
    if not familiar or not familiar.Player then return end

    local paramsByWeapon = {}
    local attacks = collectFreshAttacks(familiar, tear)
    if expandMonstroBurst(attacks, familiar, paramsByWeapon) then
        return
    end
    for _, attack in ipairs(attacks) do
        expandEntity(attack, familiar, paramsByWeapon)
    end
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
    local baseFlying = base:IsFlying()
    if baseFlying and not familiarData[KNIFE_VOLLEY_KEY] then
        local speedMultiplier = 1
        if DynamicMinisaacContinued.PlayerHasBFFS
            and DynamicMinisaacContinued:PlayerHasBFFS(familiar)
        then
            speedMultiplier = 1.4
        end
        for index = 2, #knives do
            if not knives[index]:IsFlying() then
                knives[index]:Shoot(
                    0.7 * speedMultiplier,
                    190 * speedMultiplier
                )
            end
        end
    end
    familiarData[KNIFE_VOLLEY_KEY] = baseFlying
end

local function updateKnifeAngle(_, knife)
    local familiar = resolveOwner(knife)
    if not familiar then return end

    local offset = knife:GetData()[KNIFE_ANGLE_KEY]
    if offset then
        knife.Rotation = directionForFamiliar(familiar):GetAngleDegrees() + offset
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

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, onTearInit)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, synchronizeCloneScale)
    mod:AddCallback(
        ModCallbacks.MC_FAMILIAR_UPDATE,
        maintainKnifeFormation,
        FamiliarVariant.MINISAAC
    )
    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, updateKnifeAngle)
end

return Multishot



