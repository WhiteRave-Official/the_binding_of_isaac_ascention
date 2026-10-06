local Arclight = {}
local ProjectileSpawnContext = include("scripts.projectile_spawn_context")
local MiniIsaacContext = include("scripts.minisaac.arclight_context")

local BASE_CHANCE = 0.25
local LUCK_CAP = 8.0
local MAX_CHANCE = 0.50
local WINDUP_TICKS = 8
local AIM_TICKS = 6
local FLIGHT_SPEED = 22.0
local INITIAL_FLIGHT_SPEED = -6.6
local FLIGHT_ACCELERATION = 1.6
local FLIGHT_ACCELERATION_GROWTH = 0.1
local HIT_RADIUS = 12.0
local STUCK_TICKS = 36
local MAX_FLIGHT_TICKS = 150
local WALL_COLLISION_GRACE_TICKS = 10
local KNIFE_RETURN_SPEED = 18.0
local KNIFE_RETURN_ACCELERATION = 1.8
local MAX_RETURN_TICKS = 90
local CHARGE_ARC_RADIUS = 46.0
local CHARGE_ARC_BACK_OFFSET = 30.0
local CHARGE_ARC_HALF_ANGLE = 58.0
local TECH_X_RADIUS = 14.0
local SYNERGY_LASER_DAMAGE = 0.50
local SOY_BRIMSTONE_LASER_DAMAGE = 0.20
local SOY_BRIMSTONE_LASER_TICKS = 2
local SPIN_PLAYBACK_SPEED = 0.8
local MINI_ISAAC_SWORD_SCALE = 0.6
local REAR_ARC_HALF_ANGLE = 65.0
local REAR_ARC_MIN_RADIUS = 26.0
local REAR_ARC_MAX_RADIUS = 40.0
local CONVERGENCE_DISTANCE = 100.0
local PAIR_CROSS_OFFSET = 18.0
local SYNERGY_TRIGGER_PROGRESS = 0.70
local SYNERGY_ORB_TICKS = 6
local AFTERIMAGE_INTERVAL = 2
local AFTERIMAGE_TICKS = 8
local MAX_MULTISHOT_SWORDS = 16
local HOMING_RADIUS = 320.0
local HOMING_TURN_SPEED = 5.0
local SPIRIT_SWORD_SCALE = 1.25
local SPIRIT_SWORD_SHIELD_TICKS = 30
local SPIRIT_SWORD_NORMAL_MIN = 1
local SPIRIT_SWORD_NORMAL_MAX = 2
local SPIRIT_SWORD_SPIN_MIN = 2
local SPIRIT_SWORD_SPIN_MAX = 4
local SPIRIT_SWORD_SPAWN_RADIUS = 32.0
local SHARD_PROJECTILE_SHEET = "gfx/effects/arclight_shard_projectile.png"
local SHARD_SPLAT_SHEET = "gfx/effects/arclight_shard_projectile_splat.png"
local SHARD_SPEED = 13.0
local SHARD_LIFETIME = 38
local MAX_SPLIT_CHILDREN = 8
local TINY_PLANET_ORBIT_TICKS = 54
local TINY_PLANET_START_RADIUS = 30.0
local TINY_PLANET_RADIUS_GROWTH = 0.75
local LUDOVICO_RADIUS = 30.0
local LUDOVICO_HIT_COOLDOWN = 12
local LUDOVICO_LUNGE_DISTANCE = 72.0
local LUDOVICO_LUNGE_TICKS = 16
local LUDOVICO_SWEEP_TICKS = 24
local MONSTROS_LUNG_MIN_SWORDS = 3
local MONSTROS_LUNG_MAX_SWORDS = 6
local MONSTROS_LUNG_HALF_ANGLE = 42.0
local RNG_SALT_ROLLED = 1101
local RNG_SALT_SPIRIT_NORMAL = 1102
local RNG_SALT_SPIRIT_SPIN = 1103
local RNG_SALT_MONSTRO_CHARGE = 1104
local RNG_SALT_C_SECTION_CONTACT = 1105
local ANTIGRAVITY_MAX_SWORDS = 10
local LOST_CONTACT_NORMAL_DURABILITY = 3
local LOST_CONTACT_HEAVY_DURABILITY = 5
local RUBBER_CEMENT_BOUNCES = 3
local spawningArclightShard = false
local SPIRIT_SWORD_VARIANT = KnifeVariant.SPIRIT_SWORD or 10
local TECH_SWORD_VARIANT = KnifeVariant.TECH_SWORD or 11

local BASIC_TEAR_FLAGS = TearFlags.TEAR_HOMING
    | TearFlags.TEAR_SLOW
    | TearFlags.TEAR_POISON
    | TearFlags.TEAR_FREEZE
    | TearFlags.TEAR_CHARM
    | TearFlags.TEAR_CONFUSION
    | TearFlags.TEAR_FEAR
    | TearFlags.TEAR_BURN
    | TearFlags.TEAR_KNOCKBACK
    | TearFlags.TEAR_MYSTERIOUS_LIQUID_CREEP
    | TearFlags.TEAR_LIGHT_FROM_HEAVEN
    | TearFlags.TEAR_BOOGER
    | TearFlags.TEAR_MIDAS
    | TearFlags.TEAR_ICE
    | TearFlags.TEAR_MAGNETIZE

local SHEETS = {
    default = "gfx/effects/arclight_projectile.png",
    soy = "gfx/effects/arclight_projectile_costume_soy_milk.png",
    brimstone = "gfx/effects/arclight_projectile_costume_brimstone.png",
    technology = "gfx/effects/arclight_projectile_costume_technology.png",
    momsKnife = "gfx/effects/arclight_projectile_costume_mom's_knife.png",
    spiritSword = "gfx/effects/spirit_sword_costume_arclight.png",
    ludovico = "gfx/effects/arclight_projectile_costume_ludovico.png",
    monstrosLung = "gfx/effects/arclight_projectile_costume_monstro's_lung.png",
    uranus = "gfx/effects/arclight_projectile_costume_uranus.png",
    rubberCement = "gfx/effects/arclight_projectile_costume_rubber_cement.png",
}

local spawningSynergyLaser = false
local BRIM_TECH_VARIANT = LaserVariant.BRIM_TECH
    or LaserVariant.BRIMSTONE_TECHNOLOGY
    or 9

local function chanceFor(player)
    local luck = math.max(0.0, math.min(LUCK_CAP, player.Luck))
    return BASE_CHANCE + (MAX_CHANCE - BASE_CHANCE) * luck / LUCK_CAP
end

local function captureBasicTearFlags(player, sourceFlags)
    return (sourceFlags or player.TearFlags) & BASIC_TEAR_FLAGS
end

local function hasTearFlag(flags, flag)
    return flags ~= nil and flags & flag ~= TearFlags.TEAR_NORMAL
end

local function weaponTypeForSynergy(synergy)
    if synergy == "moms_knife" then return WeaponType.WEAPON_KNIFE end
    if synergy == "brimstone" or synergy == "brimstone_soy"
    or synergy == "brimstone_techx" then
        return WeaponType.WEAPON_BRIMSTONE
    end
    if synergy == "techx" then return WeaponType.WEAPON_TECH_X end
    if synergy == "technology" then return WeaponType.WEAPON_LASER end
    return WeaponType.WEAPON_TEARS
end

local function getMultishotCount(player, synergy)
    local params = player:GetMultiShotParams(weaponTypeForSynergy(synergy))
    return math.max(1, math.min(MAX_MULTISHOT_SWORDS, params:GetNumTears()))
end

local function mixSeed(seed, value)
    return ((seed ~ (value or 0)) * 1103515245 + 12345) & 0x7fffffff
end

local function eventRng(player, source, salt)
    local seed = Game():GetSeeds():GetStartSeed()
    seed = mixSeed(seed, player.InitSeed)
    seed = mixSeed(seed, source and source.InitSeed or 0)
    seed = mixSeed(seed, Game():GetFrameCount())
    seed = mixSeed(seed, salt or 0)
    if seed == 0 then seed = 1 end

    local rng = RNG()
    rng:SetSeed(seed, 35)
    return rng
end

local function rollMonstrosLungSwordCount(rng)
    return MONSTROS_LUNG_MIN_SWORDS
        + rng:RandomInt(MONSTROS_LUNG_MAX_SWORDS
            - MONSTROS_LUNG_MIN_SWORDS + 1)
end

local function getChargedSwordCount(player, synergy, source)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then
        local sourceData = (source or player):GetData()
        if not sourceData.ArclightMonstrosLungSwordCount then
            local rng = eventRng(player, source or player,
                RNG_SALT_MONSTRO_CHARGE)
            sourceData.ArclightMonstrosLungSwordCount
                = rollMonstrosLungSwordCount(rng)
        end
        return sourceData.ArclightMonstrosLungSwordCount
    end
    local count = math.max(2, getMultishotCount(player, synergy))
    if count == 2 and player:HasCollectible(
        CollectibleType.COLLECTIBLE_20_20) then
        return 3
    end
    return count
end

local function getRolledSwordCount(player, synergy, rng)
    local count = getMultishotCount(player, synergy)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_INNER_EYE)
    or player:HasCollectible(CollectibleType.COLLECTIBLE_MUTANT_SPIDER) then
        return rng:RandomInt(count) + 1
    end
    return count
end

local function centeredSlot(index, count)
    return index - (count + 1) * 0.5
end
local function isSwordCopyFamiliar(entity)
    local familiar = entity and entity:ToFamiliar()
    return familiar and (familiar.Variant == FamiliarVariant.INCUBUS
        or familiar.Variant == FamiliarVariant.TWISTED_BABY)
end

local function resolveAttackContext(entity)
    local current = entity
    for _ = 1, 6 do
        if not current then return nil, nil end
        local player = current:ToPlayer()
        if player then return player, player end
        if isSwordCopyFamiliar(current) then
            local familiar = current:ToFamiliar()
            return familiar.Player, familiar
        end
        current = current.Parent or current.SpawnerEntity
    end
    return nil, nil
end

local function resolveProjectileContext(projectile)
    if not projectile then return nil, nil end
    local miniProxy = MiniIsaacContext.ForProjectile(projectile)
    if miniProxy then return miniProxy.Player, miniProxy end
    local parent = projectile.Parent
    local spawner = projectile.SpawnerEntity

    if isSwordCopyFamiliar(parent) then
        local familiar = parent:ToFamiliar()
        return familiar.Player, familiar
    end
    if isSwordCopyFamiliar(spawner) then
        local familiar = spawner:ToFamiliar()
        return familiar.Player, familiar
    end

    local player, source = resolveAttackContext(parent)
    if player then return player, source end
    return resolveAttackContext(spawner)
end

local function isSpiritSwordKnife(knife)
    return knife and (knife.Variant == SPIRIT_SWORD_VARIANT
        or knife.Variant == TECH_SWORD_VARIANT)
end

local function findFetusTear(entity)
    local pending = { entity }
    local seen = {}
    for _ = 1, 12 do
        local current = table.remove(pending, 1)
        if not current then return nil end
        local hash = GetPtrHash(current)
        if not seen[hash] then
            seen[hash] = true
            local tear = current:ToTear()
            if tear and (tear.Variant == TearVariant.FETUS
            or tear:HasTearFlags(TearFlags.TEAR_FETUS)) then
                return tear
            end
            if current.Parent then pending[#pending + 1] = current.Parent end
            if current.SpawnerEntity then
                pending[#pending + 1] = current.SpawnerEntity
            end
        end
    end
    return nil
end

local function isFetusSpawnedAttack(entity)
    local knife = entity and entity:ToKnife()
    return (knife and TearFlags.TEAR_FETUS_SWORD
        and hasTearFlag(knife.TearFlags, TearFlags.TEAR_FETUS_SWORD))
        or findFetusTear(entity) ~= nil
end

local function sourcePosition(source, player)
    return MiniIsaacContext.Position(source)
        or (source and source:Exists() and source.Position or player.Position)
end

local function formationAngle(index, count)
    if count <= 1 then return 0.0 end
    return -CHARGE_ARC_HALF_ANGLE
        + (index - 1) * CHARGE_ARC_HALF_ANGLE * 2.0 / (count - 1)
end

local function formationPosition(source, player, direction, index, count)
    local center = sourcePosition(source, player)
        - direction * CHARGE_ARC_BACK_OFFSET
    if count <= 1 then return center + direction * CHARGE_ARC_RADIUS end

    local averageForward = 0.0
    for current = 1, count do
        averageForward = averageForward
            + math.cos(math.rad(formationAngle(current, count)))
    end
    averageForward = averageForward / count

    local offset = direction:Rotated(formationAngle(index, count))
        - direction * averageForward
    return center + offset * CHARGE_ARC_RADIUS
end

local function validDirection(direction, player)
    if direction and direction:LengthSquared() > 0.001 then
        return direction:Normalized()
    end
    local aim = player:GetAimDirection()
    if aim:LengthSquared() > 0.001 then return aim:Normalized() end
    local fireDirection = player:GetFireDirection()
    if fireDirection == Direction.LEFT then return Vector(-1, 0) end
    if fireDirection == Direction.RIGHT then return Vector(1, 0) end
    if fireDirection == Direction.UP then return Vector(0, -1) end
    if fireDirection == Direction.DOWN then return Vector(0, 1) end
    return Vector(0, 1)
end

local function getSynergy(player)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_SPIRIT_SWORD) then
        return "spirit_sword"
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
        return "moms_knife"
    end
    local hasBrimstone = player:HasCollectible(
        CollectibleType.COLLECTIBLE_BRIMSTONE)
    local hasTechX = player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X)
    if hasBrimstone and hasTechX then
        return "brimstone_techx"
    end
    if hasBrimstone and player:HasCollectible(
        CollectibleType.COLLECTIBLE_SOY_MILK) then
        return "brimstone_soy"
    end
    if hasBrimstone then
        return "brimstone"
    end
    if hasTechX then
        return "techx"
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY) then
        return "technology"
    end
    return nil
end

local function spiritSwordPayload(player)
    local hasBrimstone = player:HasCollectible(
        CollectibleType.COLLECTIBLE_BRIMSTONE)
    local hasTechX = player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X)
    if hasBrimstone and hasTechX then return "brimstone_techx" end
    if hasBrimstone and player:HasCollectible(
        CollectibleType.COLLECTIBLE_SOY_MILK) then
        return "brimstone_soy"
    end
    if hasBrimstone then return "brimstone" end
    if hasTechX then return "techx" end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY) then
        return "technology"
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
        return "moms_knife"
    end
    return nil
end

local function sheetFor(player, synergy, state)
    if synergy == "moms_knife" then return SHEETS.momsKnife end
    if synergy == "brimstone" or synergy == "brimstone_soy"
    or synergy == "brimstone_techx" then
        return SHEETS.brimstone
    end
    if synergy == "technology" or synergy == "techx" then
        return SHEETS.technology
    end
    if state == "LUDOVICO" then return SHEETS.ludovico end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then
        return SHEETS.monstrosLung
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_URANUS) then
        return SHEETS.uranus
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_RUBBER_CEMENT) then
        return SHEETS.rubberCement
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK) then
        return SHEETS.soy
    end
    return SHEETS.default
end

local function play(sprite, animation)
    if not sprite:IsPlaying(animation) then sprite:Play(animation, true) end
end

local function getChargeSword(source, index)
    local pointers = source:GetData().ArclightChargeSwords
    local entity = pointers and pointers[index] and pointers[index].Ref
    if entity and entity:Exists() then return entity:ToEffect() end
    return nil
end

local function clearChargeSwords(source, remove)
    local sourceData = source:GetData()
    local pointers = sourceData.ArclightChargeSwords
    if remove and pointers then
        for _, pointer in ipairs(pointers) do
            local entity = pointer and pointer.Ref
            if entity and entity:Exists() then entity:Remove() end
        end
    end
    sourceData.ArclightChargeSwords = nil
    if remove then sourceData.ArclightMonstrosLungSwordCount = nil end
end

local function configureBasicSynergies(data, player)
    data.myReflection = player:HasCollectible(
        CollectibleType.COLLECTIBLE_MY_REFLECTION)
    data.continuum = player:HasCollectible(
        CollectibleType.COLLECTIBLE_CONTINUUM)
    data.rubberCement = player:HasCollectible(
        CollectibleType.COLLECTIBLE_RUBBER_CEMENT)
    data.lostContact = player:HasCollectible(
        CollectibleType.COLLECTIBLE_LOST_CONTACT)
    data.tinyPlanet = player:HasCollectible(
        CollectibleType.COLLECTIBLE_TINY_PLANET)
    data.aimControlled = player:HasCollectible(
        CollectibleType.COLLECTIBLE_MARKED)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT)
    data.parasite = player:HasCollectible(
        CollectibleType.COLLECTIBLE_PARASITE)
    data.cricketsBody = player:HasCollectible(
        CollectibleType.COLLECTIBLE_CRICKETS_BODY)
    data.compoundFracture = player:HasCollectible(
        CollectibleType.COLLECTIBLE_COMPOUND_FRACTURE)
    data.haemolacria = player:HasCollectible(
        CollectibleType.COLLECTIBLE_HAEMOLACRIA)
    data.damageMultiplier = data.haemolacria and 0.75 or 0.50
    data.hitRadius = data.haemolacria and HIT_RADIUS * 1.6 or HIT_RADIUS
    data.projectileScale = data.haemolacria and 1.45 or 1.0
    data.maxFlightTicks = MAX_FLIGHT_TICKS
    data.wallBounces = data.rubberCement and RUBBER_CEMENT_BOUNCES or 0
    data.lostContactDurability = data.lostContact and
        (data.haemolacria and LOST_CONTACT_HEAVY_DURABILITY
            or LOST_CONTACT_NORMAL_DURABILITY) or 0
end

local function spawnSword(player, source, variant, direction, position, synergy,
                          state, pairIndex, sourceFlags, sourceColor)
    local effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, variant, 0,
        position, Vector.Zero, source or player):ToEffect()
    effect.Parent = source or player
    effect.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    effect.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    effect.DepthOffset = 20

    local sprite = effect:GetSprite()
    local sheet = sheetFor(player, synergy, state)
    sprite:ReplaceSpritesheet(0, sheet)
    sprite:LoadGraphics()
    sprite:Play("Spin", true)
    sprite.PlaybackSpeed = SPIN_PLAYBACK_SPEED

    local data = effect:GetData()
    data.Arclight = {
        owner = EntityPtr(player),
        source = EntityPtr(source or player),
        direction = validDirection(direction, player),
        state = state or "WINDUP",
        stateFrame = 0,
        flightFrame = 0,
        hitSeeds = {},
        synergy = synergy,
        sheet = sheet,
        pairIndex = pairIndex or 0,
        chargeIdle = 0,
        tearFlags = captureBasicTearFlags(player, sourceFlags),
        sourceColor = sourceColor or player.LaserColor,
    }
    configureBasicSynergies(data.Arclight, player)
    if MiniIsaacContext.MiniForSource(source) then
        data.Arclight.projectileScale = data.Arclight.projectileScale
            * MINI_ISAAC_SWORD_SCALE
        data.Arclight.hitRadius = data.Arclight.hitRadius
            * MINI_ISAAC_SWORD_SCALE
    end
    sprite.Scale = sprite.Scale * data.Arclight.projectileScale
    return effect
end

local function distanceToRoomBoundary(position, direction)
    local room = Game():GetRoom()
    local distance = 16.0
    while distance < 800.0
    and room:IsPositionInRoom(position + direction * distance, 8.0) do
        distance = distance + 16.0
    end
    return distance
end

local function applyLaserModifiers(laser, tearFlags, sourceColor)
    local flags = tearFlags or TearFlags.TEAR_NORMAL
    local homing = hasTearFlag(flags, TearFlags.TEAR_HOMING)
    laser:AddTearFlags(flags)
    if homing then laser:SetHomingType(1125515264) end

    local color = homing and Color.LaserHoming or sourceColor
    if color then
        laser.Color = color
        laser:GetSprite().Color = color
    end
    laser:RecalculateSamplesNextUpdate()
end

local function fireLinearLaser(player, source, position, direction, brimstone,
                               tearFlags, sourceColor, synergy)
    local hasTechnology = player:HasCollectible(
        CollectibleType.COLLECTIBLE_TECHNOLOGY)
    local hasSoyMilk = player:HasCollectible(
        CollectibleType.COLLECTIBLE_SOY_MILK)
    local variant = LaserVariant.THIN_RED
    if brimstone and hasTechnology then
        variant = BRIM_TECH_VARIANT
    elseif brimstone then
        variant = LaserVariant.THICK_RED
    end

    local duration = brimstone and 8 or 5
    local damageMultiplier = SYNERGY_LASER_DAMAGE
    if brimstone and hasSoyMilk then
        duration = SOY_BRIMSTONE_LASER_TICKS
        damageMultiplier = SOY_BRIMSTONE_LASER_DAMAGE
    end

    spawningSynergyLaser = true
    local laser = EntityLaser.ShootAngle(variant, position,
        direction:GetAngleDegrees(), duration, Vector.Zero, player):ToLaser()
    spawningSynergyLaser = false
    if not laser then return end

    local laserData = laser:GetData()
    laserData.ArclightSynergyLaser = true
    if synergy == "brimstone_soy" then
        laserData.ArclightSoyBeam = {
            owner = EntityPtr(player),
            source = EntityPtr(source or player),
        }
    end
    applyLaserModifiers(laser, tearFlags, sourceColor)
    laser.Parent = source or player
    laser:SetDisableFollowParent(true)
    laser.Position = position
    laser.Velocity = Vector.Zero
    laser.CollisionDamage = player.Damage * damageMultiplier
    laser.MaxDistance = math.max(32.0,
        distanceToRoomBoundary(position, direction) - 8.0)
    laser:SetScale(laser:GetScale() * 0.55)
    laser:RecalculateSamplesNextUpdate()
end

local function fireBrimstoneRing(player, source, position, direction, tearFlags,
                                 sourceColor)
    spawningSynergyLaser = true
    local laser = player:FireTechXLaser(position,
        direction:Resized(FLIGHT_SPEED * 0.55), TECH_X_RADIUS,
        player, SYNERGY_LASER_DAMAGE)
    spawningSynergyLaser = false
    if not laser then return end

    local laserData = laser:GetData()
    laserData.ArclightSynergyLaser = true
    laserData.ArclightMovingRing = true
    applyLaserModifiers(laser, tearFlags, sourceColor)
    laser.Parent = source or player
    laser:SetDisableFollowParent(true)
    laser.Position = position
    laser.Velocity = direction:Resized(FLIGHT_SPEED * 0.55)
    laser:SetScale(laser:GetScale() * 0.75)
end

local function fireTechXAura(player, sword)
    spawningSynergyLaser = true
    local laser = player:FireTechXLaser(sword.Position, Vector.Zero,
        TECH_X_RADIUS, player, SYNERGY_LASER_DAMAGE)
    spawningSynergyLaser = false
    if not laser then return nil end

    laser:GetData().ArclightSynergyLaser = true
    local swordData = sword:GetData().Arclight
    applyLaserModifiers(laser,
        swordData and swordData.tearFlags or TearFlags.TEAR_NORMAL,
        swordData and swordData.sourceColor or nil)
    laser:SetDisableFollowParent(true)
    laser.Position = sword.Position
    laser.Velocity = sword.Velocity
    laser:SetTimeout(2)
    laser:SetScale(laser:GetScale() * 0.65)
    return laser
end
local function getTechXAura(data)
    local entity = data.techXAura and data.techXAura.Ref
    if entity and entity:Exists() then return entity:ToLaser() end
    return nil
end

local function syncTechXAura(effect, data)
    local laser = getTechXAura(data)
    if not laser then return end
    laser.Position = effect.Position
    laser.Velocity = effect.Velocity
    laser:SetTimeout(2)
end

local function removeTechXAura(data)
    local laser = getTechXAura(data)
    if laser then laser:Remove() end
    data.techXAura = nil
end

local function fireTechnologyTether(player, sword)
    local swordData = sword:GetData().Arclight
    local sourceEntity = swordData and swordData.source and swordData.source.Ref
    local origin = sourcePosition(sourceEntity, player)
    local delta = sword.Position - origin
    spawningSynergyLaser = true
    local laser = EntityLaser.ShootAngle(LaserVariant.THIN_RED,
        origin, delta:GetAngleDegrees(), 2, Vector.Zero, player):ToLaser()
    spawningSynergyLaser = false
    if not laser then return nil end

    laser:GetData().ArclightSynergyLaser = true
    applyLaserModifiers(laser,
        swordData and swordData.tearFlags or TearFlags.TEAR_NORMAL,
        swordData and swordData.sourceColor or nil)
    laser:SetDisableFollowParent(true)
    laser.Position = origin
    laser.MaxDistance = delta:Length()
    laser.CollisionDamage = player.Damage * SYNERGY_LASER_DAMAGE
    return laser
end

local function getTechnologyTether(data)
    local entity = data.technologyTether and data.technologyTether.Ref
    if entity and entity:Exists() then return entity:ToLaser() end
    return nil
end

local function syncTechnologyTether(effect, data, owner)
    local laser = getTechnologyTether(data)
    if not laser then return end
    local sourceEntity = data.source and data.source.Ref
    local origin = sourcePosition(sourceEntity, owner)
    local delta = effect.Position - origin
    local angle = delta:GetAngleDegrees()
    laser.Position = origin
    laser.Velocity = Vector.Zero
    laser.AngleDegrees = angle
    laser.LastAngleDegrees = angle
    laser.MaxDistance = delta:Length()
    laser.CollisionDamage = owner.Damage * SYNERGY_LASER_DAMAGE
    laser.Timeout = 2
    laser:RecalculateSamplesNextUpdate()
end
local function removeTechnologyTether(data)
    local laser = getTechnologyTether(data)
    if laser then laser:Remove() end
    data.technologyTether = nil
end

local function removeSwordAttachments(data)
    removeTechXAura(data)
    removeTechnologyTether(data)
end
local function spawnAfterimage(effect, data)
    local afterimage = Isaac.Spawn(EntityType.ENTITY_EFFECT, effect.Variant, 0,
        effect.Position, Vector.Zero, effect):ToEffect()
    afterimage.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    afterimage.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    afterimage.DepthOffset = effect.DepthOffset - 1

    local sprite = afterimage:GetSprite()
    sprite:ReplaceSpritesheet(0, data.sheet)
    sprite:LoadGraphics()
    sprite:Play("Idle", true)
    sprite.Rotation = effect:GetSprite().Rotation
    sprite.Scale = effect:GetSprite().Scale
    afterimage.Color = Color(1.0, 1.0, 1.0, 0.45, 0.35, 0.35, 0.35)
    afterimage:GetData().ArclightAfterimage = { age = 0 }
end

local function updateAfterimage(effect, data)
    data.age = data.age + 1
    local alpha = math.max(0.0, 0.45 * (1.0 - data.age / AFTERIMAGE_TICKS))
    effect.Color = Color(1.0, 1.0, 1.0, alpha, 0.35, 0.35, 0.35)
    if data.age >= AFTERIMAGE_TICKS then effect:Remove() end
end

local function spawnSynergyOrb(player, source, position, direction, synergy,
                                 tearFlags, sourceColor)
    local usesBrimstone = synergy == "brimstone"
        or synergy == "brimstone_soy"
        or synergy == "brimstone_techx"
    local variant = usesBrimstone
        and EffectVariant.BRIMSTONE_SWIRL or EffectVariant.TECH_DOT
    local orb = Isaac.Spawn(EntityType.ENTITY_EFFECT, variant, 0,
        position, Vector.Zero, source or player):ToEffect()
    orb.Parent = source or player
    orb.DepthOffset = 25
    orb.SpriteScale = Vector(0.65, 0.65)
    if sourceColor then orb.Color = sourceColor end
    orb:GetData().ArclightSynergyOrb = {
        owner = EntityPtr(player),
        source = EntityPtr(source or player),
        direction = direction,
        synergy = synergy,
        tearFlags = tearFlags,
        sourceColor = sourceColor,
        age = 0,
    }
end

local function updateSynergyOrb(effect)
    local data = effect:GetData().ArclightSynergyOrb
    if not data then return end
    local ownerEntity = data.owner and data.owner.Ref
    local owner = ownerEntity and ownerEntity:ToPlayer()
    local source = data.source and data.source.Ref
    if not owner or not owner:Exists() or not source or not source:Exists() then
        effect:Remove()
        return
    end

    effect.Velocity = Vector.Zero
    data.age = data.age + 1
    if data.age < SYNERGY_ORB_TICKS then return end

    local firePosition = effect.Position
    effect:Remove()
    if data.synergy == "brimstone_techx" then
        fireBrimstoneRing(owner, source, firePosition, data.direction,
            data.tearFlags, data.sourceColor)
    else
        fireLinearLaser(owner, source, firePosition, data.direction,
            data.synergy == "brimstone" or data.synergy == "brimstone_soy",
            data.tearFlags, data.sourceColor, data.synergy)
    end
end

local function sourceIsFiring(source, owner)
    if MiniIsaacContext.MiniForSource(source) then
        local aim = MiniIsaacContext.Aim(source)
        return aim ~= nil and aim:LengthSquared() > 0.001
    end
    local player = source and source:ToPlayer()
    local controller = player or owner
    return controller:GetFireDirection() ~= Direction.NO_DIRECTION
        or controller:GetAimDirection():LengthSquared() > 0.001
end

local function updateSoyBeam(laser)
    local data = laser:GetData().ArclightSoyBeam
    if not data then return end
    local owner = data.owner and data.owner.Ref
    local source = data.source and data.source.Ref
    owner = owner and owner:ToPlayer()
    if owner and owner:Exists() and source and source:Exists()
    and sourceIsFiring(source, owner) then
        laser.Timeout = SOY_BRIMSTONE_LASER_TICKS
    end
end
local function releaseKnifePairSlot(owner, data)
    if data.synergy ~= "moms_knife" or data.knifePairReleased then return end
    data.knifePairReleased = true
    local source = data.source and data.source.Ref
    local sourceData = source and source:Exists() and source:GetData()
        or owner:GetData()
    local remaining = math.max(0,
        (sourceData.ArclightKnifePairActive or 1) - 1)
    sourceData.ArclightKnifePairActive = remaining > 0 and remaining or nil
end

local function beginFlight(effect, data, owner)
    if data.tinyPlanet and not data.tinyPlanetComplete then
        data.state = "ORBIT"
        data.stateFrame = 0
        data.orbitAngle = (effect.Position - owner.Position):GetAngleDegrees()
        data.orbitDirection = data.pairIndex < 0 and -1 or 1
        return
    end
    data.state = "FLY"
    data.stateFrame = 0
    data.flightFrame = 0
    data.hitSeeds = {}
    data.previousPosition = effect.Position
    data.launchOrigin = effect.Position
    data.initialFlightDirection = data.direction
    data.flightSpeed = data.haemolacria
        and INITIAL_FLIGHT_SPEED * 0.65 or INITIAL_FLIGHT_SPEED
    data.flightAcceleration = data.haemolacria
        and FLIGHT_ACCELERATION * 0.70 or FLIGHT_ACCELERATION
    data.synergyTriggered = false
    data.synergyTriggerDistance = distanceToRoomBoundary(
        effect.Position, data.direction) * SYNERGY_TRIGGER_PROGRESS
    data.returnsToOwner = data.synergy == "moms_knife" or data.myReflection
    data.maxFlightDistance = data.returnsToOwner
        and math.max(100.0, owner.TearRange) or nil
    effect.Velocity = data.direction * data.flightSpeed
    effect:GetSprite().PlaybackSpeed = 1.0
    play(effect:GetSprite(), "Idle")

    local knifeMode = data.synergy == "moms_knife"
    if data.synergy == "techx" or data.synergy == "brimstone_techx"
    or (knifeMode and owner:HasCollectible(
        CollectibleType.COLLECTIBLE_TECH_X)) then
        local aura = fireTechXAura(owner, effect)
        data.techXAura = aura and EntityPtr(aura) or nil
    end
    if knifeMode and owner:HasCollectible(
        CollectibleType.COLLECTIBLE_TECHNOLOGY) then
        local tether = fireTechnologyTether(owner, effect)
        data.technologyTether = tether and EntityPtr(tether) or nil
    end
end

local function launchPair(player, source, variant, direction, synergy,
                          sourceFlags, sourceColor)
    source = source or player
    local sourceData = source:GetData()
    if synergy == "moms_knife" and sourceData.ArclightKnifePairActive then
        return
    end
    local frame = Game():GetFrameCount()
    local lastFrame = sourceData.ArclightPairLaunchFrame
    local repeatWindow = player:HasCollectible(
        CollectibleType.COLLECTIBLE_MONSTROS_LUNG) and 4 or 0
    if lastFrame and frame - lastFrame <= repeatWindow then return end
    sourceData.ArclightPairLaunchFrame = frame

    local normalized = validDirection(MiniIsaacContext.Aim(source, direction), player)
    local perpendicular = Vector(-normalized.Y, normalized.X)
    local count = getChargedSwordCount(player, synergy, source)
    local swords = {}
    for index = 1, count do
        swords[index] = getChargeSword(source, index)
    end

    local center = sourcePosition(source, player)
    for index = 1, count do
        local slot = centeredSlot(index, count)
        local sword = swords[index]
        if not sword then
            local position = formationPosition(source, player, normalized,
                index, count)
            sword = spawnSword(player, source, variant, normalized, position,
                synergy, "CHARGING", slot, sourceFlags, sourceColor)
        end
        local data = sword:GetData().Arclight
        if player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then
            local angle = count > 1
                and slot * MONSTROS_LUNG_HALF_ANGLE * 2.0 / (count - 1)
                or 0.0
            data.direction = normalized:Rotated(angle)
        else
            local crossTarget = center + normalized * CONVERGENCE_DISTANCE
                - perpendicular * slot * PAIR_CROSS_OFFSET
            data.direction = validDirection(crossTarget - sword.Position, player)
        end
        data.synergy = synergy
        data.sheet = sheetFor(player, synergy, data.state)
        data.pairIndex = slot
        data.formationIndex = index
        data.formationCount = count
        data.tearFlags = captureBasicTearFlags(player, sourceFlags)
        data.sourceColor = sourceColor or player.LaserColor
        beginFlight(sword, data, player)
    end
    clearChargeSwords(source, false)
    sourceData.ArclightMonstrosLungSwordCount = nil
    if synergy == "moms_knife" then
        sourceData.ArclightKnifePairActive = count
    end
end

local function rollSword(player, rng)
    return rng:RandomFloat() < chanceFor(player)
end

local function spawnRolledSword(player, source, variant, direction, synergy,
                                sourceFlags, sourceColor)
    source = source or player
    local sourceData = source:GetData()
    local frame = Game():GetFrameCount()
    local lastFrame = sourceData.ArclightRolledAttackFrame
    local hasMonstrosLung = player:HasCollectible(
        CollectibleType.COLLECTIBLE_MONSTROS_LUNG)
    local repeatWindow = hasMonstrosLung and 4 or 0
    if lastFrame and frame - lastFrame <= repeatWindow then return end
    sourceData.ArclightRolledAttackFrame = frame
    local rng = eventRng(player, source, RNG_SALT_ROLLED)
    if not hasMonstrosLung and not rollSword(player, rng) then return end

    local count = hasMonstrosLung
        and rollMonstrosLungSwordCount(rng)
        or getRolledSwordCount(player, synergy, rng)
    local normalized = validDirection(MiniIsaacContext.Aim(source, direction), player)
    local params = player:GetMultiShotParams(weaponTypeForSynergy(synergy))
    local spread = params:GetSpreadAngle(weaponTypeForSynergy(synergy))
    local center = sourcePosition(source, player)
    local storesSwords = player:HasCollectible(
        CollectibleType.COLLECTIBLE_ANTI_GRAVITY)
    local stored = storesSwords and (sourceData.ArclightStoredSwords or {}) or nil
    for index = 1, count do
        if storesSwords and #stored >= ANTIGRAVITY_MAX_SWORDS then break end
        local slot = centeredSlot(index, count)
        local angleOffset
        if hasMonstrosLung then
            angleOffset = count > 1
                and slot * MONSTROS_LUNG_HALF_ANGLE * 2.0 / (count - 1)
                or 0.0
        else
            angleOffset = count > 1
                and slot * spread * 2.0 / (count - 1) or 0.0
        end
        local swordDirection = normalized:Rotated(angleOffset)
        local rearAngle = 180.0 - REAR_ARC_HALF_ANGLE
            + rng:RandomFloat() * REAR_ARC_HALF_ANGLE * 2.0
        local radius = REAR_ARC_MIN_RADIUS
            + rng:RandomFloat() * (REAR_ARC_MAX_RADIUS - REAR_ARC_MIN_RADIUS)
        local spawnPosition = center
            + swordDirection:Rotated(rearAngle) * radius
        local target = center + swordDirection * CONVERGENCE_DISTANCE
        local launchDirection = validDirection(target - spawnPosition, player)
        local sword = spawnSword(player, source, variant, launchDirection,
            spawnPosition, synergy, storesSwords and "STORED" or "WINDUP",
            slot, sourceFlags, sourceColor)
        if storesSwords then
            stored[#stored + 1] = EntityPtr(sword)
            local swordData = sword:GetData().Arclight
            swordData.formationIndex = #stored
        end
    end
    if storesSwords then sourceData.ArclightStoredSwords = stored end
end

local function releaseStoredSwords(player, source)
    source = source or player
    local pointers = source:GetData().ArclightStoredSwords
    if not pointers then return end
    for _, pointer in ipairs(pointers) do
        local sword = pointer and pointer.Ref
        if sword and sword:Exists() then
            local data = sword:GetData().Arclight
            beginFlight(sword:ToEffect(), data, player)
        end
    end
    source:GetData().ArclightStoredSwords = nil
end

local function ludovicoSpriteOffset(tear)
    local offset = tear.SpriteOffset or Vector.Zero
    local height = tear.Height or -23.0
    return offset + Vector(0.0, height)
end

local function spawnLudovicoSwords(player, source, tear, variant)
    local sourceData = source:GetData()
    local active = sourceData.ArclightLudovicoSwords
    if active then
        for _, pointer in ipairs(active) do
            local sword = pointer and pointer.Ref
            if sword and sword:Exists() then return end
        end
    end

    local count = getMultishotCount(player, nil)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_SPIRIT_SWORD) then
        count = math.max(2, count)
    end
    active = {}
    for index = 1, count do
        local angle = (index - 1) * 360.0 / count
        local position = tear.Position + Vector.FromAngle(angle) * LUDOVICO_RADIUS
        local payload = player:HasCollectible(
            CollectibleType.COLLECTIBLE_SPIRIT_SWORD)
            and spiritSwordPayload(player) or nil
        local sword = spawnSword(player, source, variant, Vector.FromAngle(angle),
            position, payload, "LUDOVICO", centeredSlot(index, count),
            tear.TearFlags, tear.Color)
        local data = sword:GetData().Arclight
        data.ludovicoTear = EntityPtr(tear)
        data.ludovicoAngle = angle
        data.ludovicoIndex = index
        data.ludovicoCount = count
        data.hitCooldowns = {}
        data.spiritSwordLudovico = player:HasCollectible(
            CollectibleType.COLLECTIBLE_SPIRIT_SWORD)
        sword.SpriteOffset = ludovicoSpriteOffset(tear)
        data.hitRadius = data.hitRadius * 1.25
        sword:GetSprite().Scale = sword:GetSprite().Scale * 1.35
        if payload == "techx" or payload == "brimstone_techx" then
            local aura = fireTechXAura(player, sword)
            data.techXAura = aura and EntityPtr(aura) or nil
        end
        active[index] = EntityPtr(sword)
    end
    sourceData.ArclightLudovicoSwords = active
end

local function ensureLudovicoSwords(player, variant)
    if not player:HasCollectible(Arclight.ItemId)
    or not player:HasCollectible(
        CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then return end

    local active = player:GetData().ArclightLudovicoSwords
    if active then
        for _, pointer in ipairs(active) do
            local sword = pointer and pointer.Ref
            if sword and sword:Exists() then return end
        end
    end

    local weapon = player:GetWeapon(1)
    local mainEntity = weapon and weapon:GetMainEntity()
    local mainTear = mainEntity and mainEntity:ToTear()
    if mainTear and mainTear:HasTearFlags(TearFlags.TEAR_LUDOVICO) then
        spawnLudovicoSwords(player, player, mainTear, variant)
        return
    end

    local tears = Isaac.FindByType(EntityType.ENTITY_TEAR,
        -1, -1, false, false)
    table.sort(tears, function(left, right)
        return left.InitSeed < right.InitSeed
    end)
    for _, entity in ipairs(tears) do
        local tear = entity:ToTear()
        if tear and tear:HasTearFlags(TearFlags.TEAR_LUDOVICO) then
            local owner, source = resolveProjectileContext(tear)
            if owner and GetPtrHash(owner) == GetPtrHash(player) then
                spawnLudovicoSwords(player, source or player, tear, variant)
                return
            end
        end
    end
end

local function commandLudovicoSwords(source, attackKind, direction)
    local sourceData = source:GetData()
    local pointers = sourceData.ArclightLudovicoSwords
    if not pointers or #pointers == 0 then return false end

    if attackKind == "spin" then
        local commanded = false
        for _, pointer in ipairs(pointers) do
            local entity = pointer and pointer.Ref
            local sword = entity and entity:ToEffect()
            local data = sword and sword:GetData().Arclight
            if sword and sword:Exists() and data and data.spiritSwordLudovico then
                data.state = "LUDOVICO_SWEEP"
                data.stateFrame = 0
                data.hitSeeds = {}
                commanded = true
            end
        end
        return commanded
    end

    local count = #pointers
    local start = (sourceData.ArclightLudovicoNext or 0) % count + 1
    for offset = 0, count - 1 do
        local index = (start + offset - 1) % count + 1
        local entity = pointers[index] and pointers[index].Ref
        local sword = entity and entity:ToEffect()
        local data = sword and sword:GetData().Arclight
        if sword and sword:Exists() and data and data.spiritSwordLudovico
        and data.state == "LUDOVICO" then
            data.state = "LUDOVICO_LUNGE"
            data.stateFrame = 0
            data.ludovicoAttackDirection = direction
            data.hitSeeds = {}
            sourceData.ArclightLudovicoNext = index
            return true
        end
    end
    return false
end

local function randomCount(rng, minimum, maximum)
    return minimum + rng:RandomInt(maximum - minimum + 1)
end

local function configureSpiritSwordProjectile(sword)
    local data = sword:GetData().Arclight
    data.spiritSwordProjectile = true
    data.deferSynergyUntilEnd = true
end

local function spawnSpiritSwordNormal(player, source, variant, direction,
                                      sourceFlags, sourceColor)
    source = source or player
    local rng = eventRng(player, source, RNG_SALT_SPIRIT_NORMAL)
    if not rollSword(player, rng) then return end

    local count = randomCount(rng, SPIRIT_SWORD_NORMAL_MIN,
        SPIRIT_SWORD_NORMAL_MAX)
    local normalized = validDirection(MiniIsaacContext.Aim(source, direction), player)
    local center = sourcePosition(source, player)
    local payload = spiritSwordPayload(player)

    for index = 1, count do
        local rearAngle = 180.0 - REAR_ARC_HALF_ANGLE
            + rng:RandomFloat() * REAR_ARC_HALF_ANGLE * 2.0
        local radius = REAR_ARC_MIN_RADIUS
            + rng:RandomFloat() * (REAR_ARC_MAX_RADIUS - REAR_ARC_MIN_RADIUS)
        local spawnPosition = center + normalized:Rotated(rearAngle) * radius
        local target = center + normalized * CONVERGENCE_DISTANCE
        local launchDirection = validDirection(target - spawnPosition, player)
        local sword = spawnSword(player, source, variant, launchDirection,
            spawnPosition, payload, "WINDUP", centeredSlot(index, count),
            sourceFlags, sourceColor)
        configureSpiritSwordProjectile(sword)
    end
end

local function spawnSpiritSwordSpin(player, source, variant, direction,
                                    sourceFlags, sourceColor)
    source = source or player
    local rng = eventRng(player, source, RNG_SALT_SPIRIT_SPIN)
    local center = sourcePosition(source, player)
    local payload = spiritSwordPayload(player)
    local hasMonstrosLung = player:HasCollectible(
        CollectibleType.COLLECTIBLE_MONSTROS_LUNG)
    local count
    if hasMonstrosLung then
        count = rollMonstrosLungSwordCount(rng)
    else
        count = randomCount(rng, SPIRIT_SWORD_SPIN_MIN,
            SPIRIT_SWORD_SPIN_MAX)
    end

    local normalized = validDirection(MiniIsaacContext.Aim(source, direction), player)
    local startAngle = rng:RandomFloat() * 360.0
    for index = 1, count do
        local swordDirection
        local spawnPosition
        if hasMonstrosLung then
            local slot = centeredSlot(index, count)
            local angle = count > 1
                and slot * MONSTROS_LUNG_HALF_ANGLE * 2.0 / (count - 1)
                or 0.0
            swordDirection = normalized:Rotated(angle)
            local perpendicular = Vector(-normalized.Y, normalized.X)
            spawnPosition = center - normalized * SPIRIT_SWORD_SPAWN_RADIUS
                + perpendicular * slot * 5.0
        else
            swordDirection = Vector.FromAngle(startAngle
                + (index - 1) * 360.0 / count)
            spawnPosition = center
                + swordDirection * SPIRIT_SWORD_SPAWN_RADIUS
        end
        local sword = spawnSword(player, source, variant, swordDirection,
            spawnPosition, payload, "WINDUP", centeredSlot(index, count),
            sourceFlags, sourceColor)
        configureSpiritSwordProjectile(sword)
    end
end

local function spiritSwordDirection(animation, player)
    if animation:find("Right$") then return Vector(1.0, 0.0) end
    if animation:find("Left$") then return Vector(-1.0, 0.0) end
    if animation:find("Up$") then return Vector(0.0, -1.0) end
    if animation:find("Down$") then return Vector(0.0, 1.0) end
    return validDirection(player:GetAimDirection(), player)
end

local function updateSpiritSwordKnife(knife, variant)
    if not isSpiritSwordKnife(knife) then return end

    local fetusSource = findFetusTear(knife)
    local player, source = resolveProjectileContext(knife)
    if fetusSource then source = fetusSource end
    if not player or not player:HasCollectible(Arclight.ItemId)
    or not player:HasCollectible(CollectibleType.COLLECTIBLE_SPIRIT_SWORD) then
        return
    end

    local data = knife:GetData()
    if not data.ArclightSpiritSwordVisual then
        data.ArclightSpiritSwordVisual = true
        knife.Scale = knife.Scale * SPIRIT_SWORD_SCALE
        knife.SpriteScale = knife.SpriteScale * SPIRIT_SWORD_SCALE
        local sprite = knife:GetSprite()
        sprite:ReplaceSpritesheet(0, SHEETS.spiritSword)
        sprite:LoadGraphics()
    end

    -- Keep the regular C Section synergy, suppress only the recursive Lung fan.
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG)
    and isFetusSpawnedAttack(knife) then
        return
    end
    if knife.SubType ~= 0 then return end

    local sprite = knife:GetSprite()
    local animation = sprite:GetAnimation()
    local attackKind
    if animation:find("^Attack") then
        attackKind = "normal"
    elseif animation:find("^Spin") then
        attackKind = "spin"
    end

    if not attackKind then
        data.ArclightSpiritSwordAttack = nil
        return
    end
    if data.ArclightSpiritSwordAttack == animation then return end
    data.ArclightSpiritSwordAttack = animation

    local sourceData = source:GetData()
    local frame = Game():GetFrameCount()
    if sourceData.ArclightSpiritSwordAttackFrame == frame then return end
    sourceData.ArclightSpiritSwordAttackFrame = frame

    local direction = spiritSwordDirection(animation, player)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE)
    and commandLudovicoSwords(source, attackKind, direction) then
        return
    end
    if attackKind == "spin" then
        spawnSpiritSwordSpin(player, source, variant, direction,
            knife.TearFlags, knife.Color)
    else
        spawnSpiritSwordNormal(player, source, variant, direction,
            knife.TearFlags, knife.Color)
    end
end

local function spawnCSectionContactSword(player, fetus, target, variant)
    local fetusData = fetus:GetData()
    local frame = Game():GetFrameCount()
    fetusData.ArclightContactTargets = fetusData.ArclightContactTargets or {}
    if fetusData.ArclightContactTargets[target.InitSeed] == frame then return end
    fetusData.ArclightContactTargets[target.InitSeed] = frame
    local rng = eventRng(player, fetus,
        RNG_SALT_C_SECTION_CONTACT ~ target.InitSeed)
    if not rollSword(player, rng) then return end

    local spawnOffset = Vector.FromAngle(rng:RandomFloat() * 360.0)
        * (20.0 + rng:RandomFloat() * 12.0)
    local spawnPosition = fetus.Position + spawnOffset
    local direction = validDirection(target.Position - spawnPosition, player)
    spawnSword(player, fetus, variant, direction, spawnPosition,
        spiritSwordPayload(player), "WINDUP", 0, fetus.TearFlags, fetus.Color)
end

local function handleCSectionContactDamage(target, damageSource, variant)
    local sourceEntity = damageSource and damageSource.Entity
    local fetus = sourceEntity and sourceEntity:ToTear()
    if not fetus or (fetus.Variant ~= TearVariant.FETUS
    and not fetus:HasTearFlags(TearFlags.TEAR_FETUS)) then
        return
    end

    local player = resolveAttackContext(fetus)
    if not player or not player:HasCollectible(Arclight.ItemId)
    or not player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
        return
    end
    spawnCSectionContactSword(player, fetus, target, variant)
end

local function resolveDamageOwner(entity)
    local current = entity
    for _ = 1, 8 do
        if not current then return nil end
        local player = current:ToPlayer()
        if player then return player end
        local familiar = current:ToFamiliar()
        if familiar and familiar.Player then return familiar.Player end
        current = current.Parent or current.SpawnerEntity
    end
    return nil
end
local function ensureChargePair(player, source, variant, synergy)
    source = source or player
    local sourceData = source:GetData()
    local count = getChargedSwordCount(player, synergy, source)
    local pointers = sourceData.ArclightChargeSwords
    local complete = pointers ~= nil
    for index = 1, count do
        if not getChargeSword(source, index) then
            complete = false
            break
        end
    end
    if complete and #pointers == count then return end

    clearChargeSwords(source, true)
    pointers = {}
    local direction = validDirection(player:GetAimDirection(), player)
    for index = 1, count do
        local slot = centeredSlot(index, count)
        local position = formationPosition(source, player, direction,
            index, count)
        local sword = spawnSword(player, source, variant, direction, position,
            synergy, "CHARGING", slot)
        local data = sword:GetData().Arclight
        data.formationIndex = index
        data.formationCount = count
        pointers[index] = EntityPtr(sword)
    end
    sourceData.ArclightChargeSwords = pointers
end

local function updateChargePair(player, variant)
    if not player:HasCollectible(Arclight.ItemId) then
        clearChargeSwords(player, true)
        return
    end
    local synergy = getSynergy(player)
    if synergy ~= "brimstone" and synergy ~= "brimstone_soy"
    and synergy ~= "brimstone_techx" and synergy ~= "techx"
    and synergy ~= "moms_knife" then
        clearChargeSwords(player, true)
        player:GetData().ArclightSoyBrimstoneFiring = nil
        return
    end

    if synergy == "brimstone_soy" then
        local playerData = player:GetData()
        local firing = sourceIsFiring(player, player)
        if firing and not playerData.ArclightSoyBrimstoneFiring then
            launchPair(player, player, variant, player:GetAimDirection(),
                synergy, player.TearFlags, player.LaserColor)
        end
        playerData.ArclightSoyBrimstoneFiring = firing
        if not firing then clearChargeSwords(player, true) end
        return
    end
    player:GetData().ArclightSoyBrimstoneFiring = nil

    local weapon = player:GetWeapon(1)
    local charge = weapon and weapon:GetCharge() or 0.0
    if charge > 0.0 then
        ensureChargePair(player, player, variant, synergy)
    else
        local first = getChargeSword(player, 1)
        if first then
            local data = first:GetData().Arclight
            data.chargeIdle = (data.chargeIdle or 0) + 1
            if data.chargeIdle > 3 then clearChargeSwords(player, true) end
        end
    end
end
local function distanceSquaredToSegment(point, startPosition, endPosition)
    local segment = endPosition - startPosition
    local lengthSquared = segment:LengthSquared()
    if lengthSquared <= 0.001 then
        return point:DistanceSquared(endPosition)
    end
    local progress = math.max(0.0, math.min(1.0,
        (point - startPosition):Dot(segment) / lengthSquared))
    local closest = startPosition + segment * progress
    return point:DistanceSquared(closest)
end

local function rotateTowards(current, target, maxDegrees)
    local currentAngle = current:GetAngleDegrees()
    local targetAngle = target:GetAngleDegrees()
    local difference = (targetAngle - currentAngle + 180.0) % 360.0 - 180.0
    difference = math.max(-maxDegrees, math.min(maxDegrees, difference))
    return Vector.FromAngle(currentAngle + difference)
end

local function updateControlledAim(effect, data, owner)
    if not data.aimControlled then return end

    local desired
    local source = data.source and data.source.Ref
    local mini = MiniIsaacContext.MiniForSource(source)
    if mini then
        local aim = MiniIsaacContext.Aim(source)
        if aim then desired = mini.Position + aim - effect.Position end
    else
        local target = owner:GetMarkedTarget()
        if target and target:Exists() then
            desired = target.Position - effect.Position
        else
            desired = owner:GetAimDirection()
        end
    end
    if not desired or desired:LengthSquared() <= 0.001 then return end

    data.direction = rotateTowards(data.direction, desired:Normalized(), 12.0)
end

local function updateMovingRingHoming(laser)
    local data = laser:GetData()
    if not data.ArclightMovingRing
    or not laser:HasTearFlags(TearFlags.TEAR_HOMING)
    or laser.Velocity:LengthSquared() <= 0.001 then
        return
    end

    local candidates = Isaac.FindInRadius(laser.Position,
        HOMING_RADIUS, EntityPartition.ENEMY)
    table.sort(candidates, function(left, right)
        local leftDistance = left.Position:DistanceSquared(laser.Position)
        local rightDistance = right.Position:DistanceSquared(laser.Position)
        if leftDistance == rightDistance then return left.InitSeed < right.InitSeed end
        return leftDistance < rightDistance
    end)

    for _, enemy in ipairs(candidates) do
        if enemy:IsActiveEnemy(false) and enemy:IsVulnerableEnemy()
        and not enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            local target = enemy.Position - laser.Position
            if target:LengthSquared() > 0.001 then
                local speed = laser.Velocity:Length()
                local direction = rotateTowards(laser.Velocity:Normalized(),
                    target:Normalized(), HOMING_TURN_SPEED)
                laser.Velocity = direction * speed
            end
            return
        end
    end
end

local function updateSwordHoming(effect, data)
    if not hasTearFlag(data.tearFlags, TearFlags.TEAR_HOMING)
    or data.flightSpeed <= 0.0 then
        return
    end

    local candidates = Isaac.FindInRadius(effect.Position,
        HOMING_RADIUS, EntityPartition.ENEMY)
    table.sort(candidates, function(left, right)
        local leftDistance = left.Position:DistanceSquared(effect.Position)
        local rightDistance = right.Position:DistanceSquared(effect.Position)
        if leftDistance == rightDistance then return left.InitSeed < right.InitSeed end
        return leftDistance < rightDistance
    end)

    for _, enemy in ipairs(candidates) do
        if enemy:IsActiveEnemy(false) and enemy:IsVulnerableEnemy()
        and not enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            local targetDirection = enemy.Position - effect.Position
            if targetDirection:LengthSquared() > 0.001 then
                data.direction = rotateTowards(data.direction,
                    targetDirection:Normalized(), HOMING_TURN_SPEED)
            end
            return
        end
    end
end
local function spawnShard(owner, source, data, direction, damageMultiplier,
                           scale, lifetime)
    spawningArclightShard = true
    local tear = owner:FireTear(source.Position,
        direction:Normalized() * SHARD_SPEED, false, true, false, source,
        damageMultiplier)
    spawningArclightShard = false
    if not tear then return nil end
    tear.CollisionDamage = owner.Damage * damageMultiplier
    tear.Scale = scale
    tear.Height = -5.0
    tear.FallingSpeed = 0.0
    tear.FallingAcceleration = 0.0
    tear:AddTearFlags(data.tearFlags or TearFlags.TEAR_NORMAL)
    local tearData = tear:GetData()
    tearData.ArclightShard = true
    tearData.ArclightShardLife = lifetime or SHARD_LIFETIME
    local sprite = tear:GetSprite()
    sprite:ReplaceSpritesheet(0, SHARD_PROJECTILE_SHEET)
    sprite:LoadGraphics()
    return tear
end

local function spawnSplitChildren(effect, data, owner)
    if data.splitTriggered then return end
    if not data.parasite and not data.cricketsBody
    and not data.compoundFracture and not data.haemolacria then return end
    data.splitTriggered = true
    local children = {}
    local function add(angle, damage, scale, lifetime)
        if #children >= MAX_SPLIT_CHILDREN then return end
        children[#children + 1] = {angle = angle, damage = damage,
            scale = scale, lifetime = lifetime}
    end
    if data.parasite then
        add(-28.0, 0.28, 0.72, SHARD_LIFETIME)
        add(28.0, 0.28, 0.72, SHARD_LIFETIME)
    end
    if data.cricketsBody then
        for _, angle in ipairs({45.0, 135.0, 225.0, 315.0}) do
            add(angle, 0.20, 0.62, 30)
        end
    end
    if data.compoundFracture then
        for index = 0, 5 do add(index * 60.0, 0.18, 0.58, 26) end
    end
    if data.haemolacria then
        for _, angle in ipairs({-60.0, -30.0, 0.0, 30.0, 60.0}) do
            add(angle, 0.25, 0.78, SHARD_LIFETIME)
        end
    end
    local base = data.direction or Vector(0.0, 1.0)
    for _, child in ipairs(children) do
        spawnShard(owner, effect, data, base:Rotated(child.angle),
            child.damage, child.scale, child.lifetime)
    end
end

local function destroyEnemyProjectiles(effect, data)
    if not data.lostContact or data.lostContactDurability <= 0 then return false end
    local projectiles = Isaac.FindInRadius(effect.Position,
        (data.hitRadius or HIT_RADIUS) + 10.0, EntityPartition.BULLET)
    table.sort(projectiles, function(left, right)
        return left.InitSeed < right.InitSeed
    end)
    for _, entity in ipairs(projectiles) do
        local projectile = entity:ToProjectile()
        if projectile and projectile:Exists() then
            projectile:Die()
            data.lostContactDurability = data.lostContactDurability - 1
            data.flightSpeed = data.flightSpeed * 0.86
            if data.lostContactDurability <= 0 then
                removeSwordAttachments(data)
                effect:Remove()
                return true
            end
        end
    end
    return false
end

local function wrapContinuum(effect, nextPosition)
    local room = Game():GetRoom()
    local topLeft = room:GetTopLeftPos()
    local bottomRight = room:GetBottomRightPos()
    local position = effect.Position
    if nextPosition.X < topLeft.X then position.X = bottomRight.X - 10.0
    elseif nextPosition.X > bottomRight.X then position.X = topLeft.X + 10.0 end
    if nextPosition.Y < topLeft.Y then position.Y = bottomRight.Y - 10.0
    elseif nextPosition.Y > bottomRight.Y then position.Y = topLeft.Y + 10.0 end
    effect.Position = position
end

local function bounceFromRoomBoundary(effect, data, nextPosition)
    local room = Game():GetRoom()
    local direction = data.direction
    if not room:IsPositionInRoom(Vector(nextPosition.X, effect.Position.Y), 8.0) then
        direction = Vector(-direction.X, direction.Y)
    end
    if not room:IsPositionInRoom(Vector(effect.Position.X, nextPosition.Y), 8.0) then
        direction = Vector(direction.X, -direction.Y)
    end
    data.direction = direction:Normalized()
    data.wallBounces = data.wallBounces - 1
    data.damageMultiplier = data.damageMultiplier * 0.85
    data.flightSpeed = data.flightSpeed * 0.90
    data.previousPosition = effect.Position
end

local function strikeEnemy(effect, data, owner, enemy)
    if data.hitSeeds[enemy.InitSeed] then return end
    data.hitSeeds[enemy.InitSeed] = true
    local damage = owner.Damage * (data.damageMultiplier or 0.50)
    enemy:TakeDamage(damage, 0, EntityRef(effect), 0)
    local npc = enemy:ToNPC()
    if npc and data.tearFlags ~= TearFlags.TEAR_NORMAL then
        npc:ApplyTearflagEffects(effect.Position, data.tearFlags,
            effect, damage)
    end

    spawnSplitChildren(effect, data, owner)
    local rng = effect:GetDropRNG()
    if rng:RandomFloat() < chanceFor(owner) then
        Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.CRACK_THE_SKY, 1,
            enemy.Position, Vector.Zero, owner)
    end
end

local function damageWithLudovicoSword(effect, data, owner)
    local frame = Game():GetFrameCount()
    if (frame + (data.ludovicoIndex or 0)) % 3 ~= 0 then return end

    local enemies = Isaac.FindInRadius(effect.Position,
        (data.hitRadius or HIT_RADIUS) + 20.0, EntityPartition.ENEMY)
    table.sort(enemies, function(left, right)
        return left.InitSeed < right.InitSeed
    end)
    for _, enemy in ipairs(enemies) do
        if enemy:IsActiveEnemy(false) and enemy:IsVulnerableEnemy()
        and not enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
        and frame >= (data.hitCooldowns[enemy.InitSeed] or 0) then
            data.hitSeeds[enemy.InitSeed] = nil
            strikeEnemy(effect, data, owner, enemy)
            data.hitCooldowns[enemy.InitSeed] = frame + LUDOVICO_HIT_COOLDOWN
        end
    end
end

local function updateSword(effect)
    local effectData = effect:GetData()
    if effectData.ArclightAfterimage then
        updateAfterimage(effect, effectData.ArclightAfterimage)
        return
    end
    local data = effectData.Arclight
    if not data then return end
    local ownerEntity = data.owner and data.owner.Ref
    local owner = ownerEntity and ownerEntity:ToPlayer()
    local source = data.source and data.source.Ref
    if not owner or not owner:Exists() or not source or not source:Exists()
    or not owner:HasCollectible(Arclight.ItemId) then
        removeSwordAttachments(data)
        if owner and owner:Exists() then releaseKnifePairSlot(owner, data) end
        effect:Remove()
        return
    end

    local sprite = effect:GetSprite()
    data.stateFrame = data.stateFrame + 1

    if data.state == "CHARGING" then
        local aim = validDirection(MiniIsaacContext.Aim(source,
            owner:GetAimDirection()), owner)
        local target = formationPosition(source, owner, aim,
            data.formationIndex or 1, data.formationCount or 1)
        effect.Position = effect.Position + (target - effect.Position) * 0.35
        effect.Velocity = Vector.Zero
        data.direction = aim
        data.chargeIdle = 0
        sprite.PlaybackSpeed = SPIN_PLAYBACK_SPEED
        play(sprite, "Spin")
        return
    elseif data.state == "STORED" then
        effect.Velocity = Vector.Zero
        sprite.PlaybackSpeed = SPIN_PLAYBACK_SPEED
        play(sprite, "Spin")
    elseif data.state == "LUDOVICO" or data.state == "LUDOVICO_LUNGE"
    or data.state == "LUDOVICO_SWEEP" then
        local tearEntity = data.ludovicoTear and data.ludovicoTear.Ref
        local tear = tearEntity and tearEntity:ToTear()
        if not tear or not tear:Exists() then
            removeSwordAttachments(data)
            effect:Remove()
            return
        end

        effect.SpriteOffset = ludovicoSpriteOffset(tear)
        effect.Velocity = Vector.Zero
        if data.state == "LUDOVICO_LUNGE" then
            local progress = math.min(1.0,
                data.stateFrame / LUDOVICO_LUNGE_TICKS)
            local distance = math.sin(progress * math.pi)
                * LUDOVICO_LUNGE_DISTANCE
            local orbitPosition = tear.Position
                + Vector.FromAngle(data.ludovicoAngle) * LUDOVICO_RADIUS
            local attackDirection = validDirection(
                data.ludovicoAttackDirection, owner)
            effect.Position = orbitPosition + attackDirection * distance
            sprite.Rotation = attackDirection:GetAngleDegrees() - 90.0
            play(sprite, "Idle")
            if data.stateFrame >= LUDOVICO_LUNGE_TICKS then
                data.state = "LUDOVICO"
                data.stateFrame = 0
            end
        elseif data.state == "LUDOVICO_SWEEP" then
            data.ludovicoAngle = data.ludovicoAngle
                + 360.0 / LUDOVICO_SWEEP_TICKS
            effect.Position = tear.Position
                + Vector.FromAngle(data.ludovicoAngle)
                    * (LUDOVICO_RADIUS + 10.0)
            sprite.Rotation = data.ludovicoAngle
            play(sprite, "Idle")
            if data.stateFrame >= LUDOVICO_SWEEP_TICKS then
                data.state = "LUDOVICO"
                data.stateFrame = 0
            end
        else
            data.ludovicoAngle = data.ludovicoAngle + 2.5
            effect.Position = tear.Position
                + Vector.FromAngle(data.ludovicoAngle) * LUDOVICO_RADIUS
            sprite.Rotation = data.ludovicoAngle
            play(sprite, "Idle")
        end
        syncTechXAura(effect, data)
        damageWithLudovicoSword(effect, data, owner)
    elseif data.state == "ORBIT" then
        data.orbitAngle = data.orbitAngle
            + data.orbitDirection * 360.0 / TINY_PLANET_ORBIT_TICKS
        local radius = TINY_PLANET_START_RADIUS
            + data.stateFrame * TINY_PLANET_RADIUS_GROWTH
        effect.Position = sourcePosition(source, owner)
            + Vector.FromAngle(data.orbitAngle) * radius
        effect.Velocity = Vector.Zero
        sprite.PlaybackSpeed = SPIN_PLAYBACK_SPEED
        play(sprite, "Spin")
        if data.stateFrame >= 8
        and hasTearFlag(data.tearFlags, TearFlags.TEAR_HOMING) then
            local enemies = Isaac.FindInRadius(effect.Position, HOMING_RADIUS,
                EntityPartition.ENEMY)
            table.sort(enemies, function(left, right)
                local ld = left.Position:DistanceSquared(effect.Position)
                local rd = right.Position:DistanceSquared(effect.Position)
                if ld == rd then return left.InitSeed < right.InitSeed end
                return ld < rd
            end)
            local target = enemies[1]
            if target and target:IsActiveEnemy(false) then
                data.direction = validDirection(target.Position - effect.Position,
                    owner)
                data.tinyPlanetComplete = true
                beginFlight(effect, data, owner)
                return
            end
        end
        if data.stateFrame >= TINY_PLANET_ORBIT_TICKS then
            data.direction = Vector.FromAngle(data.orbitAngle
                + data.orbitDirection * 90.0)
            data.tinyPlanetComplete = true
            beginFlight(effect, data, owner)
        end
    elseif data.state == "WINDUP" then
        effect.Velocity = effect.Velocity * 0.75
        sprite.PlaybackSpeed = SPIN_PLAYBACK_SPEED
        play(sprite, "Spin")
        if data.stateFrame >= WINDUP_TICKS then
            data.state = "AIM"
            data.stateFrame = 0
        end
    elseif data.state == "AIM" then
        effect.Velocity = effect.Velocity * 0.65
        updateControlledAim(effect, data, owner)
        sprite.PlaybackSpeed = 1.0
        sprite.Rotation = data.direction:GetAngleDegrees() - 90.0
        play(sprite, "Aim")
        if data.stateFrame >= AIM_TICKS then beginFlight(effect, data, owner) end
    elseif data.state == "FLY" then
        data.flightFrame = data.flightFrame + 1
        data.flightSpeed = math.min(FLIGHT_SPEED,
            data.flightSpeed + data.flightAcceleration)
        data.flightAcceleration = data.flightAcceleration
            + FLIGHT_ACCELERATION_GROWTH
        updateControlledAim(effect, data, owner)
        updateSwordHoming(effect, data)
        effect.Velocity = data.direction * data.flightSpeed
        if destroyEnemyProjectiles(effect, data) then return end
        syncTechXAura(effect, data)
        syncTechnologyTether(effect, data, owner)
        sprite.PlaybackSpeed = 1.0
        sprite.Rotation = data.direction:GetAngleDegrees() - 90.0
        play(sprite, "Idle")

        if data.flightSpeed > 0.0
        and data.flightFrame % AFTERIMAGE_INTERVAL == 0 then
            spawnAfterimage(effect, data)
        end

        local forwardDistance = math.max(0.0,
            (effect.Position - data.launchOrigin):Dot(data.direction))
        if not data.synergyTriggered and not data.deferSynergyUntilEnd
        and (data.synergy == "brimstone"
            or data.synergy == "brimstone_soy"
            or data.synergy == "brimstone_techx"
            or data.synergy == "technology")
        and forwardDistance >= data.synergyTriggerDistance then
            data.synergyTriggered = true
            spawnSynergyOrb(owner, source, data.launchOrigin,
                data.initialFlightDirection, data.synergy, data.tearFlags,
                data.sourceColor)
        end

        local previousPosition = data.previousPosition
            or (effect.Position - effect.Velocity)
        if data.flightSpeed > 0.0 then
            local candidates = Isaac.FindInRadius(effect.Position,
                (data.hitRadius or HIT_RADIUS) + FLIGHT_SPEED + 40.0, EntityPartition.ENEMY)
            table.sort(candidates, function(left, right)
                return left.InitSeed < right.InitSeed
            end)
            for _, enemy in ipairs(candidates) do
                if enemy:IsActiveEnemy(false) and enemy:IsVulnerableEnemy()
                and not enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
                and distanceSquaredToSegment(enemy.Position, previousPosition,
                    effect.Position) <= ((data.hitRadius or HIT_RADIUS) + enemy.Size) ^ 2 then
                    strikeEnemy(effect, data, owner, enemy)
                end
            end
        end
        data.previousPosition = effect.Position

        local nextPosition = effect.Position + effect.Velocity
        local hitWall = data.flightFrame > WALL_COLLISION_GRACE_TICKS
            and not Game():GetRoom():IsPositionInRoom(nextPosition, 8.0)
        if hitWall and data.continuum then
            wrapContinuum(effect, nextPosition)
            data.previousPosition = effect.Position
            return
        elseif hitWall and data.wallBounces > 0 then
            bounceFromRoomBoundary(effect, data, nextPosition)
            return
        end
        if hitWall or data.flightFrame >= (data.maxFlightTicks or MAX_FLIGHT_TICKS)
        or (data.maxFlightDistance
            and forwardDistance >= data.maxFlightDistance) then
            if hitWall and data.haemolacria then
                spawnSplitChildren(effect, data, owner)
            end
            if not data.synergyTriggered
            and (data.synergy == "brimstone"
            or data.synergy == "brimstone_soy"
            or data.synergy == "brimstone_techx"
            or data.synergy == "technology") then
                data.synergyTriggered = true
                spawnSynergyOrb(owner, source, data.launchOrigin,
                    data.initialFlightDirection, data.synergy, data.tearFlags,
                    data.sourceColor)
            end
            if data.returnsToOwner then
                data.state = "RETURN"
                data.returnCurve = data.myReflection
                    and (data.pairIndex < 0 and -1 or 1) or 0
                data.stateFrame = 0
                data.hitSeeds = {}
                data.flightSpeed = math.max(0.0, data.flightSpeed * 0.35)
            else
                removeSwordAttachments(data)
                data.state = "STUCK"
                data.stateFrame = 0
                effect.Velocity = Vector.Zero
                sprite.PlaybackSpeed = 1.0
                play(sprite, "Stuck")
            end
        end
    elseif data.state == "RETURN" then
        local toOwner = sourcePosition(source, owner) - effect.Position
        if toOwner:LengthSquared() <= 18.0 ^ 2
        or data.stateFrame >= MAX_RETURN_TICKS then
            removeSwordAttachments(data)
            releaseKnifePairSlot(owner, data)
            effect:Remove()
            return
        end

        local returnDirection = validDirection(toOwner, owner)
        if data.myReflection and data.returnCurve ~= 0 then
            local curve = math.sin(math.min(1.0,
                data.stateFrame / MAX_RETURN_TICKS) * math.pi) * 14.0
            returnDirection = returnDirection:Rotated(data.returnCurve * curve)
        end
        data.direction = returnDirection
        data.flightSpeed = math.min(KNIFE_RETURN_SPEED,
            (data.flightSpeed or 0.0) + KNIFE_RETURN_ACCELERATION)
        effect.Velocity = data.direction * data.flightSpeed
        if destroyEnemyProjectiles(effect, data) then return end
        sprite.PlaybackSpeed = 1.0
        sprite.Rotation = data.direction:GetAngleDegrees() - 90.0
        play(sprite, "Idle")
        syncTechXAura(effect, data)
        syncTechnologyTether(effect, data, owner)

        if data.stateFrame % AFTERIMAGE_INTERVAL == 0 then
            spawnAfterimage(effect, data)
        end

        local previousPosition = data.previousPosition
            or (effect.Position - effect.Velocity)
        local candidates = Isaac.FindInRadius(effect.Position,
            (data.hitRadius or HIT_RADIUS) + KNIFE_RETURN_SPEED + 40.0,
            EntityPartition.ENEMY)
        table.sort(candidates, function(left, right)
            return left.InitSeed < right.InitSeed
        end)
        for _, enemy in ipairs(candidates) do
            if enemy:IsActiveEnemy(false) and enemy:IsVulnerableEnemy()
            and not enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and distanceSquaredToSegment(enemy.Position, previousPosition,
                effect.Position) <= ((data.hitRadius or HIT_RADIUS)
                    + enemy.Size) ^ 2 then
                strikeEnemy(effect, data, owner, enemy)
            end
        end
        data.previousPosition = effect.Position
    elseif data.state == "STUCK" then
        effect.Velocity = Vector.Zero
        play(sprite, "Stuck")
        local alpha = math.max(0.0, 1.0 - data.stateFrame / STUCK_TICKS)
        effect.Color = Color(1.0, 1.0, 1.0, alpha, 0.0, 0.0, 0.0)
        if data.stateFrame >= STUCK_TICKS then effect:Remove() end
    end
end

function Arclight.Register(mod, itemId, effectVariant)
    Arclight.ItemId = itemId
    Arclight.EffectVariant = effectVariant

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
        updateChargePair(player, effectVariant)
        ensureLudovicoSwords(player, effectVariant)
        if player:HasCollectible(CollectibleType.COLLECTIBLE_ANTI_GRAVITY) then
            if player:GetData().ArclightStoredSwords
            and not sourceIsFiring(player, player) then
                releaseStoredSwords(player, player)
            end
            local familiars = Isaac.FindByType(EntityType.ENTITY_FAMILIAR)
            table.sort(familiars, function(left, right)
                return left.InitSeed < right.InitSeed
            end)
            for _, entity in ipairs(familiars) do
                if isSwordCopyFamiliar(entity) then
                    local familiar = entity:ToFamiliar()
                    if GetPtrHash(familiar.Player) == GetPtrHash(player)
                    and familiar:GetData().ArclightStoredSwords
                    and not sourceIsFiring(familiar, player) then
                        releaseStoredSwords(player, familiar)
                    end
                end
            end
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
        if spawningSynergyLaser or spawningArclightShard
        or tear:GetData().ArclightShard then return end
        local player, source = resolveProjectileContext(tear)
        if not player or not player:HasCollectible(itemId) then return end
        local synergy = getSynergy(player)
        if synergy then return end
        if tear:HasTearFlags(TearFlags.TEAR_LUDOVICO) then
            spawnLudovicoSwords(player, source, tear, effectVariant)
            return
        end
        local fireVelocity = tear.Velocity
        if tear.WaitFrames > 0
        and tear.ContinueVelocity:LengthSquared() > 0.001 then
            fireVelocity = tear.ContinueVelocity
        end
        spawnRolledSword(player, source, effectVariant, fireVelocity, nil,
            tear.TearFlags, tear.Color)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_BRIMSTONE, function(_, laser)
        if spawningSynergyLaser or laser:GetData().ArclightSynergyLaser then
            return
        end
        local player, source = resolveProjectileContext(laser)
        if not player or not player:HasCollectible(itemId)
        or (getSynergy(player) ~= "brimstone"
            and getSynergy(player) ~= "brimstone_soy") then return end
        launchPair(player, source, effectVariant,
            Vector.FromAngle(laser.AngleDegrees), getSynergy(player),
            laser.TearFlags, laser.Color)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TECH_X_LASER, function(_, laser)
        if spawningSynergyLaser
        or ProjectileSpawnContext.IsActive("revelation_ring")
        or laser:GetData().ArclightSynergyLaser then
            return
        end
        local player, source = resolveProjectileContext(laser)
        if not player or not player:HasCollectible(itemId)
        or (getSynergy(player) ~= "techx"
            and getSynergy(player) ~= "brimstone_techx") then return end
        local direction = laser.Velocity
        if direction:LengthSquared() <= 0.001 then
            direction = Vector.FromAngle(laser.AngleDegrees)
        end
        launchPair(player, source, effectVariant, direction,
            getSynergy(player), laser.TearFlags, laser.Color)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TECH_LASER, function(_, laser)
        if spawningSynergyLaser or laser:GetData().ArclightSynergyLaser then
            return
        end
        local player, source = resolveProjectileContext(laser)
        if not player or not player:HasCollectible(itemId)
        or getSynergy(player) ~= "technology" then return end
        spawnRolledSword(player, source, effectVariant,
            Vector.FromAngle(laser.AngleDegrees), "technology",
            laser.TearFlags, laser.Color)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, knife)
        updateSpiritSwordKnife(knife, effectVariant)
    end)

    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG,
        function(_, entity, _, _, damageSource)
            local npc = entity:ToNPC()
            if not npc or not damageSource then return end
            handleCSectionContactDamage(npc, damageSource, effectVariant)
            local player = resolveDamageOwner(damageSource.Entity)
            if not player or not player:HasCollectible(itemId)
            or not player:HasCollectible(
                CollectibleType.COLLECTIBLE_SPIRIT_SWORD) then
                return
            end
            npc:GetData().ArclightSpiritSwordKiller = EntityPtr(player)
        end)

    mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, function(_, npc)
        local pointer = npc:GetData().ArclightSpiritSwordKiller
        local entity = pointer and pointer.Ref
        local player = entity and entity:ToPlayer()
        if not player or not player:Exists()
        or not player:HasCollectible(itemId)
        or not player:HasCollectible(
            CollectibleType.COLLECTIBLE_SPIRIT_SWORD) then
            return
        end
        player:SetMinDamageCooldown(SPIRIT_SWORD_SHIELD_TICKS)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, knife)
        local player, source = resolveProjectileContext(knife)
        if not player or not player:HasCollectible(itemId)
        or getSynergy(player) ~= "moms_knife" then return end

        local knifeData = knife:GetData()
        local isFlying = knife:IsFlying()
        if isFlying and not knifeData.ArclightWasFlying then
            local direction = knife.Velocity
            if direction:LengthSquared() <= 0.001 then
                direction = Vector.FromAngle(knife.Rotation)
            end
            launchPair(player, source, effectVariant, direction,
                "moms_knife", knife.TearFlags, knife.Color)
        end
        knifeData.ArclightWasFlying = isFlying
    end)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
        local data = tear:GetData()
        if not data.ArclightShard then return end
        data.ArclightShardLife = data.ArclightShardLife - 1
        if data.ArclightShardLife <= 0 then tear:Die() end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_DEATH, function(_, tear)
        if not tear:GetData().ArclightShard then return end
        local poof = Isaac.Spawn(EntityType.ENTITY_EFFECT,
            EffectVariant.TEAR_POOF_A, 0, tear.Position, Vector.Zero,
            tear):ToEffect()
        local sprite = poof:GetSprite()
        sprite:ReplaceSpritesheet(0, SHARD_SPLAT_SHEET)
        sprite:LoadGraphics()
    end)

    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, function(_, laser)
        updateSoyBeam(laser)
        updateMovingRingHoming(laser)
    end)
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, effect)
        updateSword(effect)
    end, effectVariant)

    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, effect)
        updateSynergyOrb(effect)
    end, EffectVariant.BRIMSTONE_SWIRL)

    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, effect)
        updateSynergyOrb(effect)
    end, EffectVariant.TECH_DOT)

    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            clearChargeSwords(player, true)
            player:GetData().ArclightKnifePairActive = nil
            player:GetData().ArclightStoredSwords = nil
            player:GetData().ArclightLudovicoSwords = nil
        end
        local familiars = Isaac.FindByType(EntityType.ENTITY_FAMILIAR)
        table.sort(familiars, function(left, right)
            return left.InitSeed < right.InitSeed
        end)
        for _, entity in ipairs(familiars) do
            if isSwordCopyFamiliar(entity) then
                clearChargeSwords(entity, true)
                entity:GetData().ArclightKnifePairActive = nil
                entity:GetData().ArclightStoredSwords = nil
                entity:GetData().ArclightLudovicoSwords = nil
            end
        end
    end)
end

return Arclight







