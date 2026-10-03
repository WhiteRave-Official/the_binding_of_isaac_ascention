local SpiritSword = {}

local SWINGS_PER_SPIN = 4
local DAMAGE_MULTIPLIER = 0.15
local ATTACK_ANIMATION = "AttackRight"
local SPIN_ANIMATION = "SpinRight"
local OWNER_KEY = "AscentionDynamicMinisaacOwner"
local EXPANDED_KEY = "AscentionDynamicMinisaacMultishotExpanded"
local SWING_COUNT_KEY = "AscentionDynamicMinisaacSpiritSwingCount"
local PROCESSED_KEY = "AscentionDynamicMinisaacSpiritProcessed"
local SPIN_KEY = "AscentionDynamicMinisaacSpiritSpin"
local HITBOX_KEY = "AscentionDynamicMinisaacSpiritHitbox"
local VISUAL_KEY = "AscentionDynamicMinisaacSpiritVisual"
local OFFSET_KEY = "AscentionDynamicMinisaacSpiritOffset"
local ANGLE_KEY = "AscentionDynamicMinisaacSpiritAngle"
local ANIMATION_KEY = "AscentionDynamicMinisaacSpiritAnimation"
local TARGET_KEY = "AscentionDynamicMinisaacSpiritTarget"
local TARGET_SEARCH_FRAME_KEY = "AscentionDynamicMinisaacSpiritTargetFrame"
local SKIN_RESTORED_KEY = "AscentionDynamicMinisaacSpiritSkinRestored"
local TARGET_SEARCH_INTERVAL = 6
local MELEE_DISTANCE = 44
local APPROACH_SPEED = 4.5
local MAX_MULTISHOT = 16

local function asMiniIsaac(entity)
    if entity
        and entity:Exists()
        and entity.Type == EntityType.ENTITY_FAMILIAR
        and entity.Variant == FamiliarVariant.MINISAAC
    then
        return entity:ToFamiliar()
    end
end

local function hasSpiritSword(player)
    return player
        and player:HasCollectible(CollectibleType.COLLECTIBLE_SPIRIT_SWORD)
        and player:HasWeaponType(WeaponType.WEAPON_SPIRIT_SWORD)
end

local function directionVector(familiar, fallback)
    if familiar.ShootDirection == Direction.LEFT then
        return Vector(-1, 0)
    elseif familiar.ShootDirection == Direction.RIGHT then
        return Vector(1, 0)
    elseif familiar.ShootDirection == Direction.UP then
        return Vector(0, -1)
    elseif familiar.ShootDirection == Direction.DOWN then
        return Vector(0, 1)
    elseif fallback and fallback:LengthSquared() > 0 then
        return fallback:Normalized()
    end
    return Vector(0, 1)
end

local function swordVariant(player)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY_2)
    then
        return KnifeVariant.TECH_SWORD
    end
    return KnifeVariant.SPIRIT_SWORD
end

local function swordAnimationPath(variant)
    if variant == KnifeVariant.TECH_SWORD then
        return "gfx/008.011_Tech Sword.anm2"
    end
    return "gfx/008.010_Spirit Sword.anm2"
end

local function configureAnimation(entity, animation, direction)
    local sprite = entity:GetSprite()
    sprite:Play(animation, true)
    sprite.Rotation = direction:GetAngleDegrees()
end

local function spawnSwordPair(familiar, position, direction, spinAttack)
    local player = familiar.Player
    local variant = swordVariant(player)
    local animation = spinAttack and SPIN_ANIMATION or ATTACK_ANIMATION
    local offset = position - familiar.Position

    local hitbox = Isaac.Spawn(
        EntityType.ENTITY_KNIFE,
        variant,
        KnifeSubType.CLUB_HITBOX,
        position,
        Vector.Zero,
        familiar
    ):ToKnife()

    local data = hitbox:GetData()
    data.DisappearMinisaac = true
    data[OWNER_KEY] = familiar
    data[EXPANDED_KEY] = true
    data[PROCESSED_KEY] = true
    data[SPIN_KEY] = spinAttack
    data[HITBOX_KEY] = true
    data[OFFSET_KEY] = offset
    data[ANGLE_KEY] = direction:GetAngleDegrees()

    hitbox.Parent = familiar
    hitbox.SpawnerEntity = familiar
    hitbox.Visible = false
    hitbox:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    hitbox.Scale = 0.75
    hitbox.SpriteScale = Vector(0.75, 0.75)
    hitbox.Rotation = direction:GetAngleDegrees()
    hitbox.CollisionDamage = player.Damage * DAMAGE_MULTIPLIER

    local params = player:GetTearHitParams(
        WeaponType.WEAPON_SPIRIT_SWORD,
        1,
        1,
        player
    )
    hitbox.TearFlags = params.TearFlags
    hitbox:SetIsSwinging(true)
    if spinAttack then hitbox:SetIsSpinAttack(true) end
    hitbox:GetSprite():Play(animation, true)

    local visual = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        0,
        0,
        position,
        Vector.Zero,
        familiar
    ):ToEffect()
    local visualData = visual:GetData()
    visualData[VISUAL_KEY] = true
    visualData[OWNER_KEY] = familiar
    visualData[OFFSET_KEY] = offset
    visualData[ANGLE_KEY] = direction:GetAngleDegrees()
    visualData[ANIMATION_KEY] = animation

    visual.Parent = familiar
    visual:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    visual.DepthOffset = 20
    visual.SpriteScale = Vector(0.75, 0.75)
    visual:GetSprite():Load(swordAnimationPath(variant), true)
    configureAnimation(visual, animation, direction)

    return hitbox, visual
end

local function spawnSwordFormation(familiar, direction, spinAttack)
    local player = familiar.Player
    local params = player:GetMultiShotParams(WeaponType.WEAPON_TEARS)
    local count = math.max(1, math.min(MAX_MULTISHOT, params:GetNumTears()))
    for index = 0, count - 1 do
        local posVel = player:GetMultiShotPositionVelocity(
            index,
            WeaponType.WEAPON_TEARS,
            direction,
            1,
            params
        )
        local shotDirection = posVel.Velocity
        if shotDirection:LengthSquared() == 0 then
            shotDirection = direction
        else
            shotDirection = shotDirection:Normalized()
        end
        spawnSwordPair(
            familiar,
            familiar.Position + posVel.Position * 4,
            shotDirection,
            spinAttack
        )
    end

    if spinAttack then
        SFXManager():Play(
            SoundEffect.SOUND_SWORD_SPIN,
            0.65,
            0,
            false,
            1.1
        )
    else
        SFXManager():Play(
            SoundEffect.SOUND_SHELLGAME,
            0.55,
            0,
            false,
            1.2
        )
    end
end

local function validTarget(entity)
    return entity
        and entity:Exists()
        and entity:IsActiveEnemy(false)
        and entity:IsVulnerableEnemy()
        and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

local function findNearestTarget(familiar)
    local nearest
    local nearestDistance = math.huge
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if validTarget(entity) then
            local distance = familiar.Position:DistanceSquared(entity.Position)
            if distance < nearestDistance
                or (distance == nearestDistance
                    and nearest
                    and entity.InitSeed < nearest.InitSeed)
            then
                nearest = entity
                nearestDistance = distance
            end
        end
    end
    return nearest
end

local function updateMeleeMovement(familiar)
    local data = familiar:GetData()
    local frame = Game():GetFrameCount()
    local target = data[TARGET_KEY]
    if frame >= (data[TARGET_SEARCH_FRAME_KEY] or 0)
        or not validTarget(target)
    then
        target = findNearestTarget(familiar)
        data[TARGET_KEY] = target
        data[TARGET_SEARCH_FRAME_KEY] = frame + TARGET_SEARCH_INTERVAL
    end

    if not validTarget(target) then return end

    local delta = target.Position - familiar.Position
    local distance = delta:Length()
    if distance > MELEE_DISTANCE then
        local approach = delta:Resized(APPROACH_SPEED)
        familiar.Velocity = familiar.Velocity * 0.2 + approach * 0.8
    else
        -- Cancel the regular shooting familiar's retreat once melee range is
        -- reached without pinning it to a fixed point around the target.
        familiar.Velocity = familiar.Velocity * 0.35
    end
end

local function overrideDynamicSpiritSword(_, player)
    if hasSpiritSword(player) then
        return true
    end
end

local function handleTechnicalTear(_, tear)
    local familiar = asMiniIsaac(tear.SpawnerEntity)
    if not familiar or not hasSpiritSword(familiar.Player) then return end

    tear.Visible = false
    tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    tear.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    DynamicMinisaacContinued:RemoveDefaultTear(tear)

    local familiarData = familiar:GetData()
    local count = (familiarData[SWING_COUNT_KEY] or 0) + 1
    local spinAttack = count >= SWINGS_PER_SPIN
    familiarData[SWING_COUNT_KEY] = spinAttack and 0 or count

    spawnSwordFormation(
        familiar,
        directionVector(familiar, tear.Velocity),
        spinAttack
    )
end

local function updateSwordHitbox(_, knife)
    local data = knife:GetData()
    if not data[HITBOX_KEY] then return end

    local familiar = asMiniIsaac(data[OWNER_KEY])
    if not familiar or not familiar.Player then
        knife:Remove()
        return
    end

    knife.Position = familiar.Position + (data[OFFSET_KEY] or Vector.Zero)
    knife.Rotation = data[ANGLE_KEY] or knife.Rotation
    knife.Scale = 0.75
    knife.SpriteScale = Vector(0.75, 0.75)
    knife.CollisionDamage = familiar.Player.Damage * DAMAGE_MULTIPLIER
    knife.Visible = false
    knife:SetIsSwinging(true)
    if data[SPIN_KEY] then knife:SetIsSpinAttack(true) end
end

local function updateSwordVisual(_, effect)
    local data = effect:GetData()
    if not data[VISUAL_KEY] then return end

    local familiar = asMiniIsaac(data[OWNER_KEY])
    if not familiar then
        effect:Remove()
        return
    end

    effect.Position = familiar.Position + (data[OFFSET_KEY] or Vector.Zero)
    effect:GetSprite().Rotation = data[ANGLE_KEY] or 0
    if effect:GetSprite():IsFinished(data[ANIMATION_KEY]) then
        effect:Remove()
    end
end

local function restoreFamiliarSkin(_, familiar)
    if familiar.Variant ~= FamiliarVariant.MINISAAC
        or not hasSpiritSword(familiar.Player)
    then return end

    local data = familiar:GetData()
    local wasConvertedByDynamic = familiar.SubType == 99
        or data.MasterSkinColor ~= nil
    if familiar.SubType == 99 then
        if data.MasterSkinColor ~= nil then
            familiar.SubType = 1 + data.MasterSkinColor
        else
            familiar.SubType = 1
        end
    end

    if wasConvertedByDynamic and not data[SKIN_RESTORED_KEY] then
        local sprite = familiar:GetSprite()
        sprite:Load("gfx/003.228_minisaac.anm2", true)
        if sprite:HasAnimation("FloatDown") then
            sprite:Play("FloatDown", true)
        end
        data[SKIN_RESTORED_KEY] = true
    end

    updateMeleeMovement(familiar)
end

function SpiritSword.Register(mod)
    local dynamic = DynamicMinisaacContinued
    local callbacks = dynamic and dynamic.CustomCallbacks
    local overrideCallback = callbacks
        and callbacks.NEBUKA_PRE_CHECK_LOGICOVERRIDE
    if not overrideCallback then
        Isaac.DebugString(
            "[Ascention] Dynamic Minisaac Spirit Sword support skipped: API unavailable"
        )
        return
    end

    mod:AddCallback(overrideCallback, overrideDynamicSpiritSword)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, handleTechnicalTear)
    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, updateSwordHitbox)
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, updateSwordVisual)
    mod:AddCallback(
        ModCallbacks.MC_FAMILIAR_UPDATE,
        restoreFamiliarSkin,
        FamiliarVariant.MINISAAC
    )
end

return SpiritSword
