local Router = {}

local PROXY_KEY = "AscentionMiniIsaacWeaponProxy"
local OWNER_KEY = "AscentionMiniIsaacProxyOwner"
local TARGET_REFRESH_INTERVAL = 6
local native = AscentionNative

local HELD_KNIFE_OFFSETS = {
    [Direction.DOWN] = Vector(0, 8),
    [Direction.UP] = Vector(0, -8),
    [Direction.LEFT] = Vector(-8, 0),
    [Direction.RIGHT] = Vector(8, 0),
}

local HELD_KNIFE_ROTATIONS = {
    [Direction.DOWN] = 0,
    [Direction.UP] = 180,
    [Direction.LEFT] = 90,
    [Direction.RIGHT] = -90,
}

local function knifeFacing(mini)
    local aim = mini:GetData().AscentionMiniIsaacAim
    if aim and aim:LengthSquared() > 0.01 then
        if math.abs(aim.X) > math.abs(aim.Y) then
            return aim.X < 0 and Direction.LEFT or Direction.RIGHT
        end
        return aim.Y < 0 and Direction.UP or Direction.DOWN
    end

    local animation = mini:GetSprite():GetAnimation() or ""
    if animation:find("Up", 1, true) then return Direction.UP end
    if animation:find("Left", 1, true) then return Direction.LEFT end
    if animation:find("Right", 1, true) then return Direction.RIGHT end
    return Direction.DOWN
end

local function heldKnifeSprite(knife)
    local data = knife:GetData()
    local source = knife:GetSprite()
    local filename = source:GetFilename()
    local layer = source:GetLayer(0)
    local sheet = layer and layer:GetSpritesheetPath()
    local state = data.AscentionMiniIsaacHeldSprite
    if state and state.filename == filename and state.sheet == sheet then
        return state.sprite
    end

    local sprite = Sprite()
    sprite:Load(filename, true)
    if sheet then sprite:ReplaceSpritesheet(0, sheet, true) end
    sprite:SetFrame("Idle", 0)
    data.AscentionMiniIsaacHeldSprite = { sprite = sprite, filename = filename, sheet = sheet }
    return sprite
end

local function renderHeldKnife(knife, mini, direction)
    local sprite = heldKnifeSprite(knife)
    sprite.Rotation = HELD_KNIFE_ROTATIONS[direction]
    -- Flip before rotation so the left-facing blade mirrors the right-facing one.
    sprite.FlipY = direction == Direction.LEFT
    sprite.Scale = Vector(knife.Scale * knife.SpriteScale.X,
        knife.Scale * knife.SpriteScale.Y)
    sprite:Render(Isaac.WorldToRenderPosition(mini.Position + mini.PositionOffset)
        + HELD_KNIFE_OFFSETS[direction])
end

local function active()
    return native and native.abi == 1
        and type(DynamicMinisaacContinued) ~= "table"
end

local function validMini(entity)
    return entity and entity:Exists()
        and entity.Type == EntityType.ENTITY_FAMILIAR
        and entity.Variant == FamiliarVariant.MINISAAC
end

local function validTarget(entity)
    return entity and entity:Exists() and entity:IsActiveEnemy(false)
        and entity:IsVulnerableEnemy()
        and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

local function ownerOf(proxy)
    local pointer = proxy:GetData()[OWNER_KEY]
    local owner = pointer and pointer.Ref
    return validMini(owner) and owner:ToFamiliar() or nil
end

local function proxyOf(mini)
    local pointer = mini:GetData().AscentionMiniIsaacProxy
    local proxy = pointer and pointer.Ref
    return proxy and proxy:Exists() and proxy:ToFamiliar() or nil
end

local function removeProxy(mini)
    local proxy = proxyOf(mini)
    if proxy then
        native.UnregisterProxy(proxy)
        proxy:Remove()
    end
    mini:GetData().AscentionMiniIsaacProxy = nil
end

local function ensureProxy(mini)
    local proxy = proxyOf(mini)
    if proxy then
        if not native.IsRegistered(proxy) then native.RegisterProxy(proxy) end
        return proxy
    end
    proxy = Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.INCUBUS,
        0, mini.Position, Vector.Zero, mini.Player):ToFamiliar()
    proxy.Player = mini.Player
    proxy.Parent = mini.Player
    proxy.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    proxy.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    proxy:SetShadowSize(0)
    proxy:GetData()[PROXY_KEY] = true
    proxy:GetData()[OWNER_KEY] = EntityPtr(mini)
    mini:GetData().AscentionMiniIsaacProxy = EntityPtr(proxy)
    if not native.RegisterProxy(proxy) then
        Isaac.DebugString("[AscentionMiniIsaac] native rejected proxy variant="
            .. tostring(proxy.Variant) .. " seed=" .. tostring(proxy.InitSeed))
        proxy:Remove()
        mini:GetData().AscentionMiniIsaacProxy = nil
        return nil
    end
    Isaac.DebugString("[AscentionMiniIsaac] native proxy=" .. tostring(proxy.InitSeed)
        .. " mini=" .. tostring(mini.InitSeed))
    return proxy
end

local function targetFor(mini)
    local data = mini:GetData()
    local frame = Game():GetFrameCount()
    local target = data.AscentionMiniIsaacTarget
    if frame < (data.AscentionMiniIsaacTargetRefresh or 0)
        and validTarget(target) then return target end

    local bestDistance = math.huge
    local bestSeed = math.huge
    target = nil
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if validTarget(entity) then
            local distance = mini.Position:DistanceSquared(entity.Position)
            if distance < bestDistance
                or (distance == bestDistance and entity.InitSeed < bestSeed) then
                target = entity
                bestDistance = distance
                bestSeed = entity.InitSeed
            end
        end
    end
    data.AscentionMiniIsaacTarget = target
    data.AscentionMiniIsaacTargetRefresh = frame + TARGET_REFRESH_INTERVAL
    return target
end

function Router.IsManaging(mini)
    return active() and validMini(mini)
end

function Router.IsProxy(entity)
    local familiar = entity and entity:ToFamiliar()
    return familiar and familiar:GetData()[PROXY_KEY] or false
end

function Router.Register(mod)
    if not native or native.abi ~= 1 then
        Isaac.DebugString("[AscentionMiniIsaac] native module unavailable; manual combat remains active")
        return
    end

    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
        native.ResetProxies()
    end)

    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, function(_, mini)
        if not Router.IsManaging(mini) then
            local data = mini:GetData()
            if data.AscentionMiniIsaacOriginalDepthOffset ~= nil then
                mini.DepthOffset = data.AscentionMiniIsaacOriginalDepthOffset
                data.AscentionMiniIsaacOriginalDepthOffset = nil
            end
            data.AscentionMiniIsaacHeldKnife = nil
            removeProxy(mini)
            return
        end
        local proxy = ensureProxy(mini)
        local data = mini:GetData()
        local weapon = proxy and proxy:GetWeapon()
        if weapon and weapon:GetWeaponType() == WeaponType.WEAPON_KNIFE then
            if data.AscentionMiniIsaacOriginalDepthOffset == nil then
                data.AscentionMiniIsaacOriginalDepthOffset = mini.DepthOffset
            end
            mini.DepthOffset = -100
        elseif data.AscentionMiniIsaacOriginalDepthOffset ~= nil then
            mini.DepthOffset = data.AscentionMiniIsaacOriginalDepthOffset
            data.AscentionMiniIsaacOriginalDepthOffset = nil
            data.AscentionMiniIsaacHeldKnife = nil
        else
            data.AscentionMiniIsaacHeldKnife = nil
        end
    end, FamiliarVariant.MINISAAC)

    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_UPDATE, function(_, proxy)
        if not Router.IsProxy(proxy) then return end
        local mini = ownerOf(proxy)
        if not active() or not mini or not mini.Player then
            native.UnregisterProxy(proxy)
            proxy:Remove()
            return true
        end
        proxy.Position = mini.Position
        proxy.Velocity = Vector.Zero
        local weapon = proxy:GetWeapon()
        local kind = weapon and weapon:GetWeaponType()
        if kind == WeaponType.WEAPON_KNIFE then
            local mainEntity = weapon:GetMainEntity()
            local knife = mainEntity and mainEntity:ToKnife()
            if not knife then return end
            local knifeData = knife:GetData()
            if not knifeData.AscentionMiniIsaacRenderOwner then
                knifeData.AscentionMiniIsaacRenderOwner = EntityPtr(mini)
                mini:GetData().AscentionMiniIsaacHeldKnife = EntityPtr(knife)
                Isaac.DebugString("[AscentionMiniIsaac] knife_render_bind knife="
                    .. tostring(knife.InitSeed) .. " mini=" .. tostring(mini.InitSeed)
                    .. " proxy=" .. tostring(proxy.InitSeed))
            end

            local data = mini:GetData()
            local proxyData = proxy:GetData()
            if not proxyData.AscentionMiniIsaacKnifeInitialized then
                proxyData.AscentionMiniIsaacKnifeInitialized = true
                knife:Reset()
            end
            if knife:IsFlying() then
                local launchFrame = proxyData.AscentionMiniIsaacKnifeFlightFrame
                if not launchFrame then
                    knife:Reset()
                    if knife:IsFlying() then return true end
                elseif Game():GetFrameCount() - launchFrame > 90 then
                    knife:Reset()
                    proxyData.AscentionMiniIsaacKnifeFlightFrame = nil
                end
                if knife:IsFlying() then return end
            end

            local target = targetFor(mini)
            local aim = target and (target.Position - mini.Position) or Vector.Zero
            data.AscentionMiniIsaacAim = target and aim or nil
            local charge = target and (proxyData.AscentionMiniIsaacKnifeCharge or 0) + 1 or 0
            proxyData.AscentionMiniIsaacKnifeCharge = charge
            if target and charge >= math.max(1, math.ceil(weapon:GetMaxCharge())) then
                proxyData.AscentionMiniIsaacKnifeCharge = 0
                knife.Position = mini.Position
                knife.Rotation = aim:GetAngleDegrees()
                knife:Shoot(1.0, math.max(40, mini.Player.TearRange))
                proxyData.AscentionMiniIsaacKnifeFlightFrame = Game():GetFrameCount()
                data.AscentionMiniIsaacLastShotFrame = Game():GetFrameCount()
                data.AscentionMiniIsaacLastShotVelocity = aim
            end
            return true
        end
        if kind == WeaponType.WEAPON_TECH_X then
            local target = targetFor(mini)
            local aim = target and (target.Position - mini.Position) or Vector.Zero
            local data = mini:GetData()
            data.AscentionMiniIsaacAim = target and aim or nil
            local fired, released = native.TickProxy(proxy, aim.X, aim.Y, target ~= nil)
            if fired then
                data.AscentionMiniIsaacLastShotFrame = Game():GetFrameCount()
                data.AscentionMiniIsaacLastShotVelocity = aim
            end
            local releaseSamples = data.AscentionMiniIsaacTechXReleases or 0
            if released and releaseSamples < 8 then
                data.AscentionMiniIsaacTechXReleases = releaseSamples + 1
                local state = native.Diagnostics(proxy)
                Isaac.DebugString("[AscentionMiniIsaac] tech_x_release frame="
                    .. tostring(Game():GetFrameCount())
                    .. " mini=" .. tostring(mini.InitSeed)
                    .. " engine_input=" .. tostring(state.release_input_x) .. ","
                    .. tostring(state.release_input_y)
                    .. " same_frame=" .. tostring(state.release_input_same_frame)
                    .. " owner_head=" .. tostring(state.owner_head)
                    .. " native_rings=" .. tostring(state.release_tech_x))
            end
            local chargeSamples = data.AscentionMiniIsaacTechXChargeSamples or 0
            if target and chargeSamples < 8 and Game():GetFrameCount() % 45 == 0 then
                data.AscentionMiniIsaacTechXChargeSamples = chargeSamples + 1
                local state = native.Diagnostics(proxy)
                Isaac.DebugString("[AscentionMiniIsaac] charged_weapon frame="
                    .. tostring(Game():GetFrameCount())
                    .. " mini=" .. tostring(mini.InitSeed)
                    .. " weapon=" .. tostring(kind)
                    .. " charge=" .. tostring(weapon:GetCharge())
                    .. " max=" .. tostring(weapon:GetMaxCharge())
                    .. " fired=" .. tostring(weapon:GetNumFired())
                    .. " fire_delay=" .. tostring(weapon:GetFireDelay())
                    .. " knives=" .. tostring(state.knives)
                    .. " releases=" .. tostring(state.releases))
            end
            return true
        end
    end, FamiliarVariant.INCUBUS)

    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, function(_, proxy)
        if not Router.IsProxy(proxy) then return end
        local mini = ownerOf(proxy)
        if not mini then return end
        proxy.Position = mini.Position
        proxy.Velocity = Vector.Zero

        local target = targetFor(mini)
        local aim = target and (target.Position - mini.Position) or Vector.Zero
        mini:GetData().AscentionMiniIsaacAim = target and aim or nil
        local weapon = proxy:GetWeapon()
        if weapon and weapon:GetWeaponType() == WeaponType.WEAPON_KNIFE then return end
        local fired, techXRelease = native.TickProxy(proxy, aim.X, aim.Y, target ~= nil)
        if techXRelease then
            local data = mini:GetData()
            local samples = data.AscentionMiniIsaacTechXReleases or 0
            if samples < 8 then
                data.AscentionMiniIsaacTechXReleases = samples + 1
                local state = native.Diagnostics(proxy)
                Isaac.DebugString("[AscentionMiniIsaac] tech_x_release frame="
                    .. tostring(Game():GetFrameCount())
                    .. " mini=" .. tostring(mini.InitSeed)
                    .. " engine_input=" .. tostring(state.release_input_x) .. ","
                    .. tostring(state.release_input_y)
                    .. " same_frame=" .. tostring(state.release_input_same_frame)
                    .. " owner_head=" .. tostring(state.owner_head)
                    .. " native_rings=" .. tostring(state.release_tech_x))
            end
        end
        if target and weapon and Game():GetFrameCount() % 100 == 0 then
            local data = mini:GetData()
            local kind = weapon:GetWeaponType()
            local samples = data.AscentionMiniIsaacDirectionSamples or {}
            data.AscentionMiniIsaacDirectionSamples = samples
            local count = samples[kind] or 0
            if count < 4 then
                samples[kind] = count + 1
                local state = native.Diagnostics(proxy)
                Isaac.DebugString("[AscentionMiniIsaac] direction weapon="
                    .. tostring(kind) .. " aim=" .. tostring(aim.X) .. "," .. tostring(aim.Y)
                    .. " after=" .. tostring(state.after_x) .. "," .. tostring(state.after_y)
                    .. " blocked=" .. tostring(state.blocked_fire)
                    .. " blocked_arg=" .. tostring(state.blocked_x) .. ","
                    .. tostring(state.blocked_y)
                    .. " input_reads=" .. tostring(state.input_reads)
                    .. " charge=" .. tostring(weapon:GetCharge()))
            end
        end
        if target and weapon and weapon:GetMaxCharge() > 0 then
            local data = mini:GetData()
            local kind = weapon:GetWeaponType()
            local samples = data.AscentionMiniIsaacChargeSamples or {}
            data.AscentionMiniIsaacChargeSamples = samples
            local count = samples[kind] or 0
            if count < 3 and Game():GetFrameCount() % 90 == 0 then
                samples[kind] = count + 1
                local state = native.Diagnostics(proxy)
                Isaac.DebugString("[AscentionMiniIsaac] charge weapon=" .. tostring(kind)
                    .. " current=" .. tostring(weapon:GetCharge())
                    .. " max=" .. tostring(weapon:GetMaxCharge())
                    .. " delay=" .. tostring(weapon:GetFireDelay())
                    .. " fired=" .. tostring(weapon:GetNumFired())
                    .. " releases=" .. tostring(state.releases)
                    .. " projectiles=" .. tostring(state.projectiles)
                    .. " brimstones=" .. tostring(state.brimstones)
                    .. " tech_lasers=" .. tostring(state.tech_lasers)
                    .. " tech_x=" .. tostring(state.tech_x)
                    .. " knives=" .. tostring(state.knives)
                    .. " owner_dir=" .. tostring(state.owner_dir_x) .. ","
                    .. tostring(state.owner_dir_y)
                    .. " owner_charge=" .. tostring(state.owner_charge)
                    .. " owner_head=" .. tostring(state.owner_head)
                    .. " owner_can_shoot=" .. tostring(state.owner_can_shoot))
            end
        end
        if fired then
            mini:GetData().AscentionMiniIsaacLastShotFrame = Game():GetFrameCount()
            mini:GetData().AscentionMiniIsaacLastShotVelocity = aim
            local data = mini:GetData()
            local count = data.AscentionMiniIsaacNativeDebugShots or 0
            if count < 3 then
                data.AscentionMiniIsaacNativeDebugShots = count + 1
                Isaac.DebugString("[AscentionMiniIsaac] native fired mini="
                    .. tostring(mini.InitSeed) .. " target="
                    .. tostring(target and target.InitSeed or "none"))
            end
        end
    end, FamiliarVariant.INCUBUS)

    mod:AddCallback(ModCallbacks.MC_PRE_KNIFE_RENDER, function(_, knife)
        local data = knife:GetData()
        local owner = data.AscentionMiniIsaacRenderOwner
        local mini = owner and owner.Ref
        if not mini or not mini:Exists() or knife:IsFlying() then return end
        return false
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_RENDER, function(_, mini)
        if not Router.IsManaging(mini) then return end
        local pointer = mini:GetData().AscentionMiniIsaacHeldKnife
        local entity = pointer and pointer.Ref
        local knife = entity and entity:Exists() and entity:ToKnife()
        if knife and not knife:IsFlying() then
            renderHeldKnife(knife, mini, knifeFacing(mini))
        end
    end, FamiliarVariant.MINISAAC)

    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_RENDER, function(_, proxy)
        if Router.IsProxy(proxy) then return false end
    end, FamiliarVariant.INCUBUS)
end

return Router
