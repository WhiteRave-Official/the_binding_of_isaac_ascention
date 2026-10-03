local GoldenEye = {}

local json = require "json"

local TARGET_REFRESH_INTERVAL = 6
local MAX_TARGET_DISTANCE = 1000.0
local FORMATION_RADIUS = 60.0
local FORMATION_ARC_DEGREES = 100.0
local EYE_SCALE = 0.8
local SHOT_WINDUP_TICKS = 4.0
local SHOT_RECOIL_TICKS = 4
local CHARGE_WINDUP_START = 0.85
local HOP_HEIGHT = 4.0
local ROOM_ENTRY_DELAY = 20
local ROOM_ENTRY_DELAY_SPREAD = 10
local SHOT_INTERVAL_MIN = 2
local SHOT_INTERVAL_MAX = 5
local PROXY_VARIANT = FamiliarVariant.INCUBUS
local KILL_THRESHOLDS = { 100, 200, 300 }
local SAVE_KEY = "goldenEyeKills"

local DIRECTION_DATA = {
    Down = { idle = "IdleDown", shoot = "ShootDown" },
    Up = { idle = "IdleUp", shoot = "ShootUp" },
    Left = { idle = "IdleLeft", shoot = "ShootLeft" },
    Right = { idle = "IdleRight", shoot = "ShootRight" },
}

local state = {
    kills = {},
}

local function getPlayerIndex(player)
    for index = 0, Game():GetNumPlayers() - 1 do
        if GetPtrHash(Isaac.GetPlayer(index)) == GetPtrHash(player) then
            return index
        end
    end
    return 0
end

local function getKills(player)
    return state.kills[tostring(getPlayerIndex(player))] or 0
end

local function getEyeCount(player)
    if not player:HasCollectible(GoldenEye.ItemId) then
        return 0
    end

    local count = 1
    local kills = getKills(player)
    for _, threshold in ipairs(KILL_THRESHOLDS) do
        if kills >= threshold then
            count = count + 1
        end
    end
    return count
end

local function save(mod)
    mod:SaveData(json.encode({ [SAVE_KEY] = state.kills }))
end

local function load(mod, continued)
    state.kills = {}
    if continued and mod:HasData() then
        local ok, decoded = pcall(json.decode, mod:LoadData())
        if ok and type(decoded) == "table" and type(decoded[SAVE_KEY]) == "table" then
            state.kills = decoded[SAVE_KEY]
        end
    end
end

local function getDirectionName(vector)
    if math.abs(vector.X) > math.abs(vector.Y) then
        return vector.X < 0 and "Left" or "Right"
    end
    return vector.Y < 0 and "Up" or "Down"
end

local function isValidTarget(entity)
    local npc = entity and entity:ToNPC()
    return npc ~= nil
        and npc:Exists()
        and not npc:IsDead()
        and npc:IsActiveEnemy(false)
        and npc:IsVulnerableEnemy()
        and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

local function findTargetFrom(position)
    local bestTarget = nil
    local bestDistance = MAX_TARGET_DISTANCE * MAX_TARGET_DISTANCE
    local bestSeed = math.huge

    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if isValidTarget(entity) then
            local distance = position:DistanceSquared(entity.Position)
            if distance < bestDistance
                or (distance == bestDistance and entity.InitSeed < bestSeed)
            then
                bestTarget = entity
                bestDistance = distance
                bestSeed = entity.InitSeed
            end
        end
    end
    return bestTarget
end

local function findTarget(familiar)
    return findTargetFrom(familiar.Position)
end

local function getData(familiar)
    local data = familiar:GetData()
    if not data.GoldenEye then
        data.GoldenEye = {
            target = nil,
            targetRefresh = 0,
            direction = "Down",
            proxy = nil,
            proxyShots = 0,
            recoilTicks = 0,
        }
    end
    return data.GoldenEye
end

local function getProxy(data)
    local proxy = data.proxy and data.proxy.Ref
    if proxy and proxy:Exists() then
        return proxy:ToFamiliar()
    end
    data.proxy = nil
    return nil
end

local function deterministicDelay(familiar, sequence, minimum, maximum)
    local roomSeed = Game():GetRoom():GetSpawnSeed()
    local range = maximum - minimum + 1
    local mixed = math.abs(familiar.InitSeed + roomSeed * 3 + sequence * 17)
    return minimum + mixed % range
end

local function resetProxyRoomDelay(proxy)
    local proxyData = proxy:GetData()
    proxyData.GoldenEyeRoomDelay = ROOM_ENTRY_DELAY
        + deterministicDelay(proxy, 0, 0, ROOM_ENTRY_DELAY_SPREAD)
end

local function addShotInterval(proxy)
    local proxyData = proxy:GetData()
    proxyData.GoldenEyeShotSequence = (proxyData.GoldenEyeShotSequence or 0) + 1

    local weapon = proxy:GetWeapon()
    if weapon then
        local extraDelay = deterministicDelay(
            proxy,
            proxyData.GoldenEyeShotSequence,
            SHOT_INTERVAL_MIN,
            SHOT_INTERVAL_MAX
        )
        weapon:SetFireDelay(math.max(0.0, weapon:GetFireDelay()) + extraDelay)
    end
end
local function spawnProxy(familiar, data)
    local proxy = Isaac.Spawn(
        EntityType.ENTITY_FAMILIAR,
        PROXY_VARIANT,
        0,
        familiar.Position,
        Vector.Zero,
        familiar.Player
    ):ToFamiliar()

    local proxyData = proxy:GetData()
    proxyData.GoldenEyeWeaponProxy = true
    proxyData.GoldenEyeOwner = EntityPtr(familiar)
    proxyData.GoldenEyeShotSequence = 0
    resetProxyRoomDelay(proxy)
    proxy.Player = familiar.Player
    -- Keep the native familiar chain player-owned; eye ownership lives in GoldenEyeOwner.
    proxy.Parent = familiar.Player
    proxy.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    proxy.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    proxy:SetShadowSize(0)

    data.proxy = EntityPtr(proxy)
    data.proxyShots = proxy:GetActiveWeaponNumFired()
    return proxy
end

local function ensureProxy(familiar, data)
    return getProxy(data) or spawnProxy(familiar, data)
end

local function getProxyOwner(proxy)
    local owner = proxy:GetData().GoldenEyeOwner
    local entity = owner and owner.Ref
    if entity and entity:Exists() then
        return entity:ToFamiliar()
    end
    return nil
end

local function getFormationIndex(familiar)
    local familiars = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, GoldenEye.FamiliarVariant)) do
        local other = entity:ToFamiliar()
        if other and other.Player
            and GetPtrHash(other.Player) == GetPtrHash(familiar.Player)
        then
            familiars[#familiars + 1] = other
        end
    end

    table.sort(familiars, function(a, b)
        return a.InitSeed < b.InitSeed
    end)

    for index, other in ipairs(familiars) do
        if GetPtrHash(other) == GetPtrHash(familiar) then
            return index, #familiars
        end
    end
    return 1, math.max(1, #familiars)
end

local function updateFormation(familiar)
    local index, count = getFormationIndex(familiar)
    local centerAngle = 270.0
    local angle = centerAngle
    if count > 1 then
        local arcStart = centerAngle - FORMATION_ARC_DEGREES * 0.5
        angle = arcStart + ((index - 1) / (count - 1)) * FORMATION_ARC_DEGREES
    end

    familiar.Position = familiar.Player.Position
        + Vector.FromAngle(angle) * FORMATION_RADIUS
    familiar.Velocity = Vector.Zero
end

local function playAnimation(familiar, data, shooting)
    local animations = DIRECTION_DATA[data.direction]
    local sprite = familiar:GetSprite()
    local desired = shooting and animations.shoot or DIRECTION_DATA.Down.idle

    if shooting then
        data.shootAnimation = desired
        sprite:Play(desired, true)
    elseif not sprite:IsPlaying(desired) then
        sprite:Play(desired, true)
    end
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function updateShotDeformation(familiar, data, proxy, hasTarget)
    local stretch = 0.0
    local weapon = proxy and proxy:GetWeapon()
    local firing = hasTarget and familiar.Player:GetData().GoldenEyeFireInput

    if firing and weapon then
        local maxCharge = weapon:GetMaxCharge()
        if maxCharge > 0.0 then
            local chargeProgress = clamp(weapon:GetCharge() / maxCharge, 0.0, 1.0)
            stretch = clamp(
                (chargeProgress - CHARGE_WINDUP_START) / (1.0 - CHARGE_WINDUP_START),
                0.0,
                1.0
            )
        else
            local fireDelay = math.max(0.0, weapon:GetFireDelay())
            stretch = 1.0 - clamp(fireDelay / SHOT_WINDUP_TICKS, 0.0, 1.0)
        end
    end

    local scaleX = EYE_SCALE * (1.0 - 0.10 * stretch)
    local scaleY = EYE_SCALE * (1.0 + 0.22 * stretch)
    local hop = HOP_HEIGHT * stretch

    if data.recoilTicks > 0 then
        local recoil = data.recoilTicks / SHOT_RECOIL_TICKS
        scaleX = scaleX * (1.0 + 0.10 * recoil)
        scaleY = scaleY * (1.0 - 0.12 * recoil)
        hop = hop + HOP_HEIGHT * 0.35 * recoil
        data.recoilTicks = data.recoilTicks - 1
    end

    familiar.SpriteScale = Vector(scaleX, scaleY)
    familiar.SpriteOffset = Vector(0.0, -hop)
end
local function updateTarget(familiar, data)
    data.targetRefresh = data.targetRefresh - 1
    if data.targetRefresh <= 0 or not isValidTarget(data.target) then
        data.target = findTarget(familiar)
        data.targetRefresh = TARGET_REFRESH_INTERVAL
    end
end

local function refreshFamiliars(player)
    player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
    player:EvaluateItems()
end

local function crossedThreshold(oldValue, newValue)
    for _, threshold in ipairs(KILL_THRESHOLDS) do
        if oldValue < threshold and newValue >= threshold then
            return true
        end
    end
    return false
end

local function isShootAction(action)
    return action == ButtonAction.ACTION_SHOOTLEFT
        or action == ButtonAction.ACTION_SHOOTRIGHT
        or action == ButtonAction.ACTION_SHOOTUP
        or action == ButtonAction.ACTION_SHOOTDOWN
end

local function actionDirection(action)
    if action == ButtonAction.ACTION_SHOOTLEFT then
        return Vector(-1, 0)
    elseif action == ButtonAction.ACTION_SHOOTRIGHT then
        return Vector(1, 0)
    elseif action == ButtonAction.ACTION_SHOOTUP then
        return Vector(0, -1)
    elseif action == ButtonAction.ACTION_SHOOTDOWN then
        return Vector(0, 1)
    end
    return nil
end

local function aimMatchesAction(aim, action)
    local direction = actionDirection(action)
    if not direction or not aim or aim:LengthSquared() == 0 then
        return false
    end

    if math.abs(aim.X) > math.abs(aim.Y) then
        return direction.X == (aim.X < 0 and -1 or 1)
    end
    return direction.Y == (aim.Y < 0 and -1 or 1)
end

local function findPlayerProxy(player)
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, PROXY_VARIANT)) do
        local proxy = entity:ToFamiliar()
        if proxy and proxy:GetData().GoldenEyeWeaponProxy
            and proxy.Player
            and GetPtrHash(proxy.Player) == GetPtrHash(player)
        then
            return proxy
        end
    end
    return nil
end

local function updateAutoFire(player)
    local playerData = player:GetData()
    if not player:HasCollectible(GoldenEye.ItemId) then
        playerData.GoldenEyeAim = nil
        playerData.GoldenEyeFireInput = nil
        playerData.GoldenEyeReleaseFrames = nil
        if playerData.GoldenEyeBlockedShooting then
            playerData.GoldenEyeBlockedShooting = nil
            player:SetCanShoot(true)
            player:UpdateCanShoot()
        end
        return
    end

    playerData.GoldenEyeBlockedShooting = true
    player:SetCanShoot(false)

    local target = findTargetFrom(player.Position)
    if not target then
        playerData.GoldenEyeAim = nil
        playerData.GoldenEyeFireInput = false
        return
    end

    playerData.GoldenEyeAim = target.Position - player.Position
    local proxy = findPlayerProxy(player)
    local weapon = proxy and proxy:GetWeapon()
    local maxCharge = weapon and weapon:GetMaxCharge() or 0

    if (playerData.GoldenEyeReleaseFrames or 0) > 0 then
        playerData.GoldenEyeReleaseFrames = playerData.GoldenEyeReleaseFrames - 1
        playerData.GoldenEyeFireInput = false
    elseif maxCharge > 0 and weapon:GetCharge() >= maxCharge then
        playerData.GoldenEyeReleaseFrames = 1
        playerData.GoldenEyeFireInput = false
    else
        playerData.GoldenEyeFireInput = true
    end
end

function GoldenEye.Register(mod, itemId, familiarVariant, weaponAdapter)
    GoldenEye.ItemId = itemId
    GoldenEye.FamiliarVariant = familiarVariant

    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
        load(mod, continued)
        for index = 0, Game():GetNumPlayers() - 1 do
            refreshFamiliars(Isaac.GetPlayer(index))
        end
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
        save(mod)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
        save(mod)
    end)

    mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cacheFlag)
        if cacheFlag == CacheFlag.CACHE_FAMILIARS then
            local rng = player:GetCollectibleRNG(itemId)
            local itemConfig = Isaac.GetItemConfig():GetCollectible(itemId)
            player:CheckFamiliar(familiarVariant, getEyeCount(player), rng, itemConfig)
        elseif cacheFlag == CacheFlag.CACHE_FIREDELAY
            and player:HasCollectible(itemId)
        then
            player.MaxFireDelay = (player.MaxFireDelay + 1.0) / 0.8 - 1.0
        elseif cacheFlag == CacheFlag.CACHE_TEARFLAG
            and player:HasCollectible(itemId)
        then
            player.TearFlags = player.TearFlags | TearFlags.TEAR_HOMING
        end
    end)

    mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, hook, action)
        local player = entity and entity:ToPlayer()
        if not player
            or not player:HasCollectible(itemId)
            or not isShootAction(action)
        then
            return
        end

        local playerData = player:GetData()
        local active = playerData.GoldenEyeFireInput
            and aimMatchesAction(playerData.GoldenEyeAim, action)

        if hook == InputHook.GET_ACTION_VALUE then
            return active and 1.0 or 0.0
        elseif hook == InputHook.IS_ACTION_PRESSED then
            return active
        elseif hook == InputHook.IS_ACTION_TRIGGERED then
            return false
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
        updateAutoFire(player)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, PROXY_VARIANT)) do
            local proxy = entity:ToFamiliar()
            if proxy and proxy:GetData().GoldenEyeWeaponProxy then
                resetProxyRoomDelay(proxy)
            end
        end
    end)
    mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, function(_, npc)
        if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            or not npc:IsActiveEnemy(true)
        then
            return
        end

        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            if player:HasCollectible(itemId) then
                local key = tostring(index)
                local oldValue = state.kills[key] or 0
                local newValue = oldValue + 1
                state.kills[key] = newValue

                if crossedThreshold(oldValue, newValue) then
                    refreshFamiliars(player)
                    save(mod)
                end
            end
        end
    end)

    mod:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, function(_, familiar)
        familiar.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        familiar.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        familiar.SpriteScale = Vector(EYE_SCALE, EYE_SCALE)
        familiar:GetSprite():Play("IdleDown", true)
        getData(familiar)
    end, familiarVariant)

    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, function(_, familiar)
        local data = getData(familiar)
        local sprite = familiar:GetSprite()

        updateFormation(familiar)
        updateTarget(familiar, data)
        local proxy = ensureProxy(familiar, data)

        if data.shootAnimation and sprite:IsFinished(data.shootAnimation) then
            data.shootAnimation = nil
        end

        if isValidTarget(data.target) then
            local aim = data.target.Position - familiar.Position
            data.direction = getDirectionName(aim)

            local shots = proxy:GetActiveWeaponNumFired()
            if shots ~= data.proxyShots then
                data.proxyShots = shots
                data.recoilTicks = SHOT_RECOIL_TICKS
                addShotInterval(proxy)
                playAnimation(familiar, data, true)
            elseif not data.shootAnimation then
                playAnimation(familiar, data, false)
            end
        else
            if not data.shootAnimation then
                playAnimation(familiar, data, false)
            end
        end

        updateShotDeformation(familiar, data, proxy, isValidTarget(data.target))
    end, familiarVariant)

    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, function(_, proxy)
        if not proxy:GetData().GoldenEyeWeaponProxy then
            return
        end

        local owner = getProxyOwner(proxy)
        if not owner or not owner.Player:HasCollectible(itemId) then
            proxy:Remove()
            return true
        end

        proxy.Position = owner.Position
        proxy.Velocity = Vector.Zero

        local proxyData = proxy:GetData()
        if (proxyData.GoldenEyeRoomDelay or 0) > 0 then
            proxyData.GoldenEyeRoomDelay = proxyData.GoldenEyeRoomDelay - 1
            return true
        end
    end, PROXY_VARIANT)

    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, function(_, proxy)
        if not proxy:GetData().GoldenEyeWeaponProxy then
            return
        end

        local owner = getProxyOwner(proxy)
        if owner then
            proxy.Position = owner.Position
            proxy.Velocity = Vector.Zero
        end
    end, PROXY_VARIANT)

    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_RENDER, function(_, proxy)
        if proxy:GetData().GoldenEyeWeaponProxy then
            return false
        end
    end, PROXY_VARIANT)

    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_PROJECTILE, function(_, tear)
        weaponAdapter.ScaleTear(tear)
    end, PROXY_VARIANT)

    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_BRIMSTONE, function(_, laser)
        weaponAdapter.ScaleLaser(laser)
    end, PROXY_VARIANT)

    mod:AddCallback(ModCallbacks.MC_POST_FAMILIAR_FIRE_TECH_LASER, function(_, laser)
        weaponAdapter.ScaleLaser(laser)
    end, PROXY_VARIANT)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TECH_X_LASER, function(_, laser)
        weaponAdapter.ScaleLaser(laser)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_BOMB, function(_, bomb)
        weaponAdapter.ScaleBomb(bomb)
    end)

    mod:AddCallback(ModCallbacks.MC_POST_FIRE_KNIFE, function(_, knife)
        weaponAdapter.ScaleKnife(knife)
    end)
end

return GoldenEye

