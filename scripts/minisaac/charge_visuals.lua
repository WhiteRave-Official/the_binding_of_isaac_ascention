local ChargeVisuals = {}

local STATE_KEY = "AscentionMiniIsaacChargeVisual"
local BODY_STATE_KEY = "AscentionMiniIsaacBodySheet"

local BLACK_BODY_SHEET = "gfx/familiar/minisaac_charge/familiar_minisaac_black.png"
local GEBURAH_BODY_SHEET = "gfx/familiar/minisaac/familiar_minisaac_geburah.png"
local GEBURAH_BLACK_BODY_SHEET = "gfx/familiar/minisaac/familiar_minisaac_geburah_black.png"
local DEFAULT_BODY_SHEET = "gfx/familiar/familiar_minisaac.png"
local RELEASE_FRAMES = 4
local RELEASE_SHOT_FRAMES = 2
local reportedFirstRender = false

local MONSTROS_LUNG = CollectibleType.COLLECTIBLE_MONSTROS_LUNG
local TECHNOLOGY = CollectibleType.COLLECTIBLE_TECHNOLOGY
local CHOCOLATE_MILK = CollectibleType.COLLECTIBLE_CHOCOLATE_MILK
local BRIMSTONE = CollectibleType.COLLECTIBLE_BRIMSTONE
local GEBURAH = Isaac.GetPlayerTypeByName("Geburah")

local COSTUME_SHEETS = {
    technology = {
        geburah = "familiar_minisaac_technology_costume_geburah.png",
        geburahBlack = "familiar_minisaac_technology_costume_geburah_black.png",
    },
    monstros_lung = {
        black = "familiar_minisaac_monsto's_lung_costume_black.png",
        geburah = "familiar_minisaac_monsto's_lung_costume_geburah.png",
        geburahBlack = "familiar_minisaac_monsto's_lung_costume_geburah_black.png",
    },
    brimstone = {
        geburah = "familiar_minisaac_brimstone_costume_geburah.png",
    },
    chocolate_milk = {
        black = "familiar_minisaac_chocolate_milk_costume_black.png",
        geburah = "familiar_minisaac_chocolate_milk_costume_geburah.png",
        geburahBlack = "familiar_minisaac_chocolate_milk_costume_geburah_black.png",
    },
}

local profiles = {
    {
        id = "technology_monstros_lung",
        costume = "technology",
        spritePath = "gfx/familiar/minisaac_charge/technology.anm2",
        releaseFrameCount = 1,
        matches = function(player)
            return player:HasCollectible(MONSTROS_LUNG)
                and player:HasCollectible(TECHNOLOGY)
        end,
    },
    {
        id = "technology_chocolate_milk",
        costume = "technology",
        spritePath = "gfx/familiar/minisaac_charge/technology.anm2",
        releaseFrameCount = 1,
        matches = function(player)
            return player:HasCollectible(CHOCOLATE_MILK)
                and player:HasCollectible(TECHNOLOGY)
        end,
    },
    {
        id = "monstros_lung",
        costume = "monstros_lung",
        weaponType = WeaponType.WEAPON_MONSTROS_LUNGS,
        spritePath = "gfx/familiar/minisaac_charge/monstros_lung.anm2",
        releaseFrameCount = 2,
    },
    {
        id = "brimstone",
        costume = "brimstone",
        weaponType = WeaponType.WEAPON_BRIMSTONE,
        spritePath = "gfx/familiar/minisaac_charge/brimstone.anm2",
        releaseFrameCount = 2,
    },
    {
        id = "chocolate_milk",
        costume = "chocolate_milk",
        spritePath = "gfx/familiar/minisaac_charge/chocolate_milk.anm2",
        releaseFrameCount = 2,
        matches = function(player)
            return player:HasCollectible(CHOCOLATE_MILK)
        end,
    },
    {
        id = "technology",
        costume = "technology",
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

local function isGeburah(player)
    return player and player:GetPlayerType() == GEBURAH
end

local function costumeSheet(profile, player)
    local variants = COSTUME_SHEETS[profile.costume]
    local black = player:HasCollectible(BRIMSTONE)
    local filename
    if isGeburah(player) then
        filename = black and variants.geburahBlack or variants.geburah
    elseif black then
        filename = variants.black
    end
    return filename and "gfx/familiar/minisaac_charge/" .. filename or nil
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
        beamActive = false,
        recoveryTimer = 0,
        lastShotFrame = -1,
    }
    data[STATE_KEY] = state
    return state
end

local function updateCostumeSheet(state, player)
    local sheet = costumeSheet(state.profile, player)
    if state.sheet == sheet then return end
    if sheet then
        state.sprite:ReplaceSpritesheet(0, sheet, true)
    else
        state.sprite:Load(state.profile.spritePath, true)
    end
    state.sheet = sheet
end

local function restoreBodySheet(familiar)
    local data = familiar:GetData()
    local bodyState = data[BODY_STATE_KEY]
    if not bodyState then return end

    local sprite = familiar:GetSprite()
    for layerId = 0, 1 do
        local originals = bodyState.originalSheets
        local original = originals and originals[layerId] or bodyState.originalSheet
        if original and (original:lower():match("familiar_minisaac_black%.png$")
            or original:lower():match("familiar_minisaac_geburah.*%.png$")) then
            original = DEFAULT_BODY_SHEET
        end
        if original then sprite:ReplaceSpritesheet(layerId, original, layerId == 1) end
    end
    data[BODY_STATE_KEY] = nil
end

local function updateBodySheet(familiar, player, profile)
    local data = familiar:GetData()
    local black = player and player:HasCollectible(BRIMSTONE)
    local sheet
    if isGeburah(player) then
        sheet = black and GEBURAH_BLACK_BODY_SHEET or GEBURAH_BODY_SHEET
    elseif profile and profile.id == "brimstone" then
        sheet = BLACK_BODY_SHEET
    end
    if not sheet then
        restoreBodySheet(familiar)
        return
    end

    local state = data[BODY_STATE_KEY]
    if state and state.sheet == sheet and state.originalSheets then return end
    local sprite = familiar:GetSprite()
    if not state then
        state = { originalSheets = {} }
        for layerId = 0, 1 do
            local layer = sprite:GetLayer(layerId)
            state.originalSheets[layerId] = layer and layer:GetSpritesheetPath()
        end
        data[BODY_STATE_KEY] = state
    elseif not state.originalSheets then
        state.originalSheets = {
            [0] = state.originalSheet,
            [1] = DEFAULT_BODY_SHEET,
        }
    end
    for layerId = 0, 1 do
        sprite:ReplaceSpritesheet(layerId, sheet, layerId == 1)
    end
    state.sheet = sheet
    if isGeburah(player) then
        local body = sprite:GetLayer(0)
        local head = sprite:GetLayer(1)
        Isaac.DebugString("[AscentionMiniIsaac] geburah_sheet mini="
            .. tostring(familiar.InitSeed) .. " body="
            .. tostring(body and body:GetSpritesheetPath()) .. " head="
            .. tostring(head and head:GetSpritesheetPath()))
    end
end
local function updateFamiliar(_, familiar)
    local player = familiar.Player
    local profile = player and getProfile(player)
    updateBodySheet(familiar, player, profile)
    if not profile then
        familiar:GetData()[STATE_KEY] = nil
        return
    end

    local state = getOrCreateState(familiar, profile)
    updateCostumeSheet(state, player)
    local data = familiar:GetData()
    state.fallbackCharge = nil
    state.fallbackMax = nil
    if profile.id == "technology_chocolate_milk" then
        local pointer = data.AscentionMiniIsaacProxy
        local proxy = pointer and pointer.Ref
        local weapon = proxy and proxy:Exists() and proxy:ToFamiliar():GetWeapon()
        if weapon and weapon:GetMaxCharge() <= 0 and AscentionNative then
            local diagnostics = AscentionNative.Diagnostics(proxy)
            state.fallbackCharge = diagnostics.chocolate_laser_charge
            state.fallbackMax = diagnostics.chocolate_laser_max
        end
    end
    local shotFrame = data.AscentionMiniIsaacLastShotFrame or -1
    local aim = data.AscentionMiniIsaacAim
    state.active = aim ~= nil and aim:LengthSquared() > 0.01
    if profile.id == "brimstone" then
        if data.AscentionMiniIsaacBrimstoneReleasing then
            state.beamActive = true
            state.recoveryTimer = 0
        elseif state.beamActive then
            state.beamActive = false
            state.recoveryTimer = RELEASE_SHOT_FRAMES
        elseif state.recoveryTimer > 0 then
            state.recoveryTimer = state.recoveryTimer - 1
        end
    else
        if state.releaseTimer > 0 then
            state.releaseTimer = state.releaseTimer - 1
        end
        if shotFrame ~= state.lastShotFrame
            and shotFrame >= Game():GetFrameCount() - 1 then
            state.releaseTimer = RELEASE_FRAMES
        end
    end

    if shotFrame ~= state.lastShotFrame
        and shotFrame >= Game():GetFrameCount() - 1 then
        local shot = data.AscentionMiniIsaacLastShotVelocity
        if shot and shot:LengthSquared() > 0.01 then
            if math.abs(shot.X) > math.abs(shot.Y) then
                state.direction = shot.X < 0 and Direction.LEFT or Direction.RIGHT
            else
                state.direction = shot.Y < 0 and Direction.UP or Direction.DOWN
            end
        end
    elseif not state.beamActive and state.recoveryTimer == 0
        and state.releaseTimer == 0 then
        if state.active then
            if math.abs(aim.X) > math.abs(aim.Y) then
                state.direction = aim.X < 0 and Direction.LEFT or Direction.RIGHT
            else
                state.direction = aim.Y < 0 and Direction.UP or Direction.DOWN
            end
        else
            state.direction = animationDirection(familiar, state.direction)
        end
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
    if profile.id == "brimstone" and state.beamActive then
        state.sprite:SetFrame("Release" .. facing, 0)
    elseif profile.id == "brimstone" and state.recoveryTimer > 0 then
        state.sprite:SetFrame("Release" .. facing, 1)
    elseif state.releaseTimer > 0 then
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
            if state.active and state.fallbackMax and state.fallbackMax > 0 then
                stage = math.min(3, math.floor(state.fallbackCharge
                    * 4 / state.fallbackMax))
            elseif state.active and weapon and weapon:GetMaxCharge() > 0 then
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
