local EmpressTiara = {}

local json = require "json"
local DamageCredit = include("scripts.damage_credit")
local GEBURAH = Isaac.GetPlayerTypeByName("Geburah")
local GUARDIAN_SUBTYPE = 7345
local DUMMY_TYPE = EntityType.ENTITY_DUMMY or 964
local SAVE_KEY = "empressTiaraDamage"
local PENDING_DAMAGE_KEY = "AscentionEmpressTiaraPendingDamage"
local REFERENCE_DAMAGE = 3.8
local TIERS = {
    { threshold = 0, guardians = 1, heal = 0.50, charges = 4 },
    { threshold = 2000, guardians = 2, heal = 0.75, charges = 3 },
    { threshold = 4000, guardians = 3, heal = 0.85, charges = 3 },
    { threshold = 8000, guardians = 3, heal = 0.85, charges = 2 },
}
local ACTIVE_SLOTS = {
    ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_POCKET,
}
local damageByPlayer = {}
local itemIds = {}
local damageSamples = 0
local probeSamples = 0

local function isGeburah(player)
    return GEBURAH >= 0 and player:GetPlayerType() == GEBURAH
end

local function playerIndex(player)
    for index = 0, Game():GetNumPlayers() - 1 do
        if GetPtrHash(Isaac.GetPlayer(index)) == GetPtrHash(player) then
            return tostring(index)
        end
    end
end

local function readSave(mod)
    if not mod:HasData() then return {} end
    local ok, decoded = pcall(json.decode, mod:LoadData())
    return ok and type(decoded) == "table" and decoded or {}
end

local function save(mod)
    local saved = readSave(mod)
    saved[SAVE_KEY] = damageByPlayer
    mod:SaveData(json.encode(saved))
end

local function tierForDamage(damage)
    for level = #TIERS, 2, -1 do
        if damage >= TIERS[level].threshold then return level end
    end
    return 1
end

function EmpressTiara.LevelForPlayer(player)
    if not player or not isGeburah(player) then return 1 end
    local index = playerIndex(player)
    return tierForDamage(index and (damageByPlayer[index] or 0) or 0)
end

local function isTiara(itemId)
    for _, id in ipairs(itemIds) do
        if id == itemId then return true end
    end
    return false
end

function EmpressTiara.HasTiara(player)
    for _, slot in ipairs(ACTIVE_SLOTS) do
        if isTiara(player:GetActiveItem(slot)) then return true end
    end
    return false
end

function EmpressTiara.HealthBonus(player)
    return EmpressTiara.LevelForPlayer(player) == 4
        and EmpressTiara.HasTiara(player) and 10 or 0
end

local function guardiansFor(player)
    local guardians = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR,
        FamiliarVariant.MINISAAC, GUARDIAN_SUBTYPE)) do
        local mini = entity:ToFamiliar()
        if mini and mini.Player and GetPtrHash(mini.Player) == GetPtrHash(player) then
            guardians[#guardians + 1] = mini
        end
    end
    table.sort(guardians, function(left, right)
        return left.InitSeed < right.InitSeed
    end)
    return guardians
end

local function useTiara(_, _, _, player)
    local config = TIERS[EmpressTiara.LevelForPlayer(player)]
    local living = 0
    for _, mini in ipairs(guardiansFor(player)) do
        if mini:IsDead() or mini.HitPoints <= 0 or living >= config.guardians then
            mini:Remove()
        else
            living = living + 1
            mini.HitPoints = math.min(mini.MaxHitPoints,
                mini.HitPoints + mini.MaxHitPoints * config.heal)
        end
    end

    while living < config.guardians do
        local offset = Vector((living - (config.guardians - 1) / 2) * 40, 0)
        local mini = player:AddMinisaac(player.Position + offset, true)
        if not mini then break end
        mini.SubType = GUARDIAN_SUBTYPE
        living = living + 1
    end
    return { Discharge = true, Remove = false, ShowAnim = true }
end

local function replaceTiara(player, slot, oldId, level)
    local charge = math.min(player:GetActiveCharge(slot), TIERS[level].charges)
    local battery = player:GetBatteryCharge(slot)
    player:RemoveCollectible(oldId, false, slot)
    if slot == ActiveSlot.SLOT_POCKET then
        player:SetPocketActiveItem(itemIds[level], slot, true)
    else
        player:AddCollectible(itemIds[level], charge, false, slot)
    end
    player:SetActiveCharge(charge, slot)
    if battery > 0 then player:AddActiveCharge(battery, slot, false, true, true) end
end

local function syncTiara(player)
    local level = EmpressTiara.LevelForPlayer(player)
    for _, slot in ipairs(ACTIVE_SLOTS) do
        local oldId = player:GetActiveItem(slot)
        if isTiara(oldId) and oldId ~= itemIds[level] then
            replaceTiara(player, slot, oldId, level)
        end
    end
end

function EmpressTiara.Register(mod, ids)
    itemIds = ids
    for _, itemId in ipairs(ids) do
        mod:AddCallback(ModCallbacks.MC_USE_ITEM, useTiara, itemId)
    end

    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
        local saved = continued and readSave(mod)[SAVE_KEY] or nil
        damageByPlayer = type(saved) == "table" and saved or {}
        for index = 0, Game():GetNumPlayers() - 1 do
            Isaac.GetPlayer(index):GetData().AscentionEmpressTiaraSyncedLevel = nil
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
        local data = player:GetData()
        local level = EmpressTiara.LevelForPlayer(player)
        if data.AscentionEmpressTiaraSyncedLevel ~= level then
            data.AscentionEmpressTiaraSyncedLevel = level
            syncTiara(player)
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE,
        function(_, itemId, _, _, _, _, player)
            if isTiara(itemId) then
                player:GetData().AscentionEmpressTiaraSyncedLevel = nil
            end
        end)

    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG,
        function(_, entity, _, _, source, _, extraSource)
            local dummy = entity.Type == DUMMY_TYPE
            local npc = entity:ToNPC()
            if not dummy and (not npc or not entity:IsVulnerableEnemy()
                or entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)) then return end
            local data = entity:GetData()
            data[PENDING_DAMAGE_KEY] = nil
            local owner = DamageCredit.Player(source, extraSource)
            local held = owner and EmpressTiara.HasTiara(owner)
            if probeSamples < 8 then
                probeSamples = probeSamples + 1
                Isaac.DebugString("[AscentionTiara] damage_probe type="
                    .. tostring(entity.Type) .. " dummy=" .. tostring(dummy)
                    .. " owner=" .. tostring(owner and owner:GetPlayerType())
                    .. " held=" .. tostring(held))
            end
            if not owner or not isGeburah(owner) or not held then return end
            local index = playerIndex(owner)
            if index then
                data[PENDING_DAMAGE_KEY] = {
                    index = index, health = math.max(0, entity.HitPoints or 0),
                    dummy = dummy,
                    damageScale = math.sqrt(math.max(1,
                        (owner.Damage or REFERENCE_DAMAGE) / REFERENCE_DAMAGE)),
                }
            end
        end)

    mod:AddCallback(ModCallbacks.MC_POST_ENTITY_TAKE_DMG,
        function(_, entity, damage)
            local data = entity:GetData()
            local pending = data[PENDING_DAMAGE_KEY]
            data[PENDING_DAMAGE_KEY] = nil
            if not pending then return end
            local dealt = pending.dummy and math.max(0, damage or 0)
                or math.max(0, pending.health - math.max(0, entity.HitPoints or 0))
            if dealt <= 0 then return end
            local previous = damageByPlayer[pending.index] or 0
            local total = previous + dealt / pending.damageScale
            damageByPlayer[pending.index] = total
            if damageSamples < 8 then
                damageSamples = damageSamples + 1
                Isaac.DebugString("[AscentionTiara] progress dealt=" .. tostring(dealt)
                    .. " points=" .. tostring(total)
                    .. " tier=" .. tostring(tierForDamage(total)))
            end
            if tierForDamage(total) ~= tierForDamage(previous) then
                local player = Isaac.GetPlayer(tonumber(pending.index))
                if player then
                    player:GetData().AscentionEmpressTiaraSyncedLevel = nil
                end
                Isaac.DebugString("[AscentionTiara] level_up tier="
                    .. tostring(tierForDamage(total)) .. " points=" .. tostring(total))
                save(mod)
            end
        end)

    mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function() save(mod) end)
    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function() save(mod) end)
end

return EmpressTiara
