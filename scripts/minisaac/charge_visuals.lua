local ChargeVisuals = {}

local STATE_KEY = "AscentionMiniIsaacChargeVisual"
local BODY_STATE_KEY = "AscentionMiniIsaacBodySheet"
local BLACK_BODY_SHEET = "gfx/familiar/minisaac_charge/familiar_minisaac_black.png"
local RELEASE_FRAMES = 4
local RELEASE_SHOT_FRAMES = 2
local reportedFirstRender = false

local MONSTROS_LUNG = CollectibleType.COLLECTIBLE_MONSTROS_LUNG
local TECHNOLOGY = CollectibleType.COLLECTIBLE_TECHNOLOGY

local profiles = {
    {
        id = "technology_monstros_lung",
        spritePath = "gfx/familiar/minisaac_charge/technology.anm2",
        releaseFrameCount = 1,
        matches = function(player)
            return player:HasCollectible(MONSTROS_LUNG)
                and player:HasCollectible(TECHNOLOGY)
        end,
    },
    {
        id = "monstros_lung",
        weaponType = WeaponType.WEAPON_MONSTROS_LUNGS,
        spritePath = "gfx/familiar/minisaac_charge/monstros_lung.anm2",
        releaseFrameCount = 2,
    },
    {
        id = "brimstone",
        weaponType = WeaponType.WEAPON_BRIMSTONE,
        spritePath = "gfx/familiar/minisaac_charge/brimstone.anm2",
        releaseFrameCount = 2,
    },
    {
        id = "technology",
        weaponType = WeaponType.WEAPON_LASER,
        spritePath = "gfx/familiar/minisaac_charge/technology.anm2",
        staticCharge = true,
        releaseFrameCount = 1,
    },
}

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
    return math.max(1, math.floor(player.MaxFireDelay + 1))
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
        lastShotFrame = -1,
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
    local player = familiar.Player
    local profile = player and getProfile(player)
    if not profile then
        familiar:GetData()[STATE_KEY] = nil
        restoreBodySheet(familiar)
        return
    end

    updateBodySheet(familiar, profile)
    local state = getOrCreateState(familiar, profile)
    local data = familiar:GetData()
    local shotFrame = data.AscentionMiniIsaacLastShotFrame or -1
    local aim = data.AscentionMiniIsaacAim
    state.active = aim ~= nil and aim:LengthSquared() > 0.01
    if state.active then
        if math.abs(aim.X) > math.abs(aim.Y) then
            state.direction = aim.X < 0 and Direction.LEFT or Direction.RIGHT
        else
            state.direction = aim.Y < 0 and Direction.UP or Direction.DOWN
        end
    else
        state.direction = animationDirection(familiar, state.direction)
        state.releaseTimer = 0
    end

    if state.releaseTimer > 0 then
        state.releaseTimer = state.releaseTimer - 1
    end

    if state.active and shotFrame ~= state.lastShotFrame then
        state.releaseTimer = RELEASE_FRAMES
    elseif not state.active then
        state.releaseTimer = 0
    end
    state.lastShotFrame = shotFrame
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
        Isaac.DebugString("[Ascention] Mini Isaac charge costume render active: " .. state.profileId)
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
            local pointer = familiar:GetData().AscentionMiniIsaacProxy
            local proxy = pointer and pointer.Ref
            local weapon = proxy and proxy:Exists() and proxy:ToFamiliar():GetWeapon()
            if state.active and weapon and weapon:GetMaxCharge() > 0 then
                stage = math.min(3, math.floor(weapon:GetCharge()
                    * 4 / weapon:GetMaxCharge()))
            elseif state.active then
                local delay = getChargeDelay(profile, player)
                local progress = math.min(math.max(delay - familiar.FireCooldown, 0), delay - 1)
                stage = math.min(3, math.floor(progress * 4 / delay))
            end
        end
        state.sprite:SetFrame("Charge" .. facing, stage)
    end

    state.sprite.Scale = familiarSprite.Scale
    state.sprite.Color = familiarColor

    local position = Isaac.WorldToRenderPosition(familiar.Position + familiar.PositionOffset)
    state.sprite:Render(position)
end

function ChargeVisuals.Register(mod)
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
