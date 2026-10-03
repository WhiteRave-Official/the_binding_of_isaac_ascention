local RevelationRework = {}
local ProjectileSpawnContext = include("scripts.projectile_spawn_context")

local REVELATION = CollectibleType.COLLECTIBLE_REVELATION
local LIGHT_RING_ANM2 = "gfx/007.008_light ring.anm2"
local LIGHT_RING_VARIANT = LaserVariant.LIGHT_RING
local REVELATION_SOUND = SoundEffect.SOUND_ANGEL_BEAM
local INTERNAL_SPAWN_KIND = "revelation_ring"
local DATA_KEY = "AscentionRevelationRing"
local CHECKED_KEY = "AscentionRevelationRingChecked"
local DAMAGE_MULTIPLIER = 0.5
local BASE_RADIUS = 22.0
local MIN_SCALE = 0.4
local SHOT_SPEED_PENALTY = 0.15
local REVELATION_TEAR_FLAGS = TearFlags.TEAR_PIERCING | TearFlags.TEAR_SPECTRAL

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

local function getRingScale(tear)
    return math.max(MIN_SCALE, tear.Scale or 1.0)
end

local function configureRing(laser, tear, owner)
    local radius = BASE_RADIUS * getRingScale(tear)
    local data = laser:GetData()

    data.AscentionRevelationRing = true
    data.AscentionRevelationSource = tear
    laser.Variant = LIGHT_RING_VARIANT
    laser.Parent = tear
    laser:SetDisableFollowParent(false)
    laser.Position = tear.Position
    laser.PositionOffset = tear.PositionOffset
    laser.Velocity = tear.Velocity
    laser.Radius = radius
    laser.CollisionDamage = owner.Damage * DAMAGE_MULTIPLIER
    laser:AddTearFlags(tear.TearFlags | TearFlags.TEAR_SPECTRAL)
    laser.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    laser.Color = Color.Default
    laser:SetInitSound(REVELATION_SOUND)
    laser:SetTimeout(2)

    local sprite = laser:GetSprite()
    sprite:Load(LIGHT_RING_ANM2, true)
    sprite:Play("LargeRedLaser", true)
    sprite.Color = Color.Default
    laser:RecalculateSamplesNextUpdate()
end

local function createRing(tear, owner)
    local radius = BASE_RADIUS * getRingScale(tear)
    local laser = ProjectileSpawnContext.Run(INTERNAL_SPAWN_KIND, function()
        return owner:FireTechXLaser(
            tear.Position,
            tear.Velocity,
            radius,
            tear,
            DAMAGE_MULTIPLIER
        )
    end)

    if not laser then
        return nil
    end

    configureRing(laser, tear, owner)
    return laser
end

local function markTear(tear)
    local data = tear:GetData()
    if data[CHECKED_KEY] then
        return data[DATA_KEY]
    end

    local owner = resolvePlayer(tear)
    if not owner then
        -- Custom tears can receive their parent shortly after spawning.
        if tear.FrameCount > 2 then
            data[CHECKED_KEY] = true
        end
        return false
    end

    data[CHECKED_KEY] = true
    if not owner:HasCollectible(REVELATION) then
        return false
    end

    data[DATA_KEY] = createRing(tear, owner)
    data.AscentionRevelationOwner = owner
    return data[DATA_KEY] ~= nil
end

local function updateRing(tear, laser)
    if not laser or not laser:Exists() then
        return
    end

    local radius = BASE_RADIUS * getRingScale(tear)
    local radiusChanged = math.abs(laser.Radius - radius) > 0.01

    laser.Parent = tear
    laser:SetDisableFollowParent(false)
    laser.Position = tear.Position
    laser.PositionOffset = tear.PositionOffset
    laser.Velocity = tear.Velocity
    laser.Radius = radius
    laser:AddTearFlags(TearFlags.TEAR_SPECTRAL)
    laser.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    laser:SetTimeout(2)

    if radiusChanged then
        laser:RecalculateSamplesNextUpdate()
    end
end

local function evaluateCache(_, player, cacheFlag)
    if not player:HasCollectible(REVELATION) then
        return
    end

    if cacheFlag == CacheFlag.CACHE_SHOTSPEED then
        player.ShotSpeed = player.ShotSpeed - SHOT_SPEED_PENALTY
    elseif cacheFlag == CacheFlag.CACHE_TEARFLAG then
        player.TearFlags = player.TearFlags | REVELATION_TEAR_FLAGS
    end
end

local function onPlayerUpdate(_, player)
    if player:HasCollectible(REVELATION) and player:GetRevelationCharge() ~= 0 then
        player:SetRevelationCharge(0)
    end
end

local function onFireTear(_, tear)
    markTear(tear)
end

local function onTearUpdate(_, tear)
    if not markTear(tear) then
        return
    end

    updateRing(tear, tear:GetData()[DATA_KEY])
end

local function onEntityRemove(_, entity)
    local tear = entity:ToTear()
    if not tear then
        return
    end

    local laser = tear:GetData()[DATA_KEY]
    if laser and laser:Exists() then
        laser:Remove()
    end
end

function RevelationRework.Register(mod)
    mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, evaluateCache)
    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, onPlayerUpdate)
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, onFireTear)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, onTearUpdate)
    mod:AddCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, onEntityRemove)
end

return RevelationRework
