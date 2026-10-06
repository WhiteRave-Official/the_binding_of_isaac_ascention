local FlamingRose = {}

local TEAR_KEY = "AscentionFlamingRoseTear"
local WEAPON_KEY = "AscentionFlamingRoseWeapon"
local FLAME_KEY = "AscentionFlamingRoseFlame"
local FLAME_COOLDOWN_KEY = "AscentionFlamingRoseFlameCooldown"
local FIRE_TEAR_ANIMATION = "gfx/002.005_fire tear.anm2"
local FLAME_DAMAGE_MULTIPLIER = 2
local FLAME_SPEED = 9
local FLAME_LIFETIME = 210
local FLAME_DRAG = 0.85
local TEAR_VISUAL_SCALE = 0.5
local BURN_DURATION = 90
local BURN_DAMAGE_MULTIPLIER = 0.2
local CONTINUOUS_HIT_COOLDOWN = 12

local function ownerOf(entity, depth)
    if not entity or depth > 4 then return nil end
    local player = entity:ToPlayer()
    if player then return player end
    local familiar = entity:ToFamiliar()
    if familiar and familiar.Player then return familiar.Player end
    local data = entity:GetData()
    local pointer = data.AscentionMiniIsaacOwner
    local mini = pointer and pointer.Ref
    if mini and mini:Exists() then return mini.Player end
    return ownerOf(entity.SpawnerEntity, depth + 1)
        or ownerOf(entity.Parent, depth + 1)
end

local function markTear(tear, owner, itemId)
    if not owner or not owner:HasCollectible(itemId) then return end
    local data = tear:GetData()
    if data[TEAR_KEY] then return end
    data[TEAR_KEY] = { owner = EntityPtr(owner), hits = 0 }
end

local function markWeapon(weapon, itemId)
    local data = weapon:GetData()
    local marked = data[WEAPON_KEY]
    if marked then return marked end
    local owner = ownerOf(weapon, 0)
    if not owner or not owner:HasCollectible(itemId) then return nil end
    marked = { owner = EntityPtr(owner) }
    data[WEAPON_KEY] = marked
    return marked
end

local function updateTearVisual(tear)
    local sprite = tear:GetSprite()
    local filename = (sprite:GetFilename() or ""):lower()
    if not filename:match("002%.005_fire tear%.anm2$") then
        sprite:Load(FIRE_TEAR_ANIMATION, true)
    end
    local animation = math.abs(tear.Velocity.X) > math.abs(tear.Velocity.Y)
        and "MoveHori" or "MoveVert"
    if sprite:GetAnimation() ~= animation then
        sprite:Play(animation, true)
    end
    sprite.Scale = Vector(TEAR_VISUAL_SCALE, TEAR_VISUAL_SCALE)
    sprite.FlipX = animation == "MoveHori" and tear.Velocity.X < 0
    sprite.FlipY = animation == "MoveVert" and tear.Velocity.Y < 0
end

local function hitWeapon(entity)
    if not entity then return nil end
    return entity:ToTear() or entity:ToLaser()
        or entity:ToKnife() or entity:ToBomb()
end

function FlamingRose.Register(mod, itemId)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, function(_, tear)
        markTear(tear, ownerOf(tear.SpawnerEntity, 0)
            or ownerOf(tear.Parent, 0), itemId)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
        markTear(tear, ownerOf(tear.SpawnerEntity, 0)
            or ownerOf(tear.Parent, 0), itemId)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_SPLIT_TEAR,
        function(_, child, source)
            local parent = source and source:GetData()[TEAR_KEY]
            local owner = parent and parent.owner.Ref
            if owner and owner:Exists() then
                markTear(child, owner, itemId)
            end
        end)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
        if not tear:GetData()[TEAR_KEY] then return end
        updateTearVisual(tear)
    end)

    for _, callback in ipairs({
        ModCallbacks.MC_POST_LASER_INIT,
        ModCallbacks.MC_POST_FIRE_TECH_LASER,
        ModCallbacks.MC_POST_FIRE_TECH_X_LASER,
        ModCallbacks.MC_POST_FIRE_KNIFE,
        ModCallbacks.MC_POST_FIRE_BOMB,
    }) do
        mod:AddCallback(callback, function(_, weapon)
            markWeapon(weapon, itemId)
        end)
    end

    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, function(_, laser)
        if laser.FrameCount <= 2 then markWeapon(laser, itemId) end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_ENTITY_TAKE_DMG,
        function(_, entity, damage, flags, source, _, extraSource)
            if (flags & DamageFlag.DAMAGE_POISON_BURN) ~= 0 then return end
            local npc = entity:ToNPC()
            if not npc or not npc:IsActiveEnemy(true)
                or npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end

            local extra = extraSource and extraSource.Entity
            local direct = source and source.Entity
            local weapon = hitWeapon(extra) or hitWeapon(direct)
            if not weapon then return end
            local tear = weapon:ToTear()
            local data = tear and tear:GetData()[TEAR_KEY]
                or markWeapon(weapon, itemId)
            if not data then return end
            local owner = data.owner.Ref
            if not owner or not owner:Exists() then return end

            local hitDamage = tear and tear.CollisionDamage or damage
            npc:AddBurn(EntityRef(owner), BURN_DURATION,
                math.max(1, hitDamage * BURN_DAMAGE_MULTIPLIER), true)
            if weapon:ToLaser() or weapon:ToKnife() then
                local now = Game():GetFrameCount()
                local targetData = npc:GetData()
                if now < (targetData[FLAME_COOLDOWN_KEY] or -1) then return end
                targetData[FLAME_COOLDOWN_KEY] = now + CONTINUOUS_HIT_COOLDOWN
            end

            data.hits = (data.hits or 0) + 1
            local seed = ((weapon.InitSeed ~ npc.InitSeed) + data.hits * 131) & 0x7fffffff
            local rng = RNG()
            rng:SetSeed(seed + 1, 35)
            local direction = Vector.FromAngle(rng:RandomInt(360))
            local position = npc.Position + direction * (npc.Size + 6)
            local flame = Isaac.Spawn(EntityType.ENTITY_EFFECT,
                EffectVariant.RED_CANDLE_FLAME, 0, position,
                direction * FLAME_SPEED, owner):ToEffect()
            flame.Parent = owner
            flame.State = 1
            flame.Timeout = FLAME_LIFETIME
            flame.CollisionDamage = hitDamage * FLAME_DAMAGE_MULTIPLIER
            flame:GetData()[FLAME_KEY] = true
        end, EntityType.ENTITY_NPC)

    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, effect)
        if effect:GetData()[FLAME_KEY] then
            effect.Velocity = effect.Velocity * FLAME_DRAG
        end
    end, EffectVariant.RED_CANDLE_FLAME)
end

return FlamingRose
