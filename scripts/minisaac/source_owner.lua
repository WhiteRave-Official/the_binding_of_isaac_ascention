local SourceOwner = {}

local function miniFrom(entity, depth)
    if not entity or depth > 4 then return nil end

    local data = entity:GetData()
    local pointer = data.AscentionMiniIsaacOwner
    local mini = pointer and pointer.Ref
    if mini and mini:Exists() then return mini:ToFamiliar() end

    local familiar = entity:ToFamiliar()
    if familiar then
        if familiar.Variant == FamiliarVariant.MINISAAC then return familiar end
        if data.AscentionMiniIsaacWeaponProxy then
            pointer = data.AscentionMiniIsaacProxyOwner
            mini = pointer and pointer.Ref
            if mini and mini:Exists() then return mini:ToFamiliar() end
        end
    end
    if entity:ToPlayer() then return nil end
    return miniFrom(entity.SpawnerEntity, depth + 1)
        or miniFrom(entity.Parent, depth + 1)
end

function SourceOwner.FromDamage(source, extraSource)
    return miniFrom(extraSource and extraSource.Entity, 0)
        or miniFrom(source and source.Entity, 0)
end

return SourceOwner
