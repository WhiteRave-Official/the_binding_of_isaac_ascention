CollectibleType = { COLLECTIBLE_NEPTUNUS = 597 }
local owned = true
local player = { HasCollectible = function() return owned end }
local holder = { data = {} }
function holder:GetData() return self.data end

local neptunus = dofile("scripts/holy_chalice_neptunus.lua")
assert(neptunus.UsesNativeFire(player))
local function tear()
    return {
        data = {}, Visible = true,
        GetData = function(self) return self.data end,
        Remove = function(self) self.removed = true end,
    }
end
local first = tear()
assert(neptunus.ReplaceNativeTear(holder, first, 90))
assert(first.removed and not first.Visible)
assert(not neptunus.ReplaceNativeTear(holder, first, 91))
local second = tear()
assert(not neptunus.ReplaceNativeTear(holder, second, 90))
assert(second.removed and not second.Visible)
assert(neptunus.ReplaceNativeTear(holder, tear(), 91))
owned = false
assert(not neptunus.UsesNativeFire(player))

print("holy_chalice_neptunus: OK")
