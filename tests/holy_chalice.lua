local nextCallbackId = 0
ModCallbacks = setmetatable({}, {
    __index = function(self, key)
        nextCallbackId = nextCallbackId + 1
        rawset(self, key, nextCallbackId)
        return nextCallbackId
    end,
})
CacheFlag = { CACHE_FIREDELAY = 1, CACHE_SHOTSPEED = 2 }
EntityType = { ENTITY_NPC = 1, ENTITY_EFFECT = 2, ENTITY_TEAR = 5,
    ENTITY_FIREPLACE = 33,
    ENTITY_BOMB = 4 }
TearFlags = { TEAR_FETUS = 4096, TEAR_LUDOVICO = 8192 }
TearVariant = { FETUS = 50, BLUE = 0 }
BombVariant = { BOMB_SMALL = 14 }
EntityPartition = { ENEMY = 1 }
EntityFlag = { FLAG_FRIENDLY = 1 }
EffectVariant = { TEAR_POOF_A = 12 }
SoundEffect = { SOUND_PLOP = 237 }
WeaponType = { WEAPON_TEARS = 1, WEAPON_BRIMSTONE = 2,
    WEAPON_TECH_X = 3, WEAPON_LASER = 4 }
CollectibleType = { COLLECTIBLE_BRIMSTONE = 101, COLLECTIBLE_TECH_X = 102,
    COLLECTIBLE_MOMS_KNIFE = 103, COLLECTIBLE_C_SECTION = 104,
    COLLECTIBLE_DR_FETUS = 105, COLLECTIBLE_HAEMOLACRIA = 106,
    COLLECTIBLE_MUTANT_SPIDER = 107, COLLECTIBLE_INNER_EYE = 108,
    COLLECTIBLE_20_20 = 109, COLLECTIBLE_THE_WIZ = 110,
    COLLECTIBLE_MONSTROS_LUNG = 111, COLLECTIBLE_SOY_MILK = 112,
    COLLECTIBLE_TECHNOLOGY = 113, COLLECTIBLE_TECHNOLOGY_2 = 114,
    COLLECTIBLE_LUDOVICO_TECHNIQUE = 115,
    COLLECTIBLE_INCUBUS = 116, COLLECTIBLE_TWISTED_PAIR = 117,
    COLLECTIBLE_TAMMYS_HEAD = 118, COLLECTIBLE_MY_REFLECTION = 119 }
TrinketType = { TRINKET_RING_WORM = 11, TRINKET_BRAIN_WORM = 144 }
EffectVariant.BRIMSTONE_BALL = 113
ButtonAction = { ACTION_SHOOTLEFT = 1, ACTION_SHOOTRIGHT = 2,
    ACTION_SHOOTUP = 3, ACTION_SHOOTDOWN = 4 }
InputHook = { GET_ACTION_VALUE = 1, IS_ACTION_PRESSED = 2, IS_ACTION_TRIGGERED = 3 }
Direction = { LEFT = 1, RIGHT = 2, UP = 3, DOWN = 4 }
FamiliarVariant = { INCUBUS = 80, TWISTED_BABY = 235 }

local function vector(x, y)
    return {
        DistanceSquared = function(_, other)
            return (x - other.x) ^ 2 + (y - other.y) ^ 2
        end,
        Distance = function(_, other)
            return math.sqrt((x - other.x) ^ 2 + (y - other.y) ^ 2)
        end,
        x = x,
        y = y,
        X = x,
        Y = y,
        LengthSquared = function() return x * x + y * y end,
        Length = function() return math.sqrt(x * x + y * y) end,
        Normalized = function() local n = math.sqrt(x * x + y * y); return vector(x / n, y / n) end,
        Resized = function(_, length)
            local n = math.sqrt(x * x + y * y)
            return vector(x * length / n, y * length / n)
        end,
        Rotated = function(_, degrees)
            local angle = math.rad(degrees)
            return vector(x * math.cos(angle) - y * math.sin(angle),
                x * math.sin(angle) + y * math.cos(angle))
        end,
    }
end
Vector = setmetatable({ Zero = vector(0, 0),
    FromAngle = function(degrees)
        local radians = math.rad(degrees)
        return vector(math.cos(radians), math.sin(radians))
    end }, { __call = function(_, x, y) return vector(x, y) end })
local vectorMeta = {
    __mul = function(v, scalar) return vector(v.x * scalar, v.y * scalar) end,
    __add = function(a, b) return vector(a.x + b.x, a.y + b.y) end,
    __sub = function(a, b) return vector(a.x - b.x, a.y - b.y) end,
}
-- The production Vector userdata supports arithmetic; mirror only what the test uses.
local oldVector = vector
vector = function(x, y) return setmetatable(oldVector(x, y), vectorMeta) end
local rngValue = 0.5
local collectibleRngValue = 0.5
RNG = function()
    return { SetSeed = function() end, RandomFloat = function() return rngValue end }
end
local frame = 0
Game = function() return { GetFrameCount = function() return frame end } end
local splashSprites = {}
Sprite = function()
    local sprite = {
        Load = function(self, path) self.path = path end,
        ReplaceSpritesheet = function(self, layer, path, graphics)
            assert(layer == 0 and graphics)
            self.sheet = path
        end,
        SetFrame = function(self, animation, spriteFrame)
            self.animation = animation
            self.frame = spriteFrame
        end,
        GetAnimation = function(self) return self.animation or "" end,
        Render = function(self, position)
            self.renderedAt = position
            self.renderCount = (self.renderCount or 0) + 1
        end,
    }
    splashSprites[#splashSprites + 1] = sprite
    return sprite
end
local holdingAttack = true
Input = { GetActionValue = function(action)
    return holdingAttack and action == ButtonAction.ACTION_SHOOTRIGHT and 1 or 0
end }

local sounds = 0
SFXManager = function()
    return { Play = function() sounds = sounds + 1 end }
end
EntityPtr = function(entity)
    return { Ref = { ToPlayer = function() return entity end } }
end
EntityRef = function(entity) return { Entity = entity } end

local callbacks = {}
local mod = {
    AddCallback = function(_, id, callback) callbacks[id] = callback end,
}
local player = {
    Damage = 12,
    MaxFireDelay = 9,
    ShotSpeed = 1,
    TearRange = 120,
    count = 1,
    items = {},
    trinkets = {},
    nativeShots = 0,
    nativeCharge = 0,
    Position = vector(0, 0),
    ControllerIndex = 0,
    GetData = function(self) self.data = self.data or {}; return self.data end,
    GetWeapon = function(self)
        self.weapon = self.weapon or {
            GetWeaponType = function() return self.weaponKind or WeaponType.WEAPON_TEARS end,
            GetNumFired = function() return self.nativeShots end,
            GetDirection = function() return vector(1, 0) end,
            GetCharge = function() return self.nativeCharge end,
            GetMaxCharge = function() return 15 end,
            SetCharge = function(_, charge) self.nativeCharge = charge end,
        }
        return self.weapon
    end,
    HasWeaponType = function(self, kind)
        if kind == WeaponType.WEAPON_BRIMSTONE then
            return self.items[CollectibleType.COLLECTIBLE_BRIMSTONE] or false
        elseif kind == WeaponType.WEAPON_TECH_X then
            return self.items[CollectibleType.COLLECTIBLE_TECH_X] or false
        end
        return false
    end,
    CanShoot = function() return true end,
    SetHeadDirection = function(self, direction, time, force)
        self.headDirection = direction
        assert(time == 2 and force == true)
    end,
    AddNullCostume = function(self, id)
        self.costume = id
        self.costumeAdds = (self.costumeAdds or 0) + 1
    end,
    TryRemoveNullCostume = function(self, id)
        assert(self.costume == id)
        self.costume = nil
    end,
    ToPlayer = function(self) return self end,
    HasCollectible = function(self, id)
        if id == 9 then return self.count > 0 end
        local value = self.items[id]
        return value == true or type(value) == "number" and value > 0
    end,
    HasTrinket = function(self, id) return self.trinkets[id] or false end,
    GetCollectibleNum = function(self, id)
        if id == 9 then return self.count end
        local value = self.items[id]
        if value == true then return 1 end
        return type(value) == "number" and value or 0
    end,
    GetCollectibleRNG = function()
        return { RandomFloat = function() return collectibleRngValue end,
            RandomInt = function() return 0 end }
    end,
    Exists = function() return true end,
}

local bombs = {}
local shots = {}
local function dieTear(self)
    self.died = true
    self.removed = true
end
local tearSprite
Isaac = {
    WorldToRenderPosition = function(position) return position end,
    GetEntityVariantByName = function() return 9200 end,
    GetCostumeIdByPath = function(path)
        return path:find("_shoot", 1, true) and 91 or 90
    end,
    Spawn = function(kind, variant, _, position, velocity, owner)
        if kind == EntityType.ENTITY_TEAR then
            assert(variant == TearVariant.BLUE)
            local tear = {
                InitSeed = 801 + #shots, CollisionDamage = owner.Damage,
                Scale = 1, Velocity = velocity, Position = position,
                SpawnerEntity = owner,
                GetData = function(self)
                    self.data = self.data or {}
                    return self.data
                end,
                GetSprite = function() return tearSprite end,
                ResetSpriteScale = function(self) self.scaleReset = true end,
                ToTear = function(self) return self end,
                Remove = function(self) self.removed = true end,
                Die = dieTear,
            }
            shots[#shots + 1] = tear
            return tear
        end
        if kind == EntityType.ENTITY_BOMB then
            assert(variant == BombVariant.BOMB_SMALL)
            local bomb = { Position = position, Variant = variant,
                ToBomb = function(self) return self end,
                SetExplosionCountdown = function(self, value)
                    self.countdown = value
                end }
            bombs[#bombs + 1] = bomb
            return bomb
        end
        local effect = {}
        return effect
    end,
    FindInRadius = function() return {} end,
}

local synergyModule
local included = {}
include = function(path)
    if not included[path] then
        included[path] = dofile(path:gsub("%.", "/") .. ".lua")
    end
    if path == "scripts.holy_chalice_synergies" then
        synergyModule = included[path]
    end
    return included[path]
end
local chalice = dofile("scripts/holy_chalice.lua")
chalice.Register(mod, 9)
callbacks[ModCallbacks.MC_EVALUATE_CACHE](mod, player, CacheFlag.CACHE_FIREDELAY)
assert(math.abs(30 / (player.MaxFireDelay + 1) - 3.3) < 0.0001)
callbacks[ModCallbacks.MC_EVALUATE_CACHE](mod, player, CacheFlag.CACHE_SHOTSPEED)
assert(math.abs(player.ShotSpeed - 0.85) < 0.0001)
player.items[CollectibleType.COLLECTIBLE_MOMS_KNIFE] = true
player.MaxFireDelay = 9
callbacks[ModCallbacks.MC_EVALUATE_CACHE](mod, player, CacheFlag.CACHE_FIREDELAY)
assert(math.abs(30 / (player.MaxFireDelay + 1) - 3.3) < 0.0001,
    "Knife + Chalice must no longer have the obsolete fire-rate penalty")
player.MaxFireDelay = 0
callbacks[ModCallbacks.MC_EVALUATE_CACHE](mod, player, CacheFlag.CACHE_FIREDELAY)
assert(math.abs(30 / (player.MaxFireDelay + 1) - 30.3) < 0.0001,
    "Chalice must not cap knife fire rate")
player.items[CollectibleType.COLLECTIBLE_MOMS_KNIFE] = nil
player.MaxFireDelay = 9

local tearData = {}
local sourceFamiliar = { Player = player,
    ToPlayer = function() return nil end,
    ToFamiliar = function(self) return self end }
local sheet
local animationPath
local selectedFrame
tearSprite = {
    GetAnimation = function(self) return self.animation or "RegularTear6" end,
    GetFrame = function() return 2 end,
    Load = function(_, path) animationPath = path end,
    SetFrame = function(self, name, frame)
        self.animation = name
        selectedFrame = { name, frame }
    end,
    ReplaceSpritesheet = function(_, layer, path, loadGraphics)
        assert(layer == 0 and loadGraphics == true)
        sheet = path
    end,
}
local tear = {
    Position = vector(0, 0),
    CollisionDamage = 12,
    Scale = 1,
    InitSeed = 123,
    Velocity = vector(10, 0),
    SpawnerEntity = sourceFamiliar,
    GetData = function() return tearData end,
    GetSprite = function() return tearSprite end,
    ToTear = function(self) return self end,
    Remove = function(self) self.removed = true end,
    Die = dieTear,
}
callbacks[ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE](mod, tear)
assert(tearData.AscentionHolyChaliceBubble)
assert(math.abs(tear.CollisionDamage - 10.8) < 0.0001)
assert(math.abs(tear.Scale - math.sqrt(0.9)) < 0.0001)
assert(sheet == "gfx/projectiles/bubble_tear_projectile.png")
assert(animationPath == "gfx/projectiles/golden_tear_projectile.anm2")
assert(selectedFrame[1] == "RegularTear6" and selectedFrame[2] == 2)
local splitChild = {
    Position = vector(0, 0), Velocity = vector(5, 0),
    CollisionDamage = 6, Scale = 0.6, InitSeed = 891,
    SpawnerEntity = sourceFamiliar, TearFlags = 12345,
    GetData = function(self) self.data = self.data or {}; return self.data end,
    GetSprite = function() return tearSprite end,
}
tear.Visible = true
tearSprite.Scale = vector(1, 1)
local inheritedLaser
tear.Die = function(self)
    inheritedLaser = { Visible = self.Visible, Scale = tearSprite.Scale }
    dieTear(self)
    callbacks[ModCallbacks.MC_POST_FIRE_SPLIT_TEAR](mod, splitChild, self, 1)
end

local function npc(x, friendly)
    local target = {
        Type = 10,
        Position = vector(x, 0),
        Size = 0,
        damage = 0,
        ToNPC = function(self) return self end,
        IsActiveEnemy = function() return true end,
        IsDead = function() return false end,
        HasEntityFlags = function() return friendly end,
        TakeDamage = function(self, amount) self.damage = self.damage + amount end,
    }
    return target
end
local hit = npc(0, false)
local near = npc(30, false)
local far = npc(80, false)
local ally = npc(10, true)
Isaac.FindInRadius = function() return { hit, near, far, ally } end

local onDamage = callbacks[ModCallbacks.MC_POST_ENTITY_TAKE_DMG]
onDamage(mod, hit, 12, 0, { Entity = tear })
assert(math.abs(hit.damage - 3.96) < 0.0001)
assert(math.abs(near.damage - 3.96) < 0.0001)
assert(far.damage == 0 and ally.damage == 0)
assert(tear.died and sounds == 1)
assert(splitChild:GetData().AscentionHolyChaliceBubble
    and splitChild.TearFlags == 12345
    and math.abs(splitChild.CollisionDamage - 5.4) < 0.0001,
    "native split child must retain its flags and damage")
assert(#splashSprites == 1
    and splashSprites[1].path == "gfx/projectiles/bubble_tear_splash.anm2"
    and not splashSprites[1].sheet,
    "ordinary bubble must use the blue custom splash")
callbacks[ModCallbacks.MC_POST_RENDER](mod)
assert(splashSprites[1].frame == 0 and splashSprites[1].renderCount == 1)
assert(callbacks[ModCallbacks.MC_PRE_EFFECT_RENDER](mod,
    { Position = tear.Position }) == false,
    "vanilla tear splash must be suppressed at the bubble")
frame = 13
callbacks[ModCallbacks.MC_POST_RENDER](mod)
assert(splashSprites[1].frame == 13)
frame = 14
callbacks[ModCallbacks.MC_POST_RENDER](mod)
assert(splashSprites[1].renderCount == 2,
    "custom splash must stop after its last frame")
frame = 0
assert(tear.Visible == false and tearSprite.Scale.X == 1,
    "popped bubble must hide without zeroing the sprite used by native death")
assert(inheritedLaser.Visible and inheritedLaser.Scale.X == 1,
    "Brimstone lasers spawned by native death must remain visible")
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](mod, tear)
assert(tear.removed and tear.Visible == false,
    "popped tear must stay hidden if the engine updates it again")
onDamage(mod, hit, 12, 0, { Entity = tear })
assert(math.abs(hit.damage - 3.96) < 0.0001)

local lethalTear = {
    Position = vector(0, 0),
    SpawnerEntity = sourceFamiliar,
    CollisionDamage = 12,
    Scale = 1,
    InitSeed = 234,
    Velocity = vector(10, 0),
    GetData = function(self) self.data = self.data or {}; return self.data end,
    GetSprite = function() return tearSprite end,
    ToTear = function(self) return self end,
    Remove = function(self) self.removed = true end,
    Die = dieTear,
}
callbacks[ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE](mod, lethalTear)
hit.IsActiveEnemy = function() return false end
hit.IsDead = function() return true end
onDamage(mod, hit, 12, 0, { Entity = lethalTear })
assert(lethalTear.removed and sounds == 2)
assert(math.abs(near.damage - 7.92) < 0.0001)

local function probeBubble(multiplierSeed)
    rngValue = multiplierSeed
    local probe = {
        Position = vector(0, 0), Velocity = vector(10, 0),
        CollisionDamage = 12, Scale = 1, InitSeed = 456,
        SpawnerEntity = sourceFamiliar,
        GetData = function(self) self.data = self.data or {}; return self.data end,
        GetSprite = function() return tearSprite end,
        ToTear = function(self) return self end,
        Remove = function(self) self.removed = true end,
        Die = dieTear,
    }
    callbacks[ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE](mod, probe)
    return probe
end
local weak = probeBubble(0)
assert(math.abs(weak.CollisionDamage - 2.4) < 0.0001)
assert(math.abs(weak.Scale - 0.55) < 0.0001)
local strong = probeBubble(1)
assert(math.abs(strong.CollisionDamage - 19.2) < 0.0001)
assert(math.abs(strong.Scale - math.sqrt(1.6)) < 0.0001)
rngValue = 0.5

player.FireTear = function(self, position, velocity)
    local shot = {
        InitSeed = 345 + #shots, CollisionDamage = self.Damage, Scale = 1,
        Velocity = velocity, Position = position, SpawnerEntity = self,
        GetData = function(self) self.data = self.data or {}; return self.data end,
        GetSprite = function() return tearSprite end,
        ResetSpriteScale = function(self, force)
            self.scaleReset = true
            self.scaleResetForced = force
        end,
        Remove = function(self) self.removed = true end,
        Die = dieTear,
    }
    shots[#shots + 1] = shot
    return shot
end
local inputHook = callbacks[ModCallbacks.MC_INPUT_ACTION]
assert(inputHook(mod, player, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_SHOOTRIGHT) == 0)
assert(inputHook(mod, player, InputHook.IS_ACTION_PRESSED,
    ButtonAction.ACTION_SHOOTRIGHT) == false)
for _, familiarItem in ipairs({ CollectibleType.COLLECTIBLE_INCUBUS,
    CollectibleType.COLLECTIBLE_TWISTED_PAIR }) do
    player.items[familiarItem] = true
    assert(inputHook(mod, player, InputHook.GET_ACTION_VALUE,
        ButtonAction.ACTION_SHOOTRIGHT) == 0,
        "native player and familiar input must be blocked during bubble stream")
    local nativeTear = { SpawnerEntity = player, Visible = true,
        GetData = function(self)
            self.data = self.data or {}
            return self.data
        end,
        Remove = function(self) self.removed = true end }
    callbacks[ModCallbacks.MC_POST_FIRE_TEAR](mod, nativeTear)
    assert(nativeTear.removed,
        "native tear must be removed when familiars use their own stream")
    player.items[familiarItem] = nil
end
for tick = 0, 8 do
    frame = tick
    callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](mod, player)
end
assert(#shots == 3, "base Chalice must shoot one bubble per stream tick")
assert(player.headDirection == Direction.RIGHT)
assert(player.costume == 91 and player.costumeAdds == 1)
player.MaxFireDelay = 19
for tick = 9, 35 do
    frame = tick
    callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](mod, player)
end
assert(#shots == 6, "slower fire rate must slow the bubble stream")
player.MaxFireDelay = 1
for tick = 36, 43 do
    frame = tick
    callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](mod, player)
end
assert(#shots == 14, "faster fire rate must speed up the bubble stream")
local timed = shots[1]
assert(math.abs(timed.CollisionDamage - 10.8) < 0.0001)
local flightHeight = timed.Height
assert(flightHeight <= -20, "bubble must start above the floor")
local reachedRange
for age = 1, 200 do
    timed.Position = vector(timed.Position.x + timed.Velocity.x,
        timed.Position.y + timed.Velocity.y)
    timed.Height = -1
    timed.FallingSpeed = 2
    timed.FallingAcceleration = 1
    far.Position = timed.Position
    callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](mod, timed)
    if not timed.removed then
        assert(timed.Height == flightHeight and timed.FallingSpeed == 0
            and timed.FallingAcceleration == 0,
            "bubble must stay airborne until it pops")
    end
    if age == 14 then
        assert(timed.Velocity:LengthSquared() > 0,
            "bubble must decelerate instead of stopping abruptly")
        assert(not timed.removed, "range must not be replaced by a fixed lifetime")
    end
    if timed:GetData().AscentionHolyChaliceBubble.travel >= player.TearRange then
        reachedRange = reachedRange or age
        assert(timed.Velocity:LengthSquared() == 0,
            "bubble should pause only after reaching player range")
    end
    if timed.removed then break end
end
assert(reachedRange and timed.died,
    "airborne expiry must use native tear death for split modifiers")
assert(math.abs(far.damage - 3.96) < 0.0001)
assert(math.abs(timed.CollisionDamage - 10.8) < 0.0001,
    "damage must only be randomized once")

local update = function(tick)
    frame = tick
    callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](mod, player)
end
local brimBalls = {}
synergyModule.FireBrimBall = function(_, position, direction, itemId)
    assert(itemId == 9, "Brimstone volley needs the collectible RNG id")
    brimBalls[#brimBalls + 1] = { position = position, direction = direction }
end
local adopted = {}
synergyModule.AdoptTechX = function(_, laser, brimstone)
    adopted[#adopted + 1] = { laser = laser, brimstone = brimstone }
end
local function charged(mode, start)
    holdingAttack = true
    for tick = start, start + 16 do update(tick) end
    holdingAttack = false
    player.nativeShots = player.nativeShots + 1
    update(start + 17)
end
player.MaxFireDelay = 9
player.weaponKind = WeaponType.WEAPON_BRIMSTONE
player.items[CollectibleType.COLLECTIBLE_BRIMSTONE] = true
assert(inputHook(mod, player, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_SHOOTRIGHT) == nil,
    "native charge input must reach the weapon and its chargebar")
charged("brimstone", 44)
assert(#brimBalls == 0, "Brimstone ball must follow native laser fire")
assert(player.costume == nil,
    "Chalice head must not layer over Brimstone costume")
local nativeLaser = { SpawnerEntity = player, Position = vector(0, 0),
    Velocity = vector(1, 0),
    GetScale = function() return 1 end,
    Remove = function(self) self.removed = true end }
nativeLaser.Child = { Visible = true,
    Remove = function(self) self.removed = true end }
callbacks[ModCallbacks.MC_POST_FIRE_BRIMSTONE](mod, nativeLaser)
assert(#brimBalls == 1,
    "each native Brimstone laser must produce a Chalice ball")
assert(not nativeLaser.removed and nativeLaser.Child.Visible,
    "native Brimstone beam must survive alongside the Chalice ball")
player:GetData().HolyChaliceFiringCustom = true
local customLaser = { SpawnerEntity = player,
    Remove = function(self) self.removed = true end }
callbacks[ModCallbacks.MC_POST_FIRE_BRIMSTONE](mod, customLaser)
assert(not customLaser.removed and #brimBalls == 1,
    "Chalice's own laser must not recursively spawn balls")
player:GetData().HolyChaliceFiringCustom = nil
player.items[CollectibleType.COLLECTIBLE_BRIMSTONE] = nil
player.weaponKind = WeaponType.WEAPON_TECH_X
player.items[CollectibleType.COLLECTIBLE_TECH_X] = true
charged("techx", 70)
assert(#brimBalls == 1, "Tech X must not be replaced by a Brimstone ball")
assert(player.costume == nil,
    "Chalice head must not layer over Tech X costume")
local nativeRings = {
    { SpawnerEntity = player }, { SpawnerEntity = player },
    { SpawnerEntity = player },
}
for _, ring in ipairs(nativeRings) do
    callbacks[ModCallbacks.MC_POST_FIRE_TECH_X_LASER](mod, ring)
    assert(not ring.removed, "native multishot ring must survive")
end
assert(#adopted == 3 and adopted[1].laser == nativeRings[1]
    and adopted[3].laser == nativeRings[3],
    "each native Tech X multishot ring must receive Chalice behavior")
player.items[CollectibleType.COLLECTIBLE_BRIMSTONE] = true
player.weaponKind = WeaponType.WEAPON_LASER
charged("brim_techx", 100)
assert(player.costume == nil)
assert(#shots == 14, "charged laser synergies must not add stream bubbles")
local comboRing = { SpawnerEntity = player }
callbacks[ModCallbacks.MC_POST_FIRE_TECH_X_LASER](mod, comboRing)
assert(not comboRing.removed and adopted[4].laser == comboRing
    and adopted[4].brimstone,
    "Brimstone + Tech X must keep the native combo ring")

player.items[CollectibleType.COLLECTIBLE_TECH_X] = nil
player.weaponKind = WeaponType.WEAPON_BRIMSTONE
local secondLaser = { SpawnerEntity = player, Position = vector(0, 0),
    Velocity = vector(0, 1), Remove = function(self) self.removed = true end }
callbacks[ModCallbacks.MC_POST_FIRE_BRIMSTONE](mod, secondLaser)
assert(#brimBalls == 2 and not secondLaser.removed,
    "Brimstone multishot must process every native laser")
player.items[CollectibleType.COLLECTIBLE_HAEMOLACRIA] = true
for _ = 1, 6 do
    local splitLaser = { SpawnerEntity = player, Position = vector(0, 0),
        Velocity = vector(1, 0), Visible = true,
        Remove = function(self) self.removed = true end }
    callbacks[ModCallbacks.MC_POST_FIRE_BRIMSTONE](mod, splitLaser)
    assert(splitLaser.Visible and not splitLaser.removed,
        "Haemolacria's native Brimstone lasers must remain visible")
end
assert(#brimBalls == 2,
    "Haemolacria split lasers must not each spawn a full overlapping ball volley")

player.items[CollectibleType.COLLECTIBLE_BRIMSTONE] = nil
player.items[CollectibleType.COLLECTIBLE_TECH_X] = nil
player.weaponKind = WeaponType.WEAPON_TEARS
player.items[CollectibleType.COLLECTIBLE_HAEMOLACRIA] = true
local redBubble = probeBubble(0.5)
assert(sheet == "gfx/projectiles/bubble_tear_projectile_red.png")
assert(redBubble:GetData().AscentionHolyChaliceBubble.bloodAnimation
    and selectedFrame[1]:match("^BloodTear%d+$"),
    "Haemolacria bubbles must use the engine's BloodTear animations")
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](mod, redBubble)
assert(selectedFrame[1]:match("^BloodTear%d+$"),
    "bubble updates must not switch a blood tear back to RegularTear")
callbacks[ModCallbacks.MC_POST_TEAR_DEATH](mod, redBubble)
assert(splashSprites[#splashSprites].sheet
    == "gfx/projectiles/bubble_tear_splash_red.png",
    "red bubble must use the red splash")
player.items[CollectibleType.COLLECTIBLE_BRIMSTONE] = true
local beforeBurstBalls = #brimBalls
local nativeSprite = {
    Scale = vector(1, 1),
    GetAnimation = function() return "RegularTear6" end,
    GetFrame = function() return 0 end,
    Load = function() error("must not replace the source sprite") end,
    SetFrame = function() error("must not change the source animation") end,
    ReplaceSpritesheet = function() error("must not replace the source sheet") end,
}
local brimBloodTear = {
    Position = vector(0, 0), Velocity = vector(10, 0),
    CollisionDamage = 12, Scale = 1, InitSeed = 789, Visible = true,
    SpawnerEntity = player,
    GetData = function(self) self.data = self.data or {}; return self.data end,
    GetSprite = function() return nativeSprite end,
    ToTear = function(self) return self end,
    Die = function(self)
        assert(self.Visible, "native source must stay visible during split")
        self.died = true
    end,
}
callbacks[ModCallbacks.MC_POST_FIRE_SPLIT_TEAR](mod, brimBloodTear, redBubble)
local overlay = brimBloodTear:GetData().AscentionHolyChaliceBubble.renderSprite
assert(overlay and overlay.sheet == "gfx/projectiles/bubble_tear_projectile_red.png"
    and overlay.animation:match("^BloodTear%d+$"),
    "Brimstone blood tear needs a separate bubble render sprite")
assert(callbacks[ModCallbacks.MC_PRE_TEAR_RENDER](mod, brimBloodTear) == false
    and overlay.renderCount == 1,
    "overlay must replace only the visible tear render")
onDamage(mod, hit, 12, 0, { Entity = brimBloodTear })
assert(brimBloodTear.died and brimBloodTear.Visible)
assert(#brimBalls == beforeBurstBalls,
    "split child must not trigger another Brimstone ball volley")
assert(callbacks[ModCallbacks.MC_PRE_TEAR_RENDER](mod, brimBloodTear) == false
    and overlay.renderCount == 1,
    "popped bubble must not render or hide its native source")
local primary = {
    Position = vector(0, 0), Velocity = vector(10, 0),
    CollisionDamage = 12, Scale = 1, InitSeed = 790, Visible = true,
    SpawnerEntity = player,
    GetData = function(self) self.data = self.data or {}; return self.data end,
    GetSprite = function() return nativeSprite end,
    ToTear = function(self) return self end,
    Die = function(self) self.died = true end,
}
callbacks[ModCallbacks.MC_POST_FIRE_SPLIT_TEAR](mod, primary, redBubble)
primary:GetData().AscentionHolyChaliceBubble.splitChild = nil
onDamage(mod, hit, 12, 0, { Entity = primary })
assert(#brimBalls == beforeBurstBalls + 1,
    "primary burst must restore exactly one Chalice Brimstone volley")
player.items[CollectibleType.COLLECTIBLE_BRIMSTONE] = nil
player.items[CollectibleType.COLLECTIBLE_HAEMOLACRIA] = nil

local function stream(item, copies, expected, start)
    player.items[item] = copies
    holdingAttack = true
    local before = #shots
    update(start)
    assert(#shots - before == expected)
    player.items[item] = nil
end
stream(CollectibleType.COLLECTIBLE_INNER_EYE, 1, 3, 130)
stream(CollectibleType.COLLECTIBLE_MUTANT_SPIDER, 1, 8, 140)
stream(CollectibleType.COLLECTIBLE_20_20, 1, 2, 150)
stream(CollectibleType.COLLECTIBLE_THE_WIZ, 1, 2, 160)
assert(shots[#shots - 1].Velocity.Y < 0 and shots[#shots].Velocity.Y > 0)
stream(CollectibleType.COLLECTIBLE_INNER_EYE, 2, 5, 170)
stream(CollectibleType.COLLECTIBLE_MUTANT_SPIDER, 2, 14, 180)
local originalRng = player.GetCollectibleRNG
local randomValues = { 0, 1, 0.25, 0.75, 0.4, 0.6 }
player.GetCollectibleRNG = function()
    local index = 0
    return {
        RandomInt = function() return 2 end,
        RandomFloat = function()
            index = index + 1
            return randomValues[(index - 1) % #randomValues + 1]
        end,
    }
end
player.items[CollectibleType.COLLECTIBLE_INNER_EYE] = true
local clustered = #shots
update(185)
assert(#shots == clustered + 9, "Inner Eye needs three RNG clusters")
assert(shots[clustered + 1].Position.Y ~= shots[clustered + 2].Position.Y,
    "tears within one cluster need random spatial offsets")
assert(shots[clustered + 1].Velocity.Y ~= shots[clustered + 2].Velocity.Y,
    "cluster tears need independent trajectory jitter")
player.items[CollectibleType.COLLECTIBLE_INNER_EYE] = nil
player.GetCollectibleRNG = originalRng

player.items[CollectibleType.COLLECTIBLE_DR_FETUS] = true
rngValue = 0.1
local bombBubble = probeBubble(0.1)
onDamage(mod, hit, 12, 0, { Entity = bombBubble })
assert(#bombs == 1)
player.items[CollectibleType.COLLECTIBLE_DR_FETUS] = nil
rngValue = 0.5

player.items[CollectibleType.COLLECTIBLE_MONSTROS_LUNG] = true
holdingAttack = false
update(190)
assert(player.costume == nil,
    "Chalice head must not layer over Monstro's Lung costume")
local nativeTear = { SpawnerEntity = player,
    Remove = function(self) self.removed = true end }
callbacks[ModCallbacks.MC_POST_FIRE_TEAR](mod, nativeTear)
assert(nativeTear.removed, "native Monstro tears must be replaced")
local before = #shots
charged("monstro", 200)
assert(sheet == "gfx/projectiles/bubble_tear_projectile_red.png",
    "Monstro's Lung must select the red bubble sheet")
assert(#shots == before + 4, "Monstro charge must fire one big and three to six small bubbles")
assert(shots[before + 1].Scale > shots[before + 2].Scale)
assert(shots[before + 1].scaleResetForced
    and shots[before + 2].scaleResetForced,
    "Monstro bubble sprite sizes must be recalculated after scaling")
assert(math.abs(shots[before + 1].CollisionDamage - 14.4) < 0.0001)
local normalSmall = shots[before + 2]
player.GetCollectibleRNG = function()
    local high = false
    return { RandomInt = function() return 3 end,
        RandomFloat = function()
            high = not high
            return high and 0 or 1
        end }
end
before = #shots
charged("monstro", 220)
assert(#shots == before + 7,
    "Monstro RNG must vary the number of small bubbles from three to six")
assert(shots[before + 2].CollisionDamage
    ~= shots[before + 3].CollisionDamage,
    "small bubbles need independent damage rolls")
local minDamage, maxDamage = math.huge, 0
local minScale, maxScale = math.huge, 0
for index = before + 2, before + 7 do
    minDamage = math.min(minDamage, shots[index].CollisionDamage)
    maxDamage = math.max(maxDamage, shots[index].CollisionDamage)
    minScale = math.min(minScale, shots[index].Scale)
    maxScale = math.max(maxScale, shots[index].Scale)
end
assert(math.abs(minDamage - player.Damage * 0.65) < 0.0001
    and math.abs(maxDamage - player.Damage * 1.6) < 0.0001,
    "Monstro damage must range from 65% to 160%")
assert(minScale < maxScale, "Monstro bubble sizes must visibly vary")
assert(shots[before + 2].Scale ~= shots[before + 3].Scale,
    "Monstro size must follow its damage roll")
assert(selectedFrame[1] ~= "RegularTear6",
    "custom sheet must use scale-specific tear frames")
assert(normalSmall.Scale < shots[before + 1].Scale)
player.GetCollectibleRNG = originalRng
player.items[CollectibleType.COLLECTIBLE_INNER_EYE] = true
before = #shots
charged("monstro", 240)
assert(#shots == before + 8,
    "Inner Eye must increase Monstro's Lung bubbles, not replace its volley")
player.items[CollectibleType.COLLECTIBLE_INNER_EYE] = nil
player.items[CollectibleType.COLLECTIBLE_MONSTROS_LUNG] = nil

player.items[CollectibleType.COLLECTIBLE_C_SECTION] = true
before = #shots
charged("c_section", 230)
assert(#shots == before,
    "Chalice must not replace the native C Section attack")
local fetus = {
    Variant = TearVariant.FETUS, Position = vector(0, 0),
    Velocity = vector(10, 0), SpawnerEntity = player,
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end,
}
callbacks[ModCallbacks.MC_POST_FIRE_TEAR](mod, fetus)
assert(not fetus.removed and #shots == before + 3,
    "native fetus must survive and gain three supplemental bubbles")
assert(shots[before + 1]:GetData().AscentionHolyChaliceBubble)
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](mod, fetus)
assert(#shots == before + 3,
    "fallback update must not duplicate C Section bubbles")
player.items[CollectibleType.COLLECTIBLE_C_SECTION] = nil

player.items[CollectibleType.COLLECTIBLE_MOMS_KNIFE] = true
player.nativeCharge = 7.5
local knifeShots = 0
included["scripts.holy_chalice_knife"].Fire = function()
    knifeShots = knifeShots + 1
end
charged("knife", 260)
assert(knifeShots == 0, "knife must use its native weapon entity")
assert(math.abs(player:GetData().HolyChaliceKnifeThrowCharge - 0.5) < 0.0001,
    "partial native knife charge must be recorded for bubble volume")
player.items[CollectibleType.COLLECTIBLE_SOY_MILK] = true
holdingAttack = true
for tick = 290, 330 do update(tick) end
assert(knifeShots == 0, "native knife must fire without the custom volley")
local knife = { Position = vector(20, 0), SpawnerEntity = player,
    InitSeed = 741,
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end }
local knifeUpdate = callbacks[ModCallbacks.MC_POST_KNIFE_UPDATE]
before = #shots
knifeUpdate(mod, knife)
knife.Position = vector(40, 0)
knifeUpdate(mod, knife)
assert(#shots > before, "native knife must spawn bubbles at launch")
local knifeBubble = shots[before + 1]
local knifeData = knifeBubble:GetData().AscentionHolyChaliceBubble
assert(knifeData.keepMomentum and knifeData.range >= 180,
    "knife bubbles need longer range and constant-speed flight")
local speed = knifeBubble.Velocity:Length()
for _ = 1, 5 do
    knifeBubble.Position = knifeBubble.Position + knifeBubble.Velocity
    callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](mod, knifeBubble)
end
assert(math.abs(knifeBubble.Velocity:Length() - speed) < 0.0001,
    "knife bubbles must not brake immediately after launch")
player.items[CollectibleType.COLLECTIBLE_MOMS_KNIFE] = nil
player.items[CollectibleType.COLLECTIBLE_SOY_MILK] = nil
player.items[CollectibleType.COLLECTIBLE_TECHNOLOGY] = true
player.weaponKind = WeaponType.WEAPON_LASER
before = #shots
local techLaser = { Position = vector(0, 0), Velocity = vector(1, 0),
    SpawnerEntity = player }
callbacks[ModCallbacks.MC_POST_FIRE_TECH_LASER](mod, techLaser)
assert(#shots == before + 2 and not techLaser.removed,
    "Technology laser must remain native and add 2-5 bubbles")
player.items[CollectibleType.COLLECTIBLE_TECHNOLOGY] = nil
player.items[CollectibleType.COLLECTIBLE_TECHNOLOGY_2] = true
player.weaponKind = WeaponType.WEAPON_TEARS
local tech2Tear = player:FireTear(vector(0, 0), vector(8, 0))
callbacks[ModCallbacks.MC_POST_FIRE_TEAR](mod, tech2Tear)
assert(tech2Tear:GetData().AscentionHolyChaliceBubble,
    "Technology 2 must preserve and convert the player's normal tear")
before = #shots
frame = 400
callbacks[ModCallbacks.MC_POST_LASER_UPDATE](mod, techLaser)
callbacks[ModCallbacks.MC_POST_LASER_UPDATE](mod, techLaser)
assert(#shots == before + 1 and not techLaser.removed,
    "Technology 2 must keep its laser and add a throttled bubble stream")
frame = 408
callbacks[ModCallbacks.MC_POST_LASER_UPDATE](mod, techLaser)
assert(#shots == before + 2)
player.items[CollectibleType.COLLECTIBLE_TECHNOLOGY_2] = nil
player.items[CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE] = true
local ludo = { SpawnerEntity = player, Position = vector(20, 0),
    Velocity = vector(0, 0),
    HasTearFlags = function(_, flag)
        return flag == TearFlags.TEAR_LUDOVICO
    end,
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end }
before = #shots
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](mod, ludo)
frame = 428
callbacks[ModCallbacks.MC_POST_TEAR_UPDATE](mod, ludo)
assert(#shots == before + 2,
    "Ludovico's native tear must periodically release radial bubbles")
player.items[CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE] = nil
local familiar = { Player = player,
    ToPlayer = function() return nil end,
    ToFamiliar = function(self) return self end }
local familiarTear = {
    InitSeed = 999, CollisionDamage = 4, Scale = 1,
    Position = vector(0, 0), Velocity = vector(8, 0),
    SpawnerEntity = player, Parent = familiar,
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end,
    GetSprite = function() return tearSprite end,
}
callbacks[ModCallbacks.MC_POST_FIRE_TEAR](mod, familiarTear)
assert(not familiarTear.removed and familiarTear:GetData().AscentionHolyChaliceBubble,
    "familiar tear must be converted before player-tear suppression")
callbacks[ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE](mod,
    familiarTear)
assert(familiarTear:GetData().AscentionHolyChaliceBubble,
    "Incubus and Twisted Pair tears must inherit Chalice bubbles")
player.items[CollectibleType.COLLECTIBLE_MONSTROS_LUNG] = true
local familiarMonstro = {
    InitSeed = 1001, CollisionDamage = 4, Scale = 1,
    Position = vector(0, 0), Velocity = vector(8, 0),
    SpawnerEntity = familiar,
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end,
    GetSprite = function() return tearSprite end,
}
callbacks[ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE](mod,
    familiarMonstro)
assert(familiarMonstro:GetData().AscentionHolyChaliceBubble,
    "familiar Monstro's Lung projectiles must become bubbles")
player.items[CollectibleType.COLLECTIBLE_MONSTROS_LUNG] = nil
player.items[CollectibleType.COLLECTIBLE_C_SECTION] = true
local familiarFetus = {
    Variant = TearVariant.FETUS, Position = vector(0, 0),
    Velocity = vector(8, 0), SpawnerEntity = familiar,
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end,
}
before = #shots
callbacks[ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE](mod,
    familiarFetus)
assert(not familiarFetus.removed and #shots == before + 3,
    "familiar C Section fetus must survive with supplemental bubbles")
player.items[CollectibleType.COLLECTIBLE_C_SECTION] = nil
player.items[CollectibleType.COLLECTIBLE_BRIMSTONE] = true
player.weaponKind = WeaponType.WEAPON_BRIMSTONE
before = #shots
callbacks[ModCallbacks.MC_POST_FAMILIAR_FIRE_BRIMSTONE](mod,
    { Position = vector(0, 0), Velocity = vector(1, 0),
        SpawnerEntity = familiar })
assert(#shots == before + 2,
    "familiar Brimstone must keep its beam and add bubbles")
player.items[CollectibleType.COLLECTIBLE_BRIMSTONE] = nil
player.weaponKind = WeaponType.WEAPON_TEARS
local huge = {
    Position = vector(0, 0), Velocity = vector(10, 0),
    CollisionDamage = 12, Scale = 100, InitSeed = 500,
    SpawnerEntity = sourceFamiliar,
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end,
    GetSprite = function() return tearSprite end,
    ToTear = function(self) return self end,
    Remove = function(self) self.removed = true end,
    Die = dieTear,
}
callbacks[ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE](mod, huge)
assert(huge.Scale <= 2.55,
    "Haemolacria-size bubbles must not cover the screen")
onDamage(mod, hit, 12, 0, { Entity = huge })
assert(splashSprites[#splashSprites].Scale.x <= 1,
    "bubble pop effect must have a bounded visual size")
frame = 400
callbacks[ModCallbacks.MC_PRE_USE_ITEM](mod,
    CollectibleType.COLLECTIBLE_TAMMYS_HEAD, nil, player)
local firstTammyShot
for index = 0, 9 do
    local direction = Vector.FromAngle(index * 36)
    local shot = player:FireTear(player.Position, direction * 10)
    shot.CollisionDamage = 37
    shot.TearFlags = 12345
    callbacks[ModCallbacks.MC_POST_FIRE_TEAR](mod, shot)
    assert(not shot.removed and shot:GetData().AscentionHolyChaliceBubble,
        "Tammy's Head must retain its ten native radial tears")
    assert(shot.TearFlags == 12345
        and math.abs(shot.CollisionDamage - 33.3) < 0.001,
        "Tammy tears must keep their native flags and bonus damage")
    assert(math.abs(shot.Velocity.X - direction.X * 10) < 0.001
        and math.abs(shot.Velocity.Y - direction.Y * 10) < 0.001,
        "Tammy's Head radial formation must not be randomized")
    firstTammyShot = firstTammyShot or shot
end
callbacks[ModCallbacks.MC_POST_USE_ITEM](mod,
    CollectibleType.COLLECTIBLE_TAMMYS_HEAD, nil, player)
local ordinaryShot = player:FireTear(player.Position, vector(10, 0))
callbacks[ModCallbacks.MC_POST_FIRE_TEAR](mod, ordinaryShot)
assert(ordinaryShot.removed and not ordinaryShot:GetData().AscentionHolyChaliceBubble,
    "ordinary player tears must still be suppressed after Tammy's Head")
assert(firstTammyShot:GetData().AscentionHolyChaliceBubble.angleSpread == 0)
player.items = { [CollectibleType.COLLECTIBLE_INCUBUS] = true,
    [CollectibleType.COLLECTIBLE_TWISTED_PAIR] = true }
player.weaponKind = WeaponType.WEAPON_TEARS
for _, variant in ipairs({ FamiliarVariant.INCUBUS,
    FamiliarVariant.TWISTED_BABY }) do
    frame = frame + 10
    local familiar = {
        Player = player, Variant = variant, Position = vector(20, 0),
        GetData = function(self)
            self.data = self.data or {}
            return self.data
        end,
        FireProjectile = function(self, aim)
            local shot = player:FireTear(self.Position, aim * 10)
            shot.SpawnerEntity = self
            shot.Parent = self
            return shot
        end,
        PlayShootAnim = function(self, direction)
            self.shootDirection = direction
        end,
    }
    local before = #shots
    callbacks[ModCallbacks.MC_FAMILIAR_UPDATE](mod, familiar)
    assert(#shots == before + 1
        and shots[#shots]:GetData().AscentionHolyChaliceBubble
        and familiar.shootDirection == Direction.RIGHT,
        "Incubus and Twisted Baby must emit their own bubbles")
    familiar.ShootDirection = Direction.DOWN
    familiar.LastDirection = Direction.DOWN
    callbacks[ModCallbacks.MC_PRE_FAMILIAR_RENDER](mod, familiar)
    assert(familiar.ShootDirection == Direction.RIGHT
        and familiar.LastDirection == Direction.RIGHT
        and familiar.shootDirection == Direction.RIGHT,
        "render must restore the facing of the familiar's own shot")
end
player.items = {
    [CollectibleType.COLLECTIBLE_BRIMSTONE] = true,
    [CollectibleType.COLLECTIBLE_HAEMOLACRIA] = true,
    [CollectibleType.COLLECTIBLE_TECHNOLOGY] = true,
}
player.weaponKind = WeaponType.WEAPON_LASER
assert(inputHook(mod, player, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_SHOOTRIGHT) == 0,
    "Technology must not switch blood Brimstone bubbles to native fire")
local beforeQuadruple = #shots
update(1000)
assert(#shots > beforeQuadruple
    and shots[#shots]:GetData().AscentionHolyChaliceBubble.renderSprite,
    "Brimstone + Haemolacria + Technology must fire Chalice bubbles")
player.items[CollectibleType.COLLECTIBLE_HAEMOLACRIA] = nil
assert(inputHook(mod, player, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_SHOOTRIGHT) == nil,
    "Technology + Brimstone without Haemolacria keeps native charge")
player.items[CollectibleType.COLLECTIBLE_TECHNOLOGY] = nil
player.items[CollectibleType.COLLECTIBLE_TECH_X] = true
player.items[CollectibleType.COLLECTIBLE_HAEMOLACRIA] = true
player.weaponKind = WeaponType.WEAPON_TECH_X
assert(inputHook(mod, player, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_SHOOTRIGHT) == 0,
    "Tech X must not replace blood Brimstone bubbles with native rings")
local beforeTechX = #shots
update(1020)
assert(#shots > beforeTechX
    and shots[#shots]:GetData().AscentionHolyChaliceBubble.renderSprite,
    "Brimstone + Haemolacria + Tech X must fire Chalice bubbles")
player.items[CollectibleType.COLLECTIBLE_TECHNOLOGY] = true
assert(inputHook(mod, player, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_SHOOTRIGHT) == 0,
    "Technology and Tech X together must keep the blood bubble route")
player.items[CollectibleType.COLLECTIBLE_HAEMOLACRIA] = nil
assert(inputHook(mod, player, InputHook.GET_ACTION_VALUE,
    ButtonAction.ACTION_SHOOTRIGHT) == nil,
    "Brimstone + Tech X without Haemolacria keeps native rings")
print("holy chalice: OK")
