local DamageCredit = {}

local function playerFrom(entity, depth)
    if not entity or depth > 5 then return nil end

    local player = entity:ToPlayer()
    if player then return player end

    local data = entity:GetData()
    local pointer = data.AscentionMiniIsaacOwner
        or data.AscentionMiniIsaacProxyOwner
    local mini = pointer and pointer.Ref
    if mini and mini:Exists() then return mini.Player end

    local familiar = entity:ToFamiliar()
    if familiar and familiar.Player then return familiar.Player end

    return playerFrom(entity.SpawnerEntity, depth + 1)
        or playerFrom(entity.Parent, depth + 1)
end

function DamageCredit.Player(source, extraSource)
    return playerFrom(extraSource and extraSource.Entity, 0)
        or playerFrom(source and source.Entity, 0)
end

return DamageCredit
