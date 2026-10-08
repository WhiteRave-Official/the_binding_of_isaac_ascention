local Tammy = {}
local BURST_KEY = "HolyChaliceTammyBurst"

function Tammy.IsBurst(player)
    return player:GetData()[BURST_KEY] == Game():GetFrameCount()
end

function Tammy.Register(mod, itemId)
    mod:AddCallback(ModCallbacks.MC_PRE_USE_ITEM,
        function(_, usedItem, _, player)
            if usedItem == CollectibleType.COLLECTIBLE_TAMMYS_HEAD
                and player:HasCollectible(itemId) then
                player:GetData()[BURST_KEY] = Game():GetFrameCount()
            end
        end, CollectibleType.COLLECTIBLE_TAMMYS_HEAD)

    mod:AddCallback(ModCallbacks.MC_POST_USE_ITEM,
        function(_, usedItem, _, player)
            if usedItem == CollectibleType.COLLECTIBLE_TAMMYS_HEAD then
                player:GetData()[BURST_KEY] = nil
            end
        end, CollectibleType.COLLECTIBLE_TAMMYS_HEAD)
end

return Tammy
