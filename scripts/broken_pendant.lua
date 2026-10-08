local BrokenPendant = {}

local REDUCTION = 0.2
local BASELINE_KEY = "AscentionBrokenPendantBaseline"
local INITIAL_KEY = "AscentionBrokenPendantInitial"
local LAST_RAW_KEY = "AscentionBrokenPendantLastRaw"
local PRE_ADD_KEY = "AscentionBrokenPendantPreAdd"
local PENDING_ADD_KEY = "AscentionBrokenPendantPendingAdd"
local PENDING_REBASE_KEY = "AscentionBrokenPendantPendingRebase"
local TRANSACTION_KEY = "AscentionBrokenPendantTransaction"
local TRACKED_FLAGS = CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY
    | CacheFlag.CACHE_SPEED | CacheFlag.CACHE_RANGE
local STATS = {
    [CacheFlag.CACHE_DAMAGE] = "Damage",
    [CacheFlag.CACHE_SPEED] = "MoveSpeed",
    [CacheFlag.CACHE_RANGE] = "TearRange",
}
local FLAGS = {
    CacheFlag.CACHE_DAMAGE, CacheFlag.CACHE_FIREDELAY,
    CacheFlag.CACHE_SPEED, CacheFlag.CACHE_RANGE,
}

local function fireRate(player)
    local delay = player.MaxFireDelay + 1
    return delay > 0 and 30 / delay or nil
end

local function statKey(flag)
    return STATS[flag] or "FireRate"
end

local function statValue(player, flag)
    local property = STATS[flag]
    return property and player[property] or fireRate(player)
end

local function itemFlags(id)
    local item = Isaac.GetItemConfig():GetCollectible(id)
    return item and item.CacheFlags & TRACKED_FLAGS or 0
end

local function recalculate(player)
    player:AddCacheFlags(TRACKED_FLAGS)
    player:EvaluateItems()
end

function BrokenPendant.Register(mod, trinketId)
    if trinketId <= 0 then return end

    mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cacheFlag)
        local property = STATS[cacheFlag]
        if not property and cacheFlag ~= CacheFlag.CACHE_FIREDELAY then return end

        local data = player:GetData()
        local baseline = data[BASELINE_KEY]
        if not baseline then
            baseline = {}
            data[BASELINE_KEY] = baseline
        end
        local initial = data[INITIAL_KEY]
        if not initial then
            initial = {}
            data[INITIAL_KEY] = initial
        end

        local value = statValue(player, cacheFlag)
        if not value then return end

        local key = statKey(cacheFlag)
        if initial[key] == nil then initial[key] = value end
        local lastRaw = data[LAST_RAW_KEY]
        if not lastRaw then
            lastRaw = {}
            data[LAST_RAW_KEY] = lastRaw
        end
        lastRaw[key] = value

        local transaction = data[TRANSACTION_KEY]
        if transaction and transaction.rebase & cacheFlag ~= 0 then
            baseline[key] = initial[key]
        elseif transaction and transaction.add[cacheFlag] then
            baseline[key] = (baseline[key] or initial[key])
                + math.max(0, value - transaction.add[cacheFlag])
        end
        if baseline[key] == nil then
            baseline[key] = value
        end

        local multiplier = player:GetTrinketMultiplier(trinketId)
        if multiplier <= 0 or value >= baseline[key] then return end

        local reduction = math.min(1, REDUCTION * multiplier)
        local adjusted = value + (baseline[key] - value) * reduction
        if property then
            player[property] = adjusted
        else
            player.MaxFireDelay = 30 / adjusted - 1
        end
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_ADD_COLLECTIBLE,
        function(_, collectibleId, _, _, _, _, player)
            local flags = itemFlags(collectibleId)
            if flags == 0 then return end
            local data = player:GetData()
            local snapshot = {}
            local lastRaw = data[LAST_RAW_KEY] or {}
            for _, flag in ipairs(FLAGS) do
                if flags & flag ~= 0 then
                    local key = statKey(flag)
                    snapshot[flag] = lastRaw[key] or statValue(player, flag)
                    local initial = data[INITIAL_KEY]
                    if not initial then
                        initial = {}
                        data[INITIAL_KEY] = initial
                    end
                    if initial[key] == nil then initial[key] = snapshot[flag] end
                end
            end
            data[PRE_ADD_KEY] = { id = collectibleId, values = snapshot }
        end)

    mod:AddCallback(ModCallbacks.MC_POST_TRIGGER_COLLECTIBLE_ADDED,
        function(_, player, collectibleId, _, wispOrInnate)
            if wispOrInnate then return end
            local data = player:GetData()
            local pre = data[PRE_ADD_KEY]
            data[PRE_ADD_KEY] = nil
            if not pre or pre.id ~= collectibleId then return end
            local pending = data[PENDING_ADD_KEY] or {}
            for flag, value in pairs(pre.values) do
                if pending[flag] == nil then pending[flag] = value end
            end
            data[PENDING_ADD_KEY] = pending
        end)

    mod:AddCallback(ModCallbacks.MC_POST_TRIGGER_COLLECTIBLE_REMOVED,
        function(_, player, collectibleId)
            local flags = itemFlags(collectibleId)
            if flags == 0 then return end
            local data = player:GetData()
            data[PENDING_REBASE_KEY] = (data[PENDING_REBASE_KEY] or 0) | flags
        end)

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
        local data = player:GetData()
        local rebase = data[PENDING_REBASE_KEY] or 0
        local added = data[PENDING_ADD_KEY] or {}
        local flags = rebase
        for flag in pairs(added) do flags = flags | flag end
        if flags == 0 then return end
        data[PENDING_REBASE_KEY] = nil
        data[PENDING_ADD_KEY] = nil
        data[TRANSACTION_KEY] = { rebase = rebase, add = added }
        player:AddCacheFlags(flags)
        player:EvaluateItems()
        data[TRANSACTION_KEY] = nil
    end)

    mod:AddCallback(ModCallbacks.MC_POST_TRIGGER_TRINKET_ADDED, function(_, player, id)
        if id % 32768 == trinketId then recalculate(player) end
    end)
    mod:AddCallback(ModCallbacks.MC_POST_TRIGGER_TRINKET_REMOVED, function(_, player, id)
        if id % 32768 == trinketId then recalculate(player) end
    end)
end

return BrokenPendant
