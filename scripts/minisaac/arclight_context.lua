local Context = {}

local cachedProxies = {}

local function miniOfProxy(entity)
    local familiar = entity and entity:ToFamiliar()
    if not familiar then return nil end
    local data = familiar:GetData()
    if not data.AscentionMiniIsaacWeaponProxy then return nil end
    local pointer = data.AscentionMiniIsaacProxyOwner
    local mini = pointer and pointer.Ref
    if mini and mini:Exists() then return mini end
    return nil
end

local function proxyOfMini(mini)
    local pointer = mini and mini:GetData().AscentionMiniIsaacProxy
    local proxy = pointer and pointer.Ref
    if proxy and proxy:Exists() and miniOfProxy(proxy) then return proxy end
    return nil
end

local function activeProxy()
    if not AscentionNative or not AscentionNative.FiringProxySeed then return nil end
    local seed = AscentionNative.FiringProxySeed()
    if not seed or seed == 0 then return nil end
    local cached = cachedProxies[seed]
    if cached and cached:Exists() and cached.InitSeed == seed
        and miniOfProxy(cached) then return cached end
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR,
        FamiliarVariant.INCUBUS)) do
        if entity.InitSeed == seed and miniOfProxy(entity) then
            local proxy = entity:ToFamiliar()
            cachedProxies[seed] = proxy
            return proxy
        end
    end
    return nil
end

function Context.ForProjectile(projectile)
    if not projectile then return nil end
    local function fromEntity(entity)
        if miniOfProxy(entity) then return entity:ToFamiliar() end
        local familiar = entity and entity:ToFamiliar()
        return familiar and proxyOfMini(familiar)
    end
    local direct = fromEntity(projectile.SpawnerEntity)
        or fromEntity(projectile.Parent)
    if direct then return direct end
    local pointer = projectile:GetData().AscentionMiniIsaacOwner
    local proxy = proxyOfMini(pointer and pointer.Ref)
    return proxy or activeProxy()
end

function Context.MiniForSource(source)
    return miniOfProxy(source)
end

function Context.Position(source)
    local mini = miniOfProxy(source)
    return mini and mini.Position or nil
end

function Context.Aim(source, fallback)
    local mini = miniOfProxy(source)
    local aim = mini and mini:GetData().AscentionMiniIsaacAim
    if aim and aim:LengthSquared() > 0.001 then return aim end
    return fallback
end

return Context
