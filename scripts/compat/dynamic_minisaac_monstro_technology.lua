local WeaponSynergies = {}

local MONSTROS_LUNG = CollectibleType.COLLECTIBLE_MONSTROS_LUNG
local BRIMSTONE = CollectibleType.COLLECTIBLE_BRIMSTONE
local TECHNOLOGY = CollectibleType.COLLECTIBLE_TECHNOLOGY
local TECH_X = CollectibleType.COLLECTIBLE_TECH_X
local BURST_LASERS = 6
local MIN_CHAINED_LASERS = 3
local MAX_CHAINED_LASERS = 4
local BURST_DISTANCE = 70
local BURST_SPREAD = 50
local TECH_X_RADIUS = 40
local DAMAGE_MULTIPLIER = 0.15
local BASE_CHARGE_DELAY = 4
local BURST_MEMBER_KEY = "AscentionDynamicMinisaacBurstMember"
local MAX_BURST_DIRECTIONS = 3

local function comboFor(player)
    if not player then return nil end

    -- These weapons own the projectile lifecycle. Brimstone/Technology/Tech X
    -- are modifiers for them and must not replace their attack outright.
    if player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_SPIRIT_SWORD)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS)
    then
        return nil
    end

    local hasMonstro = player:HasCollectible(MONSTROS_LUNG)
        and player:HasWeaponType(WeaponType.WEAPON_MONSTROS_LUNGS)
    local hasBrimstone = player:HasCollectible(BRIMSTONE)
    local hasTechnology = player:HasCollectible(TECHNOLOGY)
    local hasTechX = player:HasCollectible(TECH_X)

    if hasMonstro then
        if hasTechX then return "monstro_tech_x" end
        if hasBrimstone then return "monstro_brimstone" end
        if hasTechnology then return "monstro_technology" end
    end

    if hasBrimstone and hasTechX then
        return "brimstone_tech_x"
    end
    if hasBrimstone and hasTechnology then
        return "brimstone_technology"
    end
end

local function directionVector(familiar, fallback)
    local direction = familiar.ShootDirection
    if direction == Direction.LEFT then
        return Vector(-1, 0)
    elseif direction == Direction.RIGHT then
        return Vector(1, 0)
    elseif direction == Direction.UP then
        return Vector(0, -1)
    elseif direction == Direction.DOWN then
        return Vector(0, 1)
    end

    if fallback:LengthSquared() > 0 then
        return fallback:Normalized()
    end
    return Vector(0, 1)
end

local function chargeDelay(player, combo)
    local dynamic = DynamicMinisaacContinued
    local delay = BASE_CHARGE_DELAY
    if combo == "brimstone_tech_x" then
        delay = dynamic.TearDelayMult.TECH_X or 3
    elseif combo == "brimstone_technology" then
        delay = dynamic.TearDelayMult.BRIM or BASE_CHARGE_DELAY
    else
        delay = dynamic.TearDelayMult.MONSTRO or BASE_CHARGE_DELAY
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_CHOCOLATE_MILK) then
        delay = delay * (dynamic.TearDelayModif.CHOC or 2)
    end
    return math.max(1, delay)
end

local function randomBurstDirection(familiar, direction)
    local rng = familiar:GetDropRNG()
    local radius = rng:RandomFloat() * BURST_SPREAD
    local angle = rng:RandomFloat() * 360
    local endpoint = direction * BURST_DISTANCE
        + Vector.FromAngle(angle) * radius
    return endpoint:Normalized(), endpoint:Length(), rng
end

local function configureLaser(laser, familiar, damage, isBurst)
    laser.Parent = familiar
    laser.ParentOffset = Vector.Zero
    laser.CollisionDamage = damage
    laser.TearFlags = familiar.Player.TearFlags
    laser:GetData().AscentionDynamicMinisaacOwner = familiar
    if isBurst then laser:GetData()[BURST_MEMBER_KEY] = true end
end

local function fireTechnologyBurst(player, familiar, direction, damage, count)
    local origin = familiar.Position + direction * 10
    for _ = 1, count do
        local laserDirection, segmentDistance, rng
            = randomBurstDirection(familiar, direction)
        local laser = Isaac.Spawn(
            EntityType.ENTITY_LASER,
            LaserVariant.THIN_RED,
            0,
            origin,
            Vector.Zero,
            player
        ):ToLaser()
        laser.Timeout = 1
        laser.PositionOffset = Vector.Zero
        laser.DisableFollowParent = true
        laser.AngleDegrees = laserDirection:GetAngleDegrees()
        laser.MaxDistance = segmentDistance
        laser:SetNumChainedLasers(
            MIN_CHAINED_LASERS
                + rng:RandomInt(MAX_CHAINED_LASERS - MIN_CHAINED_LASERS + 1)
        )
        configureLaser(laser, familiar, damage, true)
    end
end

local function fireBrimstoneBurst(player, familiar, direction, damage, count)
    for _ = 1, count do
        local laserDirection, distance = randomBurstDirection(familiar, direction)
        local laser = player:FireBrimstone(
            laserDirection,
            familiar,
            DAMAGE_MULTIPLIER
        )
        laser.Timeout = 5
        laser.MaxDistance = distance
        laser.AngleDegrees = laserDirection:GetAngleDegrees()
        configureLaser(laser, familiar, damage, true)
    end
end

local function fireTechXBurst(player, familiar, direction, damage, count)
    for _ = 1, count do
        local ringDirection = randomBurstDirection(familiar, direction)
        local laser = player:FireTechXLaser(
            familiar.Position,
            ringDirection * 10,
            TECH_X_RADIUS,
            familiar,
            DAMAGE_MULTIPLIER
        )
        configureLaser(laser, familiar, damage, true)
    end
end

local function fireBrimstoneTechnology(player, familiar, direction, damage)
    local laser = player:FireBrimstone(
        direction,
        familiar,
        DAMAGE_MULTIPLIER
    )
    laser.Timeout = 5
    laser.MaxDistance = 150
    configureLaser(laser, familiar, damage)
end

local function fireBrimstoneTechX(player, familiar, direction, damage)
    local laser = player:FireTechXLaser(
        familiar.Position,
        direction * 10,
        TECH_X_RADIUS,
        familiar,
        DAMAGE_MULTIPLIER
    )
    configureLaser(laser, familiar, damage)
end

local function burstSettings(player, familiar, direction, weaponType)
    local params = player:GetMultiShotParams(weaponType)
    local eyes = math.max(1, params:GetNumEyesActive())
    local lanesPerEye = math.max(1, params:GetNumLanesPerEye())
    local count = BURST_LASERS
        + math.floor(2.4 * (lanesPerEye - 1))
    local directions = {}
    local multiEyeAngle = params:GetMultiEyeAngle()

    for eye = 0, eyes - 1 do
        local angle = eyes <= 1 and 0
            or (-multiEyeAngle + multiEyeAngle * 2 * (eye / (eyes - 1)))
        table.insert(directions, direction:Rotated(angle))
    end

    if params:IsShootingBackwards() then
        table.insert(directions, direction:Rotated(180))
    end
    if params:IsShootingSideways() then
        table.insert(directions, direction:Rotated(90))
        table.insert(directions, direction:Rotated(-90))
    end

    local rng = familiar:GetDropRNG()
    local randomDirections = math.min(
        params:GetNumRandomDirTears(),
        MAX_BURST_DIRECTIONS
    )
    for _ = 1, randomDirections do
        table.insert(directions, Vector.FromAngle(rng:RandomFloat() * 360))
    end
    return count, directions
end
local function executeCombo(combo, player, familiar, direction)
    local damage = player.Damage * DAMAGE_MULTIPLIER
    if combo == "monstro_technology"
        or combo == "monstro_brimstone"
        or combo == "monstro_tech_x"
    then
        local weaponType = combo == "monstro_tech_x"
            and WeaponType.WEAPON_TECH_X
            or (combo == "monstro_brimstone"
                and WeaponType.WEAPON_BRIMSTONE
                or WeaponType.WEAPON_LASER)
        local count, directions = burstSettings(
            player,
            familiar,
            direction,
            weaponType
        )
        for _, burstDirection in ipairs(directions) do
            if combo == "monstro_technology" then
                fireTechnologyBurst(
                    player, familiar, burstDirection, damage, count
                )
            elseif combo == "monstro_brimstone" then
                fireBrimstoneBurst(
                    player, familiar, burstDirection, damage, count
                )
            else
                fireTechXBurst(
                    player, familiar, burstDirection, damage, count
                )
            end
        end
    elseif combo == "brimstone_technology" then
        fireBrimstoneTechnology(player, familiar, direction, damage)
    elseif combo == "brimstone_tech_x" then
        fireBrimstoneTechX(player, familiar, direction, damage)
    end
end

local function overrideDynamicWeaponLogic(_, player)
    if comboFor(player) then
        return true
    end
end

local function handleMinisaacTear(_, tear)
    local familiar = tear.SpawnerEntity and tear.SpawnerEntity:ToFamiliar()
    if not familiar or familiar.Variant ~= FamiliarVariant.MINISAAC then
        return
    end

    local player = familiar.Player
    local combo = comboFor(player)
    if not combo then return end

    local direction = directionVector(familiar, tear.Velocity)
    tear.Visible = false
    tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    tear.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    DynamicMinisaacContinued:RemoveDefaultTear(tear)

    familiar.Keys = (familiar.Keys or 0) + 1
    if familiar.Keys < chargeDelay(player, combo) then
        return
    end

    familiar.Keys = 0
    executeCombo(combo, player, familiar, direction)
end

function WeaponSynergies.Register(mod)
    local dynamic = DynamicMinisaacContinued
    local callbacks = dynamic and dynamic.CustomCallbacks
    local overrideCallback = callbacks
        and callbacks.NEBUKA_PRE_CHECK_LOGICOVERRIDE
    if not overrideCallback then
        Isaac.DebugString(
            "[Ascention] Dynamic Minisaac weapon synergy support skipped: API unavailable"
        )
        return
    end

    mod:AddCallback(overrideCallback, overrideDynamicWeaponLogic)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, handleMinisaacTear)
end

return WeaponSynergies

