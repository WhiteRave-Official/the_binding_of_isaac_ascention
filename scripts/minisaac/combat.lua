local Formation = include("scripts.minisaac.formation")
local Router = include("scripts.minisaac.incubus_router")
local Combat = {}

local DAMAGE_MULTIPLIER = 0.15
local TEAR_SCALE = 0.6
local LASER_SCALE = 0.65
local TECH_X_RADIUS = 26
local SWORD_APPROACH_SPEED = 6.0
local SWORD_KEY = "AscentionMiniIsaacSword"
local SWORD_VISUAL_KEY = "AscentionMiniIsaacSwordVisual"
local SWORD_SWING_COUNT_KEY = "AscentionMiniIsaacSwordSwingCount"
local SWORD_TARGET_KEY = "AscentionMiniIsaacSwordTarget"
local SWORD_TARGET_FRAME_KEY = "AscentionMiniIsaacSwordTargetFrame"
local SPLIT_KEY = "AscentionMiniIsaacSplit"
local OWNER_KEY = "AscentionMiniIsaacOwner"
local PROCESSED_KEY = "AscentionMiniIsaacProcessed"
local emitting = false
local debugCounts = {}
local weaponType

local function validSwordTarget(entity)
    return entity and entity:Exists() and entity:IsActiveEnemy(false)
        and entity:IsVulnerableEnemy()
        and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

local function updateSwordMovement(_, familiar)
    if type(DynamicMinisaacContinued) == "table" then return end
    local player = familiar.Player
    if not player or weaponType(player) ~= WeaponType.WEAPON_SPIRIT_SWORD then return end

    local data = familiar:GetData()
    local frame = Game():GetFrameCount()
    local target = data[SWORD_TARGET_KEY]
    if frame >= (data[SWORD_TARGET_FRAME_KEY] or 0) or not validSwordTarget(target) then
        local bestDistance = math.huge
        target = nil
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if validSwordTarget(entity) then
                local distance = familiar.Position:DistanceSquared(entity.Position)
                if distance < bestDistance then
                    target = entity
                    bestDistance = distance
                end
            end
        end
        data[SWORD_TARGET_KEY] = target
        data[SWORD_TARGET_FRAME_KEY] = frame + 6
    end
    if not validSwordTarget(target) then return end

    local delta = target.Position - familiar.Position
    if delta:LengthSquared() > 44 * 44 then
        familiar.Velocity = familiar.Velocity * 0.2 + delta:Resized(SWORD_APPROACH_SPEED) * 0.8
    else
        familiar.Velocity = familiar.Velocity * 0.35
    end
end

local function asMiniIsaac(entity)
    if entity and entity:Exists()
        and entity.Type == EntityType.ENTITY_FAMILIAR
        and entity.Variant == FamiliarVariant.MINISAAC
    then
        return entity:ToFamiliar()
    end
end

weaponType = function(player)
    if player:HasWeaponType(WeaponType.WEAPON_SPIRIT_SWORD) then
        return WeaponType.WEAPON_SPIRIT_SWORD
    elseif player:HasWeaponType(WeaponType.WEAPON_KNIFE) then
        return WeaponType.WEAPON_KNIFE
    elseif player:HasWeaponType(WeaponType.WEAPON_BOMBS) then
        return WeaponType.WEAPON_BOMBS
    elseif player:HasWeaponType(WeaponType.WEAPON_TECH_X) then
        return WeaponType.WEAPON_TECH_X
    elseif player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE) then
        return WeaponType.WEAPON_BRIMSTONE
    elseif player:HasWeaponType(WeaponType.WEAPON_LASER) then
        return WeaponType.WEAPON_LASER
    elseif player:HasWeaponType(WeaponType.WEAPON_MONSTROS_LUNGS) then
        return WeaponType.WEAPON_MONSTROS_LUNGS
    end
    return WeaponType.WEAPON_TEARS
end

local function scaleTear(tear, player)
    tear.CollisionDamage = player.Damage * DAMAGE_MULTIPLIER
    tear.Scale = tear.Scale * TEAR_SCALE
end

local function scaleLaser(laser, player, familiar)
    laser.CollisionDamage = player.Damage * DAMAGE_MULTIPLIER
    laser:SetScale(laser:GetScale() * LASER_SCALE)
    laser:ResetSpriteScale()
    laser.Parent = familiar
end

local function fireTear(player, familiar, position, velocity)
    local tear = player:FireTear(position, velocity, false, true, false, familiar, DAMAGE_MULTIPLIER)
    tear:GetData()[PROCESSED_KEY] = true
    tear:GetData()[OWNER_KEY] = EntityPtr(familiar)
    scaleTear(tear, player)
    return tear
end

local function fireBrimstone(player, familiar, position, velocity)
    local laser = player:FireBrimstone(velocity:Normalized(), familiar, DAMAGE_MULTIPLIER)
    laser.Position = position
    laser.MaxDistance = 150
    laser.Timeout = 5
    scaleLaser(laser, player, familiar)
end

local function fireTechnology(player, familiar, position, velocity)
    local laser = player:FireTechLaser(position, 0, velocity:Normalized(), false, true, familiar, DAMAGE_MULTIPLIER)
    laser.DisableFollowParent = true
    laser.AngleDegrees = velocity:GetAngleDegrees()
    laser.MaxDistance = 150
    laser.Timeout = 1
    scaleLaser(laser, player, familiar)
end

local function fireTechX(player, familiar, position, velocity)
    local laser = player:FireTechXLaser(position, velocity, TECH_X_RADIUS, familiar, DAMAGE_MULTIPLIER)
    laser.CollisionDamage = player.Damage * DAMAGE_MULTIPLIER
    laser.Parent = familiar
end

local function fireBomb(player, familiar, position, velocity)
    local bomb = player:FireBomb(position, velocity)
    bomb:GetData()[OWNER_KEY] = EntityPtr(familiar)
    bomb.ExplosionDamage = player.Damage * DAMAGE_MULTIPLIER
    bomb.RadiusMultiplier = 0.6
    bomb.SpriteScale = Vector(0.6, 0.6)
end

local function fireKnife(player, familiar, position, velocity)
    local data = familiar:GetData()
    local knife = data.AscentionMiniIsaacKnife
    knife = knife and knife.Ref and knife.Ref:ToKnife()
    if not knife or not knife:Exists() then
        knife = player:FireKnife(familiar)
        data.AscentionMiniIsaacKnife = EntityPtr(knife)
        knife.Parent = familiar
        knife.Scale = 0.6
        knife.SpriteScale = Vector(0.6, 0.6)
    end
    if knife:IsFlying() then return end
    knife.Position = position
    knife.Rotation = velocity:GetAngleDegrees()
    knife.CollisionDamage = player.Damage * DAMAGE_MULTIPLIER
    knife:Shoot(1, math.max(40, player.TearRange))
end

local function fireSword(player, familiar, position, velocity)
    local variant = (player:HasWeaponType(WeaponType.WEAPON_LASER)
        or player:HasWeaponType(WeaponType.WEAPON_TECH_X)) and 11 or 10
    local spinAttack = familiar:GetData()[SWORD_SWING_COUNT_KEY] == 0
    local animation = spinAttack and "SpinRight" or "AttackRight"
    local spritePath = variant == 11
        and "gfx/008.011_tech sword.anm2" or "gfx/008.010_spirit sword.anm2"

    local knife = Isaac.Spawn(
        EntityType.ENTITY_KNIFE, variant, KnifeSubType.CLUB_HITBOX,
        position, Vector.Zero, player
    ):ToKnife()
    knife.Parent = familiar
    knife.SpawnerEntity = player
    knife.Visible = false
    knife:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    knife.Rotation = velocity:GetAngleDegrees()
    knife.Scale = 0.6
    knife.SpriteScale = Vector(0.6, 0.6)
    knife.CollisionDamage = player.Damage * DAMAGE_MULTIPLIER
    local params = player:GetTearHitParams(WeaponType.WEAPON_SPIRIT_SWORD)
    knife.TearFlags = params.TearFlags
    knife:SetIsSwinging(true)
    if spinAttack then knife:SetIsSpinAttack(true) end
    local knifeSprite = knife:GetSprite()
    knifeSprite:Load(spritePath, true)
    knifeSprite:Play(animation, true)
    knifeSprite.PlaybackSpeed = 0

    local visual = Isaac.Spawn(EntityType.ENTITY_EFFECT, 0, 0,
        position, Vector.Zero, familiar):ToEffect()
    visual.Parent = familiar
    visual:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    visual.SpriteScale = Vector(0.6, 0.6)
    visual.DepthOffset = 20
    local visualSprite = visual:GetSprite()
    visualSprite:Load(spritePath, true)
    visualSprite:Play(animation, true)
    visualSprite.Rotation = velocity:GetAngleDegrees()

    local data = knife:GetData()
    data[SWORD_KEY] = true
    data.Owner = EntityPtr(familiar)
    data.Visual = EntityPtr(visual)
    local visualData = visual:GetData()
    visualData[SWORD_VISUAL_KEY] = true
    visualData.Owner = EntityPtr(familiar)
    visualData.Hitbox = EntityPtr(knife)
end

local function emit(player, familiar, kind, position, velocity)
    if kind == WeaponType.WEAPON_BRIMSTONE then
        fireBrimstone(player, familiar, position, velocity)
    elseif kind == WeaponType.WEAPON_TECH_X then
        fireTechX(player, familiar, position, velocity)
    elseif kind == WeaponType.WEAPON_LASER then
        fireTechnology(player, familiar, position, velocity)
    elseif kind == WeaponType.WEAPON_BOMBS then
        fireBomb(player, familiar, position, velocity)
    elseif kind == WeaponType.WEAPON_KNIFE then
        fireKnife(player, familiar, position, velocity)
    elseif kind == WeaponType.WEAPON_SPIRIT_SWORD then
        fireSword(player, familiar, position, velocity)
    else
        fireTear(player, familiar, position, velocity)
    end
end

local function processTear(_, tear)
    local familiar = asMiniIsaac(tear.SpawnerEntity)
    if not familiar or not familiar.Player then return end
    if type(DynamicMinisaacContinued) == "table" then return end
    if Router.IsManaging(familiar) then
        tear:Remove()
        return
    end
    local data = tear:GetData()
    if data[PROCESSED_KEY] or emitting then return end
    data[PROCESSED_KEY] = true

    local player = familiar.Player
    local velocity = tear.Velocity
    if velocity:LengthSquared() < 0.01 then
        scaleTear(tear, player)
        return
    end

    local familiarData = familiar:GetData()
    familiarData.AscentionMiniIsaacLastShotFrame = Game():GetFrameCount()
    familiarData.AscentionMiniIsaacLastShotVelocity = velocity
    familiar.FireCooldown = math.max(1, math.floor(player.MaxFireDelay + 1))

    local kind = weaponType(player)
    if kind == WeaponType.WEAPON_SPIRIT_SWORD then
        local count = (familiarData[SWORD_SWING_COUNT_KEY] or 0) + 1
        familiarData[SWORD_SWING_COUNT_KEY] = count >= 4 and 0 or count
    end
    local formationType = kind == WeaponType.WEAPON_MONSTROS_LUNGS
        and WeaponType.WEAPON_TEARS or kind
    local shots = Formation.Build(player, formationType, velocity)
    local chargedBurst = player:HasWeaponType(WeaponType.WEAPON_MONSTROS_LUNGS)
        and (kind == WeaponType.WEAPON_LASER
            or kind == WeaponType.WEAPON_BRIMSTONE
            or kind == WeaponType.WEAPON_TECH_X)
    local count = debugCounts[kind] or 0
    if count < 3 then
        debugCounts[kind] = count + 1
        local multiplier = kind == WeaponType.WEAPON_MONSTROS_LUNGS
            and 5 or (chargedBurst and 3 or 1)
        Isaac.DebugString("[AscentionMiniIsaac] fire weapon=" .. tostring(kind)
            .. " shots=" .. tostring(#shots * multiplier)
            .. " mini=" .. tostring(familiar.InitSeed))
    end
    -- The vanilla tear is the familiar's firing event, not an extra projectile.
    tear:Remove()
    emitting = true
    local ok, err = pcall(function()
        if kind == WeaponType.WEAPON_MONSTROS_LUNGS then
            local rng = familiar:GetDropRNG()
            for _, shot in ipairs(shots) do
                for _ = 1, 5 do
                    local spread = rng:RandomInt(31) - 15
                    emit(player, familiar, WeaponType.WEAPON_TEARS,
                        familiar.Position + shot.offset,
                        shot.velocity:Rotated(spread) * (0.7 + rng:RandomFloat() * 0.3))
                end
            end
        elseif chargedBurst then
            for _, shot in ipairs(shots) do
                for _, angle in ipairs({ -12, 0, 12 }) do
                    emit(player, familiar, kind,
                        familiar.Position + shot.offset,
                        shot.velocity:Rotated(angle))
                end
            end
        else
            for _, shot in ipairs(shots) do
                emit(player, familiar, kind, familiar.Position + shot.offset, shot.velocity)
            end
        end
    end)
    emitting = false
    if not ok then
        Isaac.DebugString("[AscentionMiniIsaac] fire failed: " .. tostring(err))
    elseif kind == WeaponType.WEAPON_SPIRIT_SWORD then
        local spinAttack = familiarData[SWORD_SWING_COUNT_KEY] == 0
        SFXManager():Play(spinAttack and SoundEffect.SOUND_SWORD_SPIN
            or SoundEffect.SOUND_SHELLGAME, 0.55, 0, false, 1.2)
    end
end

local function updateSwordHitbox(_, knife)
    local data = knife:GetData()
    if not data[SWORD_KEY] then return end
    local familiar = data.Owner and data.Owner.Ref
    local visual = data.Visual and data.Visual.Ref
    if not familiar or not familiar:Exists() or not visual or not visual:Exists() then
        knife:Remove()
        return
    end
    local visualSprite = visual:GetSprite()
    local knifeSprite = knife:GetSprite()
    knife.Position = visual.Position
    knifeSprite:Play(visualSprite:GetAnimation(), true)
    knifeSprite:SetFrame(visualSprite:GetFrame())
    knifeSprite.PlaybackSpeed = 0
    knifeSprite.Rotation = visualSprite.Rotation
end

local function updateSwordVisual(_, visual)
    local data = visual:GetData()
    if not data[SWORD_VISUAL_KEY] then return end
    local familiar = data.Owner and data.Owner.Ref
    if not familiar or not familiar:Exists() then
        visual:Remove()
        return
    end
    visual.Position = familiar.Position
    if visual:GetSprite():IsFinished() then
        visual:Remove()
    end
end

local function onSplitTear(_, child, source)
    local familiar = asMiniIsaac(source and source.SpawnerEntity)
    if not familiar and source then
        familiar = asMiniIsaac(source.Parent)
    end
    if not familiar and source then
        local stored = source:GetData()[OWNER_KEY]
        familiar = stored and asMiniIsaac(stored.Ref)
    end
    if not familiar or not familiar.Player then return end
    local data = child:GetData()
    if data[SPLIT_KEY] then return end
    data[SPLIT_KEY] = true
    data[PROCESSED_KEY] = true
    data[OWNER_KEY] = EntityPtr(familiar)
    child.CollisionDamage = familiar.Player.Damage * DAMAGE_MULTIPLIER
    child.Scale = child.Scale * TEAR_SCALE
end

function Combat.Register(mod)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
        debugCounts = {}
    end)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, processTear)
    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE, function(_, tear)
        local familiar = asMiniIsaac(tear.SpawnerEntity)
        if familiar and Router.IsManaging(familiar) then tear:Remove() end
    end, FamiliarVariant.MINISAAC)
    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, updateSwordMovement,
        FamiliarVariant.MINISAAC)
    mod:AddCallback(ModCallbacks.MC_PRE_KNIFE_UPDATE, updateSwordHitbox)
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, updateSwordVisual)
    if ModCallbacks.MC_POST_FIRE_SPLIT_TEAR then
        mod:AddCallback(ModCallbacks.MC_POST_FIRE_SPLIT_TEAR, onSplitTear)
    end
end

return Combat
