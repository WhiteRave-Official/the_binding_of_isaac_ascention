local Multishot = {}

local MAX_CLUSTERS = 8
local CONJOINED_COOLDOWN_MULTIPLIER = 1.10
local NORMAL_LANES = { 0 }
local WIZ_LANES = { -45, 45 }
local CONJOINED_LANES = { -30, 0, 30 }
local WIZ_CONJOINED_LANES = { -75, -45, -15, 15, 45, 75 }

local function composition(player)
    local inner = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_INNER_EYE)
    local spider = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_MUTANT_SPIDER)
    local double = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_20_20)
    local count = math.min(MAX_CLUSTERS, 1 + inner * 2 + spider * 3 + double)
    local wiz = player:HasCollectible(CollectibleType.COLLECTIBLE_THE_WIZ)
    local conjoined = player:HasPlayerForm(PlayerForm.PLAYERFORM_BABY)
    local laneCount = (wiz and 2 or 1) * (conjoined and 3 or 1)
    return count, laneCount, inner, spider, wiz, conjoined
end

function Multishot.ExpectedProjectiles(player)
    local count, laneCount, inner, spider, _, conjoined = composition(player)
    local meanSize = spider > 0 and 3 or inner > 0 and 2 or 1
    if conjoined then meanSize = meanSize + 1 end
    return count * laneCount * meanSize
end

function Multishot.CooldownProjectiles(player)
    local count, _, inner, spider, wiz = composition(player)
    local meanSize = spider > 0 and 3 or inner > 0 and 2 or 1
    return count * (wiz and 2 or 1) * meanSize
end

function Multishot.CooldownMultiplier(player)
    return player:HasPlayerForm(PlayerForm.PLAYERFORM_BABY)
        and CONJOINED_COOLDOWN_MULTIPLIER or 1
end

function Multishot.Clusters(player, rng)
    local count, _, inner, spider, wiz, conjoined = composition(player)
    local lanes = conjoined and (wiz and WIZ_CONJOINED_LANES
        or CONJOINED_LANES) or (wiz and WIZ_LANES or NORMAL_LANES)
    local result = {}
    for _, lane in ipairs(lanes) do
        for index = 1, count do
            local angle = lane + (index - (count + 1) / 2)
                * math.min(16, 48 / math.max(1, count - 1))
            local size = 1
            if spider > 0 then
                size = 2 + rng:RandomInt(3)
            elseif inner > 0 then
                size = 1 + rng:RandomInt(3)
            end
            if conjoined then size = size + 1 end
            result[#result + 1] = { angle = angle, size = size,
                clustered = inner > 0 or spider > 0 }
        end
    end
    return result
end

return Multishot
