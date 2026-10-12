local Scaling = {}

local BASE_STREAM_INTERVAL = 4
local BASE_FIRE_RATE = 3
local TEARS_BONUS = 0.3
local MULTISHOT_INTERVAL_COST = 0.35
local DATA_KEY = "AscentionHolyChaliceBaseStats"
local SAVE_KEY = "holyChaliceBaseStats"

local function fireRate(player)
    return 30 / math.max(0.1, player.MaxFireDelay + 1)
end

local function state(player)
    local data = player:GetData()
    if not data[DATA_KEY] then data[DATA_KEY] = {} end
    return data[DATA_KEY]
end

local function readSave(mod)
    if not mod:HasData() then return {} end
    local json = require "json"
    local ok, decoded = pcall(json.decode, mod:LoadData())
    return ok and type(decoded) == "table" and decoded or {}
end

local function capture(player, itemId)
    local base = state(player)
    base.rate = fireRate(player) - TEARS_BONUS * player:GetCollectibleNum(itemId)
    base.range = player.TearRange
end

function Scaling.StreamInterval(player, itemId, expectedProjectiles, multiplier,
    minimumRate)
    local rate = fireRate(player)
    local chaliceBonus = TEARS_BONUS * player:GetCollectibleNum(itemId)
    local baseRate = state(player).rate or rate - chaliceBonus
    local extraRate = math.max(0, rate - chaliceBonus - baseRate)
    local streamRate = math.max(minimumRate or 0.1, rate - extraRate * 0.3)
    local baseInterval = math.max(1,
        BASE_STREAM_INTERVAL * BASE_FIRE_RATE / streamRate)
    local extraProjectiles = math.max(0, (expectedProjectiles or 1) - 1)
    return baseInterval * (1 + MULTISHOT_INTERVAL_COST * extraProjectiles)
        * (multiplier or 1)
end

function Scaling.Range(player)
    local range = player.TearRange
    local baseRange = state(player).range or range
    return range - math.max(0, range - baseRange) * 0.5
end

function Scaling.Register(mod, itemId)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
        local saved = continued and readSave(mod)[SAVE_KEY] or nil
        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            local entry = saved and saved[tostring(index)]
            if entry and tonumber(entry.rate) and tonumber(entry.range) then
                local base = state(player)
                base.rate = tonumber(entry.rate)
                base.range = tonumber(entry.range)
            else
                capture(player, itemId)
            end
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, function(_, player)
        if not state(player).rate then capture(player, itemId) end
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
        local saved = readSave(mod)
        local baselines = {}
        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            local base = state(player)
            baselines[tostring(index)] = {
                rate = base.rate,
                range = base.range,
            }
        end
        saved[SAVE_KEY] = baselines
        mod:SaveData(require("json").encode(saved))
    end)
end

return Scaling
