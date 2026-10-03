local ChargeVisuals = {}

local STATE_KEY = "AscentionDynamicMinisaacChargeVisual"
local BODY_STATE_KEY = "AscentionDynamicMinisaacBodySheet"
local BLACK_BODY_SHEET = "gfx/familiar/minisaac_charge/familiar_minisaac_black.png"
local RELEASE_FRAMES = 4
local RELEASE_SHOT_FRAMES = 2
local reportedFirstRender = false
local enemyScanFrame = -1
local enemyPresent = false

local MONSTROS_LUNG = CollectibleType.COLLECTIBLE_MONSTROS_LUNG
local TECHNOLOGY = CollectibleType.COLLECTIBLE_TECHNOLOGY

local profiles = {
    {
        id = "technology_monstros_lung",
        spritePath = "gfx/familiar/minisaac_charge/technology.anm2",
        delayKey = "MONSTRO",
        baseDelay = 4,
        releaseFrameCount = 1,
        matches = function(player)
            return player:HasCollectible(MONSTROS_LUNG)
                and player:HasCollectible(TECHNOLOGY)
        end,
    },
    {
        id = "technology",
        weaponType = WeaponType.WEAPON_LASER,
        spritePath = "gfx/familiar/minisaac_charge/technology.anm2",
        staticCharge = true,
        releaseFrameCount = 1,
    },
    {
        id = "monstros_lung",
        weaponType = WeaponType.WEAPON_MONSTROS_LUNGS,
        spritePath = "gfx/familiar/minisaac_charge/monstros_lung.anm2",
        delayKey = "MONSTRO",
        baseDelay = 4,
        releaseFrameCount = 2,
    },
    {
        id = "brimstone",
        weaponType = WeaponType.WEAPON_BRIMSTONE,
        spritePath = "gfx/familiar/minisaac_charge/brimstone.anm2",
        delayKey = "BRIM",
        baseDelay = 4,
        releaseFrameCount = 2,
    },
}

local function isDynamicMinisaacsLoaded()
    return type(DynamicMinisaacContinued) == "table"
end

local function hasEnemyTarget()
    local frame = Game():GetFrameCount()
    if enemyScanFrame == frame then
        return enemyPresent
    end

    enemyScanFrame = frame
    enemyPresent = false
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if npc
            and npc:IsVulnerableEnemy()
            and not npc:IsDead()
            and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
        then
            enemyPresent = true
            break
        end
    end
    return enemyPresent
end

local function getProfile(player)
    for _, profile in ipairs(profiles) do
        local matches = profile.matches and profile.matches(player)
            or (profile.weaponType and player:HasWeaponType(profile.weaponType))
        if matches then
            return profile
        end
    end
end

local function getChargeDelay(profile, player)
    local dynamic = DynamicMinisaacContinued
    local delay = profile.baseDelay

    if dynamic and dynamic.TearDelayMult then
        delay = dynamic.TearDelayMult[profile.delayKey] or delay
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_CHOCOLATE_MILK) then
        local modifier = dynamic
            and dynamic.TearDelayModif
            and dynamic.TearDelayModif.CHOC
            or 2
        delay = delay * modifier
    end

    return math.max(1, delay)
end

local function directionName(direction)
    if direction == Direction.UP then
        return "Up"
    elseif direction == Direction.LEFT then
        return "Left"
    elseif direction == Direction.RIGHT then
        return "Right"
    end
    return "Down"
end

local function animationDirection(familiar, fallback)
    local animation = familiar:GetSprite():GetAnimation() or ""
    if animation:find("Up", 1, true) then
        return Direction.UP
    elseif animation:find("Left", 1, true) then
        return Direction.LEFT
    elseif animation:find("Right", 1, true) then
        return Direction.RIGHT
    elseif animation:find("Down", 1, true) then
        return Direction.DOWN
    end
    return fallback
end

local function isSpawnAnimation(familiar)
    local animation = familiar:GetSprite():GetAnimation() or ""
    return animation == "Appear" or animation:sub(1, 9) == "Transform"
end

local function getOrCreateState(familiar, profile)
    local data = familiar:GetData()
    local state = data[STATE_KEY]
    if state and state.profileId == profile.id then
        return state
    end

    local sprite = Sprite()
    sprite:Load(profile.spritePath, true)
    state = {
        profileId = profile.id,
        profile = profile,
        sprite = sprite,
        direction = Direction.DOWN,
        releaseTimer = 0,
        lastKeys = familiar.Keys or 0,
    }
    data[STATE_KEY] = state
    return state
end

local function restoreBodySheet(familiar)
    local data = familiar:GetData()
    local bodyState = data[BODY_STATE_KEY]
    if not bodyState then
        return
    end

    familiar:GetSprite():ReplaceSpritesheet(0, bodyState.originalSheet, true)
    data[BODY_STATE_KEY] = nil
end

local function updateBodySheet(familiar, profile)
    local data = familiar:GetData()
    if profile.id ~= "brimstone" then
        restoreBodySheet(familiar)
        return
    end

    if data[BODY_STATE_KEY] then
        return
    end

    local sprite = familiar:GetSprite()
    local layer = sprite:GetLayer(0)
    data[BODY_STATE_KEY] = {
        originalSheet = layer:GetSpritesheetPath(),
    }
    sprite:ReplaceSpritesheet(0, BLACK_BODY_SHEET, true)
end
local function updateFamiliar(_, familiar)
    if not isDynamicMinisaacsLoaded() then
        return
    end

    local player = familiar.Player
    local profile = player and getProfile(player)
    if not profile then
        familiar:GetData()[STATE_KEY] = nil
        restoreBodySheet(familiar)
        return
    end

    updateBodySheet(familiar, profile)
    local state = getOrCreateState(familiar, profile)
    state.hasEnemies = hasEnemyTarget()
    if state.hasEnemies and familiar.ShootDirection ~= Direction.NO_DIRECTION then
        state.direction = familiar.ShootDirection
    elseif not state.hasEnemies then
        state.direction = animationDirection(familiar, state.direction)
        state.releaseTimer = 0
    end

    if state.releaseTimer > 0 then
        state.releaseTimer = state.releaseTimer - 1
    end

    local keys = familiar.Keys or 0
    if state.hasEnemies and state.lastKeys > 0 and keys == 0 then
        state.releaseTimer = RELEASE_FRAMES
    elseif not state.hasEnemies then
        state.releaseTimer = 0
    end
    state.lastKeys = keys
end

local function renderFamiliar(_, familiar)
    local state = familiar:GetData()[STATE_KEY]
    if not state then
        return
    end

    local familiarSprite = familiar:GetSprite()
    local familiarColor = familiarSprite.Color

    if isSpawnAnimation(familiar) then
        return
    end

    local profile = state.profile
    local player = familiar.Player

    if not reportedFirstRender then
        reportedFirstRender = true
        Isaac.DebugString("[Ascention] Dynamic Minisaac charge costume render active: " .. state.profileId)
    end

    local facing = directionName(state.direction)
    if state.releaseTimer > 0 then
        local frame = 0
        if (profile.releaseFrameCount or 1) > 1 then
            local elapsed = RELEASE_FRAMES - state.releaseTimer
            frame = elapsed < RELEASE_SHOT_FRAMES and 0 or 1
        end
        state.sprite:SetFrame("Release" .. facing, frame)
    else
        local stage = 0
        if not profile.staticCharge then
            local delay = getChargeDelay(profile, player)
            local keys = state.hasEnemies and (familiar.Keys or 0) or 0
            local progress = math.min(math.max(keys, 0), delay - 1)
            stage = math.min(3, math.floor(progress * 4 / delay))
        end
        state.sprite:SetFrame("Charge" .. facing, stage)
    end

    state.sprite.Scale = familiarSprite.Scale
    state.sprite.Color = familiarColor

    local position = Isaac.WorldToRenderPosition(familiar.Position + familiar.PositionOffset)
    state.sprite:Render(position)
end

local function markTechnologyShot(_, tear)
    local familiar = tear.SpawnerEntity and tear.SpawnerEntity:ToFamiliar()
    if not familiar or familiar.Variant ~= FamiliarVariant.MINISAAC then
        return
    end

    local player = familiar.Player
    local profile = player and getProfile(player)
    if not profile or profile.id ~= "technology" then
        return
    end

    local state = getOrCreateState(familiar, profile)
    if familiar.ShootDirection ~= Direction.NO_DIRECTION then
        state.direction = familiar.ShootDirection
    end
    state.releaseTimer = RELEASE_FRAMES
end
function ChargeVisuals.Register(mod)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, markTechnologyShot)
    mod:AddCallback(
        ModCallbacks.MC_FAMILIAR_UPDATE,
        updateFamiliar,
        FamiliarVariant.MINISAAC
    )
    mod:AddCallback(
        ModCallbacks.MC_POST_FAMILIAR_RENDER,
        renderFamiliar,
        FamiliarVariant.MINISAAC
    )
end

return ChargeVisuals
