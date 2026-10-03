local globalKey = "__ASCENTION_PROJECTILE_SPAWN_CONTEXT"
local existing = rawget(_G, globalKey)
if existing then
    return existing
end

local ProjectileSpawnContext = {
    depths = {}
}

function ProjectileSpawnContext.IsActive(kind)
    return (ProjectileSpawnContext.depths[kind] or 0) > 0
end

function ProjectileSpawnContext.Run(kind, callback)
    ProjectileSpawnContext.depths[kind] = (ProjectileSpawnContext.depths[kind] or 0) + 1
    local result = table.pack(pcall(callback))
    ProjectileSpawnContext.depths[kind] = ProjectileSpawnContext.depths[kind] - 1

    if not result[1] then
        error(result[2], 0)
    end

    return table.unpack(result, 2, result.n)
end

rawset(_G, globalKey, ProjectileSpawnContext)
return ProjectileSpawnContext
