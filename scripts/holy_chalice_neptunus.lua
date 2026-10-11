local Neptunus = {}

function Neptunus.UsesNativeFire(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_NEPTUNUS)
end

function Neptunus.ReplaceNativeTear(holder, tear, frame)
    local tearData = tear:GetData()
    if tearData.HolyChaliceNeptunusReplaced then return false end
    tearData.HolyChaliceNeptunusReplaced = true
    tear.Visible = false
    tear:Remove()
    local data = holder:GetData()
    if data.HolyChaliceNeptunusVolleyFrame == frame then return false end
    data.HolyChaliceNeptunusVolleyFrame = frame
    return true
end

return Neptunus
