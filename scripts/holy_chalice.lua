local HolyChalice = {}
local Synergies = include("scripts.holy_chalice_synergies")
local Damage = include("scripts.holy_chalice_damage")
local Knife = include("scripts.holy_chalice_knife")
local Multishot = include("scripts.holy_chalice_multishot")
local Splash = include("scripts.holy_chalice_splash")
local Tammy = include("scripts.holy_chalice_tammy")
local Flight = include("scripts.holy_chalice_flight")
local IDLE_COSTUME = Isaac.GetCostumeIdByPath("gfx/characters/holy_chalice.anm2")
local SHOOT_COSTUME = Isaac.GetCostumeIdByPath("gfx/characters/holy_chalice_shoot.anm2")

local TEAR_KEY = "AscentionHolyChaliceBubble"

local BUBBLE_SHEET = "gfx/projectiles/bubble_tear_projectile.png"
local HAEMO_BUBBLE_SHEET = "gfx/projectiles/bubble_tear_projectile_red.png"
local TEAR_ANIMATION = "gfx/projectiles/golden_tear_projectile.anm2"
local BURST_RADIUS = 48
local BURST_DAMAGE_MULTIPLIER = 0.33
local TEARS_BONUS = 0.3
local SHOT_SPEED_PENALTY = 0.15
local STREAM_INTERVAL_AT_BASE_RATE = 4
local BASE_FIRE_DELAY = 10
local BUBBLE_ANGLE_SPREAD = 22
local MONSTRO_MIN_DAMAGE = 0.65
local MONSTRO_DAMAGE_SPREAD = 0.95
local BUBBLE_SIZE_THRESHOLDS = { 0.3, 0.55, 0.675, 0.8, 0.925, 1.05,
    1.175, 1.425, 1.675, 1.925, 2.175, 2.55 }

local function syncBubbleSize(tear)
    local data = tear:GetData()[TEAR_KEY]
    local sprite = data and data.renderSprite or tear:GetSprite()
    local scale = tear.Scale
    local size = 13
    for index, threshold in ipairs(BUBBLE_SIZE_THRESHOLDS) do
        if scale <= threshold then
            size = index
            break
        end
    end
    local animation = (data and data.bloodAnimation
        and "BloodTear" or "RegularTear") .. size
    if sprite:GetAnimation() ~= animation then
        sprite:SetFrame(animation, 0)
    end
end

local function isShootAction(action)
    return action == ButtonAction.ACTION_SHOOTLEFT
        or action == ButtonAction.ACTION_SHOOTRIGHT
        or action == ButtonAction.ACTION_SHOOTUP
        or action == ButtonAction.ACTION_SHOOTDOWN
end

local function attackMode(player)
    local weapon = player:GetWeapon(1)
    local kind = weapon and weapon:GetWeaponType()
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
        return "knife"
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
        return "c_section"
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then
        return "bubble"
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then
        return "monstro"
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then
        return "ludo"
    end
    local brimstone = player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
    local techX = player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X)
    local brimWeapon = player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE)
    local techXWeapon = player:HasWeaponType(WeaponType.WEAPON_TECH_X)
    if brimstone and techX and (brimWeapon or techXWeapon) then
        return "brim_techx"
    end
    if brimstone and brimWeapon then return "brimstone" end
    if techX and techXWeapon then return "techx" end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY_2) then
        return "technology_2"
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY) then
        return "technology"
    end
    if kind == WeaponType.WEAPON_TEARS then return "bubble" end
end

local function shootInput(player)
    local index = player.ControllerIndex
    local x = Input.GetActionValue(ButtonAction.ACTION_SHOOTRIGHT, index)
        - Input.GetActionValue(ButtonAction.ACTION_SHOOTLEFT, index)
    local y = Input.GetActionValue(ButtonAction.ACTION_SHOOTDOWN, index)
        - Input.GetActionValue(ButtonAction.ACTION_SHOOTUP, index)
    local direction = Vector(x, y)
    return direction:LengthSquared() > 0.01 and direction:Normalized() or nil
end

local function headDirection(aim)
    if math.abs(aim.X) > math.abs(aim.Y) then
        return aim.X > 0 and Direction.RIGHT or Direction.LEFT
    end
    return aim.Y > 0 and Direction.DOWN or Direction.UP
end

local function setCostume(player, costumeId)
    local data = player:GetData()
    if data.HolyChaliceCostume == costumeId then return end
    if data.HolyChaliceCostume then
        player:TryRemoveNullCostume(data.HolyChaliceCostume)
    end
    data.HolyChaliceCostume = nil
    if costumeId and costumeId >= 0 then
        player:AddNullCostume(costumeId)
        data.HolyChaliceCostume = costumeId
    end
end

local function ownerOf(entity, depth)
    if not entity or depth > 4 then return nil end
    local player = entity:ToPlayer()
    if player then return player end
    local familiar = entity:ToFamiliar()
    if familiar and familiar.Player then return familiar.Player end
    return ownerOf(entity.SpawnerEntity, depth + 1)
        or ownerOf(entity.Parent, depth + 1)
end

local function directOwner(entity)
    if not entity then return nil end
    local source = entity.SpawnerEntity or entity.Parent
    return source and source:ToPlayer() or nil
end

local function familiarSource(entity)
    local parent = entity and entity.Parent
    local spawner = entity and entity.SpawnerEntity
    return (parent and parent.ToFamiliar and parent:ToFamiliar())
        or (spawner and spawner.ToFamiliar and spawner:ToFamiliar())
end

local function markBubble(tear, itemId, owner, forced)
    local data = tear:GetData()
    if data[TEAR_KEY] then return end
    owner = owner or ownerOf(tear.SpawnerEntity, 0)
        or ownerOf(tear.Parent, 0)
    if not owner or not owner:HasCollectible(itemId) then return end
    local mode = attackMode(owner)
    if not forced and mode ~= "bubble"
        and mode ~= "technology_2" then return end
    data[TEAR_KEY] = {
        owner = EntityPtr(owner), itemId = itemId, popped = false, age = 0,
        range = math.max(40, owner.TearRange), travel = 0,
        lastPosition = tear.Position,
        angleSpread = BUBBLE_ANGLE_SPREAD,
    }
    local sprite = tear:GetSprite()
    local animation = sprite:GetAnimation() or ""
    local frame = sprite:GetFrame()
    local bloodAnimation = owner:HasCollectible(
        CollectibleType.COLLECTIBLE_HAEMOLACRIA)
    data[TEAR_KEY].bloodAnimation = bloodAnimation
    local sheet = (bloodAnimation or attackMode(owner) == "monstro")
        and HAEMO_BUBBLE_SHEET or BUBBLE_SHEET
    data[TEAR_KEY].splashRed = sheet == HAEMO_BUBBLE_SHEET
    if bloodAnimation and owner:HasCollectible(
        CollectibleType.COLLECTIBLE_BRIMSTONE) then
        sprite = Sprite()
        data[TEAR_KEY].renderSprite = sprite
    end
    sprite:Load(TEAR_ANIMATION, true)
    sprite:ReplaceSpritesheet(0, sheet, true)
    local tearSize = animation:match("^RegularTear(%d+)$")
        or animation:match("^BloodTear(%d+)$")
    if tearSize then
        sprite:SetFrame((bloodAnimation and "BloodTear" or "RegularTear")
            .. tearSize, frame)
    else
        sprite:SetFrame(bloodAnimation and "BloodTear6"
            or "RegularTear6", 0)
    end
end

local function configureBubble(tear)
    local data = tear:GetData()[TEAR_KEY]
    if not data or data.configured then return end
    data.configured = true
    data.flightHeight = math.min(tear.Height or -23, -20)
    tear.Height = data.flightHeight
    local rng = RNG()
    rng:SetSeed(tear.InitSeed, 35)
    local damageMultiplier = data.damageRoll or Damage.Roll(rng)
    tear.CollisionDamage = tear.CollisionDamage * damageMultiplier
    tear.Scale = math.min(2.55,
        tear.Scale * math.max(0.55, math.sqrt(damageMultiplier)))
    syncBubbleSize(tear)
    tear.Velocity = tear.Velocity:Rotated(
        (rng:RandomFloat() * 2 - 1) * data.angleSpread)
    data.speed = tear.Velocity:Length()
    if data.speed > 0.01 then
        data.launchDirection = tear.Velocity:Normalized()
    end
    data.driftPhase = rng:RandomFloat() * math.pi * 2
    local ownerEntity = data.owner and data.owner.Ref
    local owner = ownerEntity and ownerEntity:ToPlayer()
    Flight.Init(data, tear, owner)
    tear.FallingSpeed = 0
    tear.FallingAcceleration = 0
end

local function fireBubble(player, itemId, position, velocity, scale,
    damageMultiplier, spread, roll, plain)
    local playerData = player:GetData()
    playerData.HolyChaliceFiringCustom = true
    local tear
    if plain then
        local spawned = Isaac.Spawn(EntityType.ENTITY_TEAR,
            TearVariant.BLUE, 0, position, velocity, player)
        tear = spawned and spawned:ToTear()
        if tear then tear.CollisionDamage = player.Damage end
    else
        tear = player:FireTear(position, velocity, false, true, false)
    end
    playerData.HolyChaliceFiringCustom = nil
    if not tear then return end
    markBubble(tear, itemId, player, true)
    local data = tear:GetData()[TEAR_KEY]
    data.angleSpread = spread or 0
    data.damageRoll = roll
    configureBubble(tear)
    tear.Scale = math.min(2.55, tear.Scale * (scale or 1))
    tear:ResetSpriteScale(true)
    syncBubbleSize(tear)
    if roll then
        tear.CollisionDamage = player.Damage * roll * (damageMultiplier or 1)
    else
        tear.CollisionDamage = tear.CollisionDamage * (damageMultiplier or 1)
    end
    return tear
end

local function fireCharged(player, mode, direction, itemId)
    if mode == "knife" then
        return -- The native knife handles the throw; Knife.Register adds the endpoint bubbles.
    elseif mode == "monstro" then
        local rng = player:GetCollectibleRNG(itemId)
        fireBubble(player, itemId, player.Position,
            direction * (8 * player.ShotSpeed), 2.2, 1, 0, 1.2)
        local clusters = Multishot.Clusters(player, rng)
        local smallCount = 3 + rng:RandomInt(4)
            + (#clusters - 1) * 2
        for i = 1, smallCount do
            local angle = (i - (smallCount + 1) / 2) * 11
                + (rng:RandomFloat() - 0.5) * 12
            local roll = MONSTRO_MIN_DAMAGE
                + rng:RandomFloat() * MONSTRO_DAMAGE_SPREAD
            local smallScale = 0.42 + (roll - MONSTRO_MIN_DAMAGE)
                / MONSTRO_DAMAGE_SPREAD * 0.8
            fireBubble(player, itemId, player.Position,
                direction:Rotated(angle)
                    * ((8 + rng:RandomFloat() * 3) * player.ShotSpeed),
                smallScale, 1, 2, roll)
        end
    end
end

local function fireRadialBubbles(player, itemId, position, aim,
    count, spread, speed, scale)
    local rng = player:GetCollectibleRNG(itemId)
    for _ = 1, count do
        local direction = aim:Rotated((rng:RandomFloat() - 0.5) * spread)
        fireBubble(player, itemId, position,
            direction * ((speed + rng:RandomFloat() * 2) * player.ShotSpeed),
            scale or 0.6, 1, 0, 1, true)
    end
end

local function laserAim(laser, player)
    if laser.Velocity and laser.Velocity:LengthSquared() > 0.01 then
        return laser.Velocity:Normalized()
    end
    if laser.AngleDegrees then return Vector.FromAngle(laser.AngleDegrees) end
    return shootInput(player) or Vector(1, 0)
end

local function supplementFetus(player, tear, itemId)
    local data = tear:GetData()
    if data.HolyChaliceSupplementedFetus
        or tear.Variant ~= TearVariant.FETUS then return end
    data.HolyChaliceSupplementedFetus = true
    local velocity = tear.Velocity
    if velocity:LengthSquared() < 0.01 then return end
    local direction = velocity:Normalized()
    for index = -1, 1 do
        fireBubble(player, itemId, tear.Position,
            direction:Rotated(index * 13) * (6 * player.ShotSpeed),
            0.6, 1, 3, 1, true)
    end
end

local function fireStream(player, itemId, direction)
    local rng = player:GetCollectibleRNG(itemId)
    for _, cluster in ipairs(Multishot.Clusters(player, rng)) do
        local trajectory = direction:Rotated(cluster.angle)
        for _ = 1, cluster.size do
            local angleJitter = (rng:RandomFloat() - 0.5) * 10
            local lateral = (rng:RandomFloat() - 0.5) * 12
            local forward = rng:RandomFloat() * 6
            local position = player.Position
                + trajectory:Rotated(90) * lateral
                + trajectory * forward
            local velocity = trajectory:Rotated(angleJitter)
                * ((8.5 + rng:RandomFloat() * 3) * player.ShotSpeed)
            fireBubble(player, itemId, position, velocity,
                1, 1, cluster.clustered and 2 or BUBBLE_ANGLE_SPREAD)
        end
    end
end

local function fireFamiliarStream(familiar, itemId, direction)
    local player = familiar.Player
    local playerData = player:GetData()
    local rng = player:GetCollectibleRNG(itemId)
    local aim = direction:Rotated((rng:RandomFloat() - 0.5) * 10)
    playerData.HolyChaliceFiringCustom = true
    local tear = familiar:FireProjectile(aim)
    playerData.HolyChaliceFiringCustom = nil
    if tear then
        markBubble(tear, itemId, player, true)
        local data = tear:GetData()[TEAR_KEY]
        data.angleSpread = BUBBLE_ANGLE_SPREAD
        configureBubble(tear)
    end
    local facing = headDirection(aim)
    familiar.ShootDirection = facing
    familiar.LastDirection = facing
    local data = familiar:GetData()
    data.HolyChaliceShotFrame = Game():GetFrameCount()
    data.HolyChaliceShotFacing = facing
    familiar:PlayShootAnim(facing)
end

local function popBubble(tear, data)
    if data.popped then return end
    data.popped = true
    Splash.Show(tear)

    local ownerEntity = data.owner and data.owner.Ref
    local owner = ownerEntity and ownerEntity:ToPlayer()
    if not owner or not owner:Exists() then
        tear:Die()
        if not data.renderSprite then tear.Visible = false end
        return
    end
    local position = tear.Position
    local damage = owner.Damage * BURST_DAMAGE_MULTIPLIER
    for _, entity in ipairs(Isaac.FindInRadius(position, BURST_RADIUS,
        EntityPartition.ENEMY)) do
        local npc = entity:ToNPC()
        if npc and npc:IsActiveEnemy(true) and not npc:IsDead()
            and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and position:DistanceSquared(npc.Position)
                <= (BURST_RADIUS + npc.Size) ^ 2
        then
            npc:TakeDamage(damage, 0, EntityRef(owner), 0)
        end
    end

    if owner:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then
        local rng = RNG()
        rng:SetSeed(tear.InitSeed, 59)
        if rng:RandomFloat() < 0.15 then
            local bomb = Isaac.Spawn(EntityType.ENTITY_BOMB,
                BombVariant.BOMB_SMALL, 0, position, Vector.Zero,
                owner):ToBomb()
            if bomb then
                bomb.ExplosionDamage = owner.Damage * 0.5
                bomb.RadiusMultiplier = 0.55
                bomb:SetExplosionCountdown(30)
            end
        end
    end
    SFXManager():Play(SoundEffect.SOUND_PLOP, 0.35, 0, false, 1.15)
    if data.renderSprite and not data.splitChild then
        Synergies.FireBrimBall(owner, position,
            data.launchDirection or shootInput(owner) or Vector(1, 0),
            data.itemId)
    end
    -- Keep the native sprite intact until Die() has generated split tears and lasers.
    tear:Die()
    if not data.renderSprite then tear.Visible = false end
end

function HolyChalice.Register(mod, itemId)
    local bloodLaserSamples = 0
    Synergies.Register(mod)
    Splash.Register(mod)
    Tammy.Register(mod, itemId)
    Knife.Register(mod, itemId, function(player, position, velocity)
        local tear = fireBubble(player, itemId, position, velocity, 0.6, 1, 0)
        if tear then
            local data = tear:GetData()[TEAR_KEY]
            data.range = math.max(180, player.TearRange * 1.4)
            data.keepMomentum = true
        end
    end)
    mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cacheFlag)
        local count = player:GetCollectibleNum(itemId)
        if count == 0 then return end
        if cacheFlag == CacheFlag.CACHE_FIREDELAY then
            local tears = 30 / (player.MaxFireDelay + 1)
                + TEARS_BONUS * count
            player.MaxFireDelay = 30 / math.max(0.1, tears) - 1
        elseif cacheFlag == CacheFlag.CACHE_SHOTSPEED then
            player.ShotSpeed = player.ShotSpeed - SHOT_SPEED_PENALTY * count
        end
    end)

    mod:AddCallback(ModCallbacks.MC_INPUT_ACTION,
        function(_, entity, hook, action)
            local player = entity and entity:ToPlayer()
            if not player or not player:HasCollectible(itemId)
                or player:GetData().GoldenEyeBlockedShooting
                or attackMode(player) ~= "bubble"
                or not isShootAction(action) then
                return
            end
            if hook == InputHook.GET_ACTION_VALUE then return 0 end
            if hook == InputHook.IS_ACTION_PRESSED
                or hook == InputHook.IS_ACTION_TRIGGERED then return false end
        end)

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
        if not player:HasCollectible(itemId)
            or player:GetData().GoldenEyeBlockedShooting
            or not player:CanShoot() then
            setCostume(player, nil)
            return
        end
        local mode = attackMode(player)
        if not mode then
            player:GetData().HolyChaliceNativeShotCount = nil
            setCostume(player, nil)
            return
        end
        local direction = shootInput(player)
        setCostume(player, mode == "bubble"
            and (direction and SHOOT_COSTUME or IDLE_COSTUME) or nil)
        local data = player:GetData()
        data.HolyChaliceWasHolding = direction ~= nil
        if direction then player:SetHeadDirection(headDirection(direction), 2, true) end
        if mode ~= "bubble" then
            local weapon = player:GetWeapon(1)
            if not weapon then return end
            local fired = weapon:GetNumFired()
            if data.HolyChaliceNativeMode ~= mode
                or (data.HolyChaliceNativeShotCount
                    and fired < data.HolyChaliceNativeShotCount) then
                data.HolyChaliceNativeMode = mode
                data.HolyChaliceNativeShotCount = fired
            end
            if direction then data.HolyChaliceNativeAim = direction end
            local previous = data.HolyChaliceNativeShotCount or fired
            if mode == "knife" then
                local maximum = weapon:GetMaxCharge()
                if direction and maximum > 0 then
                    data.HolyChaliceKnifeChargeFraction = math.max(
                        data.HolyChaliceKnifeChargeFraction or 0,
                        math.max(0, math.min(1,
                            weapon:GetCharge() / maximum)))
                end
                if fired > previous then
                    data.HolyChaliceKnifeShotSerial = fired
                    data.HolyChaliceKnifeThrowCharge =
                        data.HolyChaliceKnifeChargeFraction or 0.25
                    data.HolyChaliceKnifeChargeFraction = 0
                end
            elseif fired > previous then
                fireCharged(player, mode,
                    data.HolyChaliceNativeAim or weapon:GetDirection(), itemId)
            end
            data.HolyChaliceNativeShotCount = fired
            return
        end
        data.HolyChaliceNativeMode = nil
        data.HolyChaliceNativeShotCount = nil
        if not direction then return end
        local frame = Game():GetFrameCount()
        local nextShot = data.HolyChaliceNextShotFrame or frame
        if frame < nextShot then return end
        local interval = math.max(1,
            STREAM_INTERVAL_AT_BASE_RATE * (player.MaxFireDelay + 1)
                / BASE_FIRE_DELAY)
        data.HolyChaliceNextShotFrame = math.max(frame, nextShot) + interval
        fireStream(player, itemId, direction)
    end)

    local function updateMirroringFamiliar(_, familiar)
        local player = familiar.Player
        if not player or not player:HasCollectible(itemId)
            or player:GetData().GoldenEyeBlockedShooting
            or not player:CanShoot()
            or attackMode(player) ~= "bubble" then return end
        local direction = shootInput(player)
        if not direction then return end
        local frame = Game():GetFrameCount()
        local data = familiar:GetData()
        local facing = headDirection(direction)
        familiar.ShootDirection = facing
        familiar.LastDirection = facing
        if frame < (data.HolyChaliceNextShotFrame or frame) then return end
        local interval = math.max(1,
            STREAM_INTERVAL_AT_BASE_RATE * (player.MaxFireDelay + 1)
                / BASE_FIRE_DELAY)
        data.HolyChaliceNextShotFrame = frame + interval
        fireFamiliarStream(familiar, itemId, direction)
    end
    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE,
        updateMirroringFamiliar, FamiliarVariant.INCUBUS)
    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE,
        updateMirroringFamiliar, FamiliarVariant.TWISTED_BABY)

    local function renderMirroringFamiliar(_, familiar)
        local data = familiar:GetData()
        if data.HolyChaliceShotFrame == Game():GetFrameCount() then
            local facing = data.HolyChaliceShotFacing
            familiar.ShootDirection = facing
            familiar.LastDirection = facing
            familiar:PlayShootAnim(facing)
        end
    end
    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_RENDER,
        renderMirroringFamiliar, FamiliarVariant.INCUBUS)
    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_RENDER,
        renderMirroringFamiliar, FamiliarVariant.TWISTED_BABY)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, function(_, tear)
        local source = directOwner(tear)
        if source and source:GetData().HolyChaliceFiringCustom then return end
        if source and attackMode(source) == "bubble" then return end
        markBubble(tear, itemId)
    end)
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
        local familiar = familiarSource(tear)
        local familiarOwner = familiar and ownerOf(familiar, 0)
        if familiarOwner and familiarOwner:HasCollectible(itemId) then
            local familiarMode = attackMode(familiarOwner)
            if familiarMode == "bubble" or familiarMode == "technology_2"
                or familiarMode == "monstro" then
                markBubble(tear, itemId, familiarOwner, true)
                configureBubble(tear)
                return
            end
        end
        local player = directOwner(tear)
        if player and player:GetData().HolyChaliceFiringCustom then return end
        if player and player:HasCollectible(itemId) then
            local mode = attackMode(player)
            if mode == "bubble" then
                if Tammy.IsBurst(player) then
                    markBubble(tear, itemId, player, true)
                    local data = tear:GetData()[TEAR_KEY]
                    data.angleSpread = 0
                    configureBubble(tear)
                    return
                end
                tear.Visible = false
                tear:Remove()
                return
            end
            if mode == "c_section" then
                supplementFetus(player, tear, itemId)
                return
            end
            if mode == "monstro" then
                tear:Remove()
                return
            end
        end
        markBubble(tear, itemId)
        configureBubble(tear)
        syncBubbleSize(tear)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_BRIMSTONE, function(_, laser)
        local player = ownerOf(laser.SpawnerEntity, 0)
            or ownerOf(laser.Parent, 0)
        if not player or not player:HasCollectible(itemId)
            or player:GetData().HolyChaliceFiringCustom then return end
        local mode = attackMode(player)
        if mode == "brimstone"
            and not player:HasCollectible(
                CollectibleType.COLLECTIBLE_HAEMOLACRIA) then
            Synergies.FireBrimBall(player, laser.Position,
                laserAim(laser, player), itemId)
        end
    end)
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TECH_X_LASER,
        function(_, laser)
            local player = ownerOf(laser.SpawnerEntity, 0)
                or ownerOf(laser.Parent, 0)
            if not player or not player:HasCollectible(itemId)
                or player:GetData().HolyChaliceFiringCustom then return end
            local mode = attackMode(player)
            if mode == "techx" or mode == "brim_techx" then
                Synergies.AdoptTechX(player, laser,
                    mode == "brim_techx")
            end
        end)
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TECH_LASER,
        function(_, laser)
            local player = ownerOf(laser.SpawnerEntity, 0)
                or ownerOf(laser.Parent, 0)
            if not player or not player:HasCollectible(itemId)
                or player:GetData().HolyChaliceFiringCustom then return end
            if attackMode(player) == "technology" then
                local rng = player:GetCollectibleRNG(itemId)
                fireRadialBubbles(player, itemId, laser.Position,
                    laserAim(laser, player), 2 + rng:RandomInt(4),
                    36, 7, 0.6)
            end
        end)
    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE,
        function(_, tear)
            local familiar = tear.SpawnerEntity or tear.Parent
            local player = ownerOf(familiar, 0)
            if not player or not player:HasCollectible(itemId) then return end
            local mode = attackMode(player)
            if mode == "c_section" then
                supplementFetus(player, tear, itemId)
            elseif mode == "bubble" or mode == "technology_2"
                or mode == "monstro" then
                markBubble(tear, itemId, player, true)
                configureBubble(tear)
            end
        end)
    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_BRIMSTONE,
        function(_, laser)
            local familiar = laser.SpawnerEntity or laser.Parent
            local player = ownerOf(familiar, 0)
            if player and player:HasCollectible(itemId)
                and attackMode(player) == "brimstone" then
                fireRadialBubbles(player, itemId, laser.Position,
                    laserAim(laser, player), 2, 22, 7, 0.55)
            end
        end)
    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_TECH_LASER,
        function(_, laser)
            local familiar = laser.SpawnerEntity or laser.Parent
            local player = ownerOf(familiar, 0)
            if player and player:HasCollectible(itemId)
                and attackMode(player) == "technology" then
                fireRadialBubbles(player, itemId, laser.Position,
                    laserAim(laser, player), 2, 22, 7, 0.55)
            end
        end)
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_SPLIT_TEAR,
        function(_, child, source)
            local sourceData = source and source:GetData()[TEAR_KEY]
            local ownerEntity = sourceData and sourceData.owner.Ref
            local owner = ownerEntity and ownerEntity:ToPlayer()
            if owner and owner:Exists() and owner:HasCollectible(itemId) then
                markBubble(child, itemId, owner, true)
                child:GetData()[TEAR_KEY].splitChild = true
                configureBubble(child)
            end
        end)

    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE,
        function(_, laser)
            local player = directOwner(laser)
            if bloodLaserSamples < 12 and laser.FrameCount == 1
                and player and player:HasCollectible(itemId)
                and player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
                and player:HasCollectible(CollectibleType.COLLECTIBLE_HAEMOLACRIA) then
                bloodLaserSamples = bloodLaserSamples + 1
                local sprite = laser:GetSprite()
                Isaac.DebugString("[AscentionChalice] blood_brim_laser"
                    .. " variant=" .. tostring(laser.Variant)
                    .. " visible=" .. tostring(laser.Visible)
                    .. " animation=" .. tostring(sprite:GetAnimation())
                    .. " anm2=" .. tostring(sprite:GetFilename())
                    .. " scale=" .. tostring(laser:GetScale()))
            end
            if not player or not player:HasCollectible(itemId)
                or player:GetData().HolyChaliceFiringCustom
                or attackMode(player) ~= "technology_2" then return end
            local frame = Game():GetFrameCount()
            local data = player:GetData()
            if frame < (data.HolyChaliceTech2Next or 0) then return end
            data.HolyChaliceTech2Next = frame + 8
            fireRadialBubbles(player, itemId, laser.Position,
                laserAim(laser, player), 1, 16, 7, 0.45)
        end)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
        local tearData = tear:GetData()
        if tearData.HolyChaliceSuppressUntil then
            tear.Visible = false
            if Game():GetFrameCount() >= tearData.HolyChaliceSuppressUntil then
                tear:Remove()
            end
            return
        end
        if not tearData[TEAR_KEY] then
            local familiar = familiarSource(tear)
            local owner = familiar and ownerOf(familiar, 0)
            if owner and owner:HasCollectible(itemId) then
                local mode = attackMode(owner)
                if mode == "bubble" or mode == "technology_2"
                    or mode == "monstro" then
                    markBubble(tear, itemId, owner, true)
                end
            end
        end
        local data = tearData[TEAR_KEY]
        if not data then
            local player = directOwner(tear)
            if player and player:HasCollectible(itemId) then
                local mode = attackMode(player)
                if mode == "c_section" then
                    supplementFetus(player, tear, itemId)
                elseif mode == "ludo"
                    and tear:HasTearFlags(TearFlags.TEAR_LUDOVICO) then
                    local tearData = tear:GetData()
                    local frame = Game():GetFrameCount()
                    if not tearData.HolyChaliceLudoNext then
                        tearData.HolyChaliceLudoNext = frame + 20
                    elseif frame >= tearData.HolyChaliceLudoNext then
                        local rng = player:GetCollectibleRNG(itemId)
                        fireRadialBubbles(player, itemId, tear.Position,
                            Vector.FromAngle(rng:RandomInt(360)),
                            2 + rng:RandomInt(3), 360, 6, 0.55)
                        tearData.HolyChaliceLudoNext = frame + 20
                    end
                end
            end
            return
        end
        if data.popped then
            if not data.renderSprite then tear.Visible = false end
            return
        end
        configureBubble(tear)
        syncBubbleSize(tear)
        tear.Height = data.flightHeight
        tear.FallingSpeed = 0
        tear.FallingAcceleration = 0
        local ownerEntity = data.owner and data.owner.Ref
        local owner = ownerEntity and ownerEntity:ToPlayer()
        if Flight.Update(tear, data, owner) then popBubble(tear, data) end
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_TEAR_RENDER, function(_, tear)
        local data = tear:GetData()[TEAR_KEY]
        if not data or not data.renderSprite then return end
        if not data.popped then
            local sprite = data.renderSprite
            local nativeScale = tear:GetSprite().Scale
            sprite.Scale = nativeScale or Vector(tear.Scale, tear.Scale)
            sprite:Render(Isaac.WorldToRenderPosition(
                tear.Position + Vector(0, tear.Height or 0)))
        end
        return false
    end)

    mod:AddCallback(ModCallbacks.MC_POST_ENTITY_TAKE_DMG,
        function(_, target, _, _, source, _, extraSource)
            local npc = target:ToNPC()
            if not npc or npc.Type == EntityType.ENTITY_FIREPLACE
                or npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
            local extra = extraSource and extraSource.Entity
            local direct = source and source.Entity
            local tear = (extra and extra:ToTear())
                or (direct and direct:ToTear())
            if not tear then return end
            local data = tear:GetData()[TEAR_KEY]
            if data then popBubble(tear, data) end
        end, EntityType.ENTITY_NPC)

end

return HolyChalice
