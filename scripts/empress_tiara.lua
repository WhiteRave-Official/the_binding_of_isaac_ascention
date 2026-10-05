local EmpressTiara = {}

local GUARDIAN_SUBTYPE = 7345
local MAX_GUARDIANS = 2

local function guardiansFor(player)
    local guardians = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR,
        FamiliarVariant.MINISAAC, GUARDIAN_SUBTYPE)) do
        local mini = entity:ToFamiliar()
        if mini and mini.Player
            and GetPtrHash(mini.Player) == GetPtrHash(player) then
            guardians[#guardians + 1] = mini
        end
    end
    table.sort(guardians, function(left, right)
        return left.InitSeed < right.InitSeed
    end)
    return guardians
end

local function useTiara(_, _, _, player)
    local guardians = guardiansFor(player)
    local living = 0
    for _, mini in ipairs(guardians) do
        if mini:IsDead() or mini.HitPoints <= 0 or living >= MAX_GUARDIANS then
            mini:Remove()
        else
            living = living + 1
            mini.HitPoints = mini.MaxHitPoints
        end
    end

    while living < MAX_GUARDIANS do
        local offset = living == 0 and Vector(-20, 0) or Vector(20, 0)
        local mini = player:AddMinisaac(player.Position + offset, true)
        if not mini then break end
        mini.SubType = GUARDIAN_SUBTYPE
        living = living + 1
    end

    return { Discharge = true, Remove = false, ShowAnim = true }
end

function EmpressTiara.Register(mod, itemId)
    mod:AddCallback(ModCallbacks.MC_USE_ITEM, useTiara, itemId)
end

return EmpressTiara
