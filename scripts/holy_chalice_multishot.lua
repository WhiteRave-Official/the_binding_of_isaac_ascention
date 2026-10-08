local Multishot = {}

local MAX_CLUSTERS = 8

function Multishot.Clusters(player, rng)
    local inner = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_INNER_EYE)
    local spider = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_MUTANT_SPIDER)
    local double = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_20_20)
    local count = math.min(MAX_CLUSTERS, 1 + inner * 2 + spider * 3 + double)
    local lanes = player:HasCollectible(CollectibleType.COLLECTIBLE_THE_WIZ)
        and { -45, 45 } or { 0 }
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
            result[#result + 1] = { angle = angle, size = size,
                clustered = inner > 0 or spider > 0 }
        end
    end
    return result
end

return Multishot
