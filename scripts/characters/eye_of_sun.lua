local EyeOfSun = {}

local GEBURAH = Isaac.GetPlayerTypeByName("Geburah")
local STATE_KEY = "AscentionEyeOfSun"
local GOLDEN_TEAR_KEY = "AscentionGeburahGoldenTear"
local OLD_GOD_TEAR_KEY = "AscentionOldGodEyeTear"
local TEAR_ANIMATION = "gfx/projectiles/golden_tear_projectile.anm2"
local SPLASH_ANIMATION = "gfx/projectiles/golden_tear_splash.anm2"
local EYE_ANIMATION = "gfx/effects/effect_eye_of_sun.anm2"
local MAX_STACKS = 4
local OLD_GOD_DURATION = 150
local BOUNCE_FRAMES = 8
local MARK_DAMAGE_MULTIPLIER = 1.15
local MARK_SLOW_MULTIPLIER = 0.85
local MINI_HEAL_MULTIPLIER = 0.10
local SLOW_COLOR = Color(1, 1, 1, 1, 0, 0, 0)
local tearVisualSamples = 0
local recentGoldenDeaths = {}
local activeSplashes = {}
local markedTarget = nil

local function validEnemy(entity)
    local npc = entity and entity:ToNPC()
    return npc and npc:IsActiveEnemy(false) and npc:IsVulnerableEnemy()
        and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

local function miniIsaacSource(entity, depth)
    if not entity or depth > 4 then return false end
    local familiar = entity:ToFamiliar()
    if familiar and (familiar.Variant == FamiliarVariant.MINISAAC
        or familiar:GetData().AscentionMiniIsaacWeaponProxy) then
        return true
    end
    if entity:ToPlayer() then return false end
    return miniIsaacSource(entity.SpawnerEntity, depth + 1)
        or miniIsaacSource(entity.Parent, depth + 1)
end

local function miniIsaacTear(tear)
    local data = tear:GetData()
    return data.AscentionMiniIsaacNativeAimed
        or data.AscentionMiniIsaacSplitChild
        or miniIsaacSource(tear.SpawnerEntity, 0)
        or miniIsaacSource(tear.Parent, 0)
end

local function goldenSource(entity, depth)
    if not entity or depth > 4 then return false end
    local tear = entity:ToTear()
    if tear and tear:GetData()[GOLDEN_TEAR_KEY] then return true end
    if entity:ToPlayer() then return false end
    return goldenSource(entity.SpawnerEntity, depth + 1)
        or goldenSource(entity.Parent, depth + 1)
end

local function oldGodSource(entity, depth)
    if not entity or depth > 4 then return false end
    local tear = entity:ToTear()
    if tear and tear:GetData()[OLD_GOD_TEAR_KEY] then return true end
    if entity:ToPlayer() then return false end
    return oldGodSource(entity.SpawnerEntity, depth + 1)
        or oldGodSource(entity.Parent, depth + 1)
end

local function miniIsaacOwner(entity, depth)
    if not entity or depth > 4 then return nil end
    local data = entity:GetData()
    local owner = data.AscentionMiniIsaacOwner
    local mini = owner and owner.Ref
    if mini and mini:Exists() then return mini end

    local familiar = entity:ToFamiliar()
    if familiar then
        if familiar.Variant == FamiliarVariant.MINISAAC then return familiar end
        if data.AscentionMiniIsaacWeaponProxy then
            owner = data.AscentionMiniIsaacProxyOwner
            mini = owner and owner.Ref
            if mini and mini:Exists() then return mini end
        end
    end
    if entity:ToPlayer() then return nil end
    return miniIsaacOwner(entity.SpawnerEntity, depth + 1)
        or miniIsaacOwner(entity.Parent, depth + 1)
end

local function geburahMiniSource(source, extraSource)
    local mini = miniIsaacOwner(extraSource and extraSource.Entity, 0)
        or miniIsaacOwner(source and source.Entity, 0)
    local player = mini and mini.Player
    if mini and mini.Variant == FamiliarVariant.MINISAAC
        and player and player:GetPlayerType() == GEBURAH then
        return mini
    end
end

local function markTear(tear)
    if miniIsaacTear(tear) then return end
    if tear:GetData()[GOLDEN_TEAR_KEY] then return end
    tear:GetData()[GOLDEN_TEAR_KEY] = true
end

local function isGeburahTear(tear)
    if miniIsaacTear(tear) then return false end
    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    return player and player:GetPlayerType() == GEBURAH
end

local function updateTearVisual(tear)
    if tear:GetData().AscentionFlamingRoseTear
        and not tear:GetData()[OLD_GOD_TEAR_KEY] then return end
    local sprite = tear:GetSprite()
    local filename = sprite:GetFilename() or ""
    if filename:lower():match("golden_tear_projectile%.anm2$") then return end
    local animation = sprite:GetAnimation() or ""
    local frame = sprite:GetFrame()
    sprite:Load(TEAR_ANIMATION, true)
    if animation:match("^RegularTear%d+$") then
        sprite:SetFrame(animation, frame)
    else
        sprite:SetFrame("RegularTear6", 0)
    end
    if tearVisualSamples < 8 then
        tearVisualSamples = tearVisualSamples + 1
        Isaac.DebugString("[AscentionEyeOfSun] tear_sheet seed=" .. tostring(tear.InitSeed)
            .. " animation=" .. tostring(animation)
            .. " before=" .. tostring(filename)
            .. " after=" .. tostring(sprite:GetFilename()))
    end
end

local function newSprite()
    local sprite = Sprite()
    sprite:Load(EYE_ANIMATION, true)
    return sprite
end

function EyeOfSun.IsMarked(entity)
    local state = entity and entity:GetData()[STATE_KEY]
    return state and state.stacks >= MAX_STACKS
        and (not state.expiresAt or Game():GetFrameCount() < state.expiresAt)
        or false
end

function EyeOfSun.MarkOldGodTear(tear)
    markTear(tear)
    tear:GetData()[OLD_GOD_TEAR_KEY] = true
end

local function fullMark(entity, state, expiresAt)
    local previous = markedTarget and markedTarget.Ref
    if previous and previous:Exists()
        and GetPtrHash(previous) ~= GetPtrHash(entity) then
        previous:GetData()[STATE_KEY] = nil
    end
    state.stacks = MAX_STACKS
    state.bounce = BOUNCE_FRAMES
    state.expiresAt = expiresAt
    markedTarget = EntityPtr(entity)
end

function EyeOfSun.Register(mod)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
        markedTarget = nil
    end)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, function(_, tear)
        if isGeburahTear(tear) then markTear(tear) end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
        if isGeburahTear(tear) then markTear(tear) end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
        if tear.FrameCount <= 2 then
            if miniIsaacTear(tear) then
                tear:GetData()[GOLDEN_TEAR_KEY] = nil
                return
            end
            if isGeburahTear(tear) then markTear(tear) end
        end
        if tear:GetData()[GOLDEN_TEAR_KEY] then updateTearVisual(tear) end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_SPLIT_TEAR, function(_, child, source)
        if child and source and not miniIsaacTear(child)
            and not miniIsaacTear(source) and goldenSource(source, 0) then
            markTear(child)
            if oldGodSource(source, 0) then
                child:GetData()[OLD_GOD_TEAR_KEY] = true
            end
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_DEATH, function(_, tear)
        if not tear:GetData()[GOLDEN_TEAR_KEY] then return end
        local sprite = Sprite()
        sprite:Load(SPLASH_ANIMATION, true)
        local frame = Game():GetFrameCount()
        activeSplashes[#activeSplashes + 1] = {
            frame = frame, position = tear.Position, sprite = sprite,
        }
        recentGoldenDeaths[#recentGoldenDeaths + 1] = {
            frame = frame, position = tear.Position,
        }
        if #recentGoldenDeaths > 32 then table.remove(recentGoldenDeaths, 1) end
    end)

    local function hideVanillaSplash(_, effect)
        if goldenSource(effect.SpawnerEntity, 0)
            or goldenSource(effect.Parent, 0)
        then return false end
        local frame = Game():GetFrameCount()
        for i = #recentGoldenDeaths, 1, -1 do
            local death = recentGoldenDeaths[i]
            if frame - death.frame > 2 then
                table.remove(recentGoldenDeaths, i)
            elseif effect.Position:DistanceSquared(death.position) <= 256 then
                return false
            end
        end
    end
    for _, variant in ipairs({
        EffectVariant.TEAR_POOF_A,
        EffectVariant.TEAR_POOF_B,
        EffectVariant.TEAR_POOF_SMALL,
        EffectVariant.TEAR_POOF_VERYSMALL,
    }) do
        mod:AddCallback(ModCallbacks.MC_PRE_EFFECT_RENDER,
            hideVanillaSplash, variant)
    end

    mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
        local frame = Game():GetFrameCount()
        for i = #activeSplashes, 1, -1 do
            local splash = activeSplashes[i]
            local age = frame - splash.frame
            if age < 0 or age >= 15 then
                table.remove(activeSplashes, i)
            else
                splash.sprite:SetFrame("Poof", age)
                splash.sprite:Render(Isaac.WorldToRenderPosition(splash.position))
            end
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
        activeSplashes = {}
        recentGoldenDeaths = {}
        markedTarget = nil
    end)

    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG,
        function(_, entity, damage, _, source, _, extraSource)
            if not EyeOfSun.IsMarked(entity) then return end
            local state = entity:GetData()[STATE_KEY]
            local mini = geburahMiniSource(source, extraSource)
            state.pendingHeal = mini and {
                mini = EntityPtr(mini), beforeHp = entity.HitPoints,
            } or nil
            return { Damage = damage * MARK_DAMAGE_MULTIPLIER }
        end, EntityType.ENTITY_NPC)

    mod:AddCallback(ModCallbacks.MC_POST_ENTITY_TAKE_DMG,
        function(_, entity, _, _, source, _, extraSource)
            local state = entity:GetData()[STATE_KEY]
            local pending = state and state.pendingHeal
            if pending then
                state.pendingHeal = nil
                local mini = pending.mini.Ref
                if mini and mini:Exists() and not mini:IsDead() then
                    local dealt = math.max(0, pending.beforeHp - entity.HitPoints)
                    mini.HitPoints = math.min(mini.MaxHitPoints,
                        mini.HitPoints + dealt * MINI_HEAL_MULTIPLIER)
                end
            end
            if not validEnemy(entity) then return end
            if not goldenSource(extraSource and extraSource.Entity, 0)
                and not goldenSource(source and source.Entity, 0) then return end

            local oldGodHit = oldGodSource(extraSource and extraSource.Entity, 0)
                or oldGodSource(source and source.Entity, 0)

            local data = entity:GetData()
            state = data[STATE_KEY]
            if not state then
                state = { stacks = 0, eye = newSprite(), fire = newSprite() }
                data[STATE_KEY] = state
            end
            if oldGodHit then
                fullMark(entity, state, Game():GetFrameCount() + OLD_GOD_DURATION)
            elseif state.stacks < MAX_STACKS then
                state.stacks = state.stacks + 1
                state.bounce = BOUNCE_FRAMES
                if state.stacks == MAX_STACKS then
                    fullMark(entity, state)
                end
            end
        end, EntityType.ENTITY_NPC)

    mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, function(_, npc)
        local state = npc:GetData()[STATE_KEY]
        if state and state.expiresAt
            and Game():GetFrameCount() >= state.expiresAt then
            npc:GetData()[STATE_KEY] = nil
            return
        end
        if state and state.stacks >= MAX_STACKS then
            npc:AddSlowing(EntityRef(npc), 2, MARK_SLOW_MULTIPLIER,
                SLOW_COLOR, true)
        end
        if state and state.bounce and state.bounce > 0 then
            state.bounce = state.bounce - 1
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_NPC_RENDER, function(_, npc, renderOffset)
        local state = npc:GetData()[STATE_KEY]
        if not state or npc:IsDead() then return end

        local bounce = (state.bounce or 0) / BOUNCE_FRAMES
        local scale = 1 + 0.25 * bounce
        local position = Isaac.WorldToRenderPosition(npc.Position + npc.PositionOffset)
            + renderOffset + Vector(0, -npc.Size - 22 - 3 * bounce)
        state.eye:SetFrame("Eye", state.stacks - 1)
        state.eye.Scale = Vector(scale, scale)
        state.eye:Render(position)
        if state.stacks == MAX_STACKS then
            state.fire:SetFrame("Fire", Game():GetFrameCount() % 14)
            state.fire.Scale = Vector(scale, scale)
            state.fire:Render(position)
        end
    end)
end

return EyeOfSun
