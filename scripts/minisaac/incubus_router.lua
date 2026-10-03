local Router = {}

local PROXY_KEY = "AscentionMiniIsaacWeaponProxy"
local OWNER_KEY = "AscentionMiniIsaacProxyOwner"
local TARGET_REFRESH_INTERVAL = 6
local native = AscentionNative

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
    if proxy then return proxy end
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
            removeProxy(mini)
            return
        end
        ensureProxy(mini)
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
        local fired = native.TickProxy(proxy, aim.X, aim.Y, target ~= nil)
        local weapon = proxy:GetWeapon()
        if target and weapon and weapon:GetMaxCharge() > 0 then
            local data = mini:GetData()
            local kind = weapon:GetWeaponType()
            local samples = data.AscentionMiniIsaacChargeSamples or {}
            data.AscentionMiniIsaacChargeSamples = samples
            local count = samples[kind] or 0
            if count < 3 and Game():GetFrameCount() % 90 == 0 then
                samples[kind] = count + 1
                Isaac.DebugString("[AscentionMiniIsaac] charge weapon=" .. tostring(kind)
                    .. " current=" .. tostring(weapon:GetCharge())
                    .. " max=" .. tostring(weapon:GetMaxCharge())
                    .. " delay=" .. tostring(weapon:GetFireDelay())
                    .. " fired=" .. tostring(weapon:GetNumFired()))
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

    mod:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_RENDER, function(_, proxy)
        if Router.IsProxy(proxy) then return false end
    end, FamiliarVariant.INCUBUS)
end

return Router
