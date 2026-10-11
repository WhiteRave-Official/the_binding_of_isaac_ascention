local vectorMeta = {}
local function vector(x, y)
    return setmetatable({ X = x, Y = y,
        Distance = function(_, other)
            return math.sqrt((x - other.X) ^ 2 + (y - other.Y) ^ 2)
        end,
        Normalized = function()
            local length = math.sqrt(x * x + y * y)
            return vector(x / length, y / length)
        end,
        Rotated = function(_, angle)
            local rad = math.rad(angle)
            return vector(x * math.cos(rad) - y * math.sin(rad),
                x * math.sin(rad) + y * math.cos(rad))
        end,
    }, vectorMeta)
end
vectorMeta.__sub = function(a, b) return vector(a.X - b.X, a.Y - b.Y) end
vectorMeta.__add = function(a, b) return vector(a.X + b.X, a.Y + b.Y) end
vectorMeta.__mul = function(a, n) return vector(a.X * n, a.Y * n) end
Vector = vector
ModCallbacks = { MC_POST_KNIFE_UPDATE = 1 }
CollectibleType = { COLLECTIBLE_BRIMSTONE = 118 }
RNG = function()
    local roll = 0
    return { SetSeed = function() end, RandomFloat = function()
        roll = roll + 1
        return (roll % 3) / 2
    end }
end
local player = {
    Position = vector(0, 0), ShotSpeed = 1,
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end,
    HasCollectible = function(self, item)
        return item == 9 or item == CollectibleType.COLLECTIBLE_BRIMSTONE
            and self.brimstone
    end,
    GetWeapon = function(self)
        return { GetMainEntity = function() return self.mainKnife end }
    end,
    ToPlayer = function(self) return self end,
}
local knife = {
    InitSeed = 1, Position = vector(20, 0), SpawnerEntity = player,
    GetData = function(self)
        self.data = self.data or {}
        return self.data
    end,
}
player.mainKnife = knife
local callback
local mod = { AddCallback = function(_, id, fn)
    assert(id == ModCallbacks.MC_POST_KNIFE_UPDATE)
    callback = fn
end }
local bursts = {}
dofile("scripts/holy_chalice_knife.lua").Register(mod, 9,
    function(_, position, velocity)
        bursts[#bursts + 1] = { position = position, velocity = velocity }
    end)
for _, distance in ipairs({ 20, 40, 65, 100, 98 }) do
    knife.Position = vector(distance, 0)
    callback(mod, knife)
    if distance == 40 then
        assert(#bursts == 6,
            "partial charge must burst as the knife leaves, not at max distance")
    end
end
assert(#bursts == 6, "returning knife must not burst a second time")
player:GetData().HolyChaliceKnifeThrowCharge = 1
for _, distance in ipairs({ 90, 50, 15 }) do
    knife.Position = vector(distance, 0)
    callback(mod, knife)
end
player:GetData().HolyChaliceKnifeShotSerial = 1
for _, distance in ipairs({ 60, 110, 105 }) do
    knife.Position = vector(distance, 0)
    callback(mod, knife)
    if distance == 60 then
        assert(#bursts == 21, "full charge must burst at launch")
    end
end
assert(#bursts == 21, "full charge must release fifteen bubbles")
local widest = 0
for _, burst in ipairs(bursts) do
    widest = math.max(widest, math.abs(burst.position.Y))
end
assert(widest > 8, "knife burst must have a wider lateral spread")
player.brimstone = true
local bonus = { InitSeed = 2, Position = vector(20, 0),
    SpawnerEntity = player, GetData = knife.GetData }
for _, distance in ipairs({ 20, 40, 50 }) do
    bonus.Position = vector(distance, 0)
    callback(mod, bonus)
end
assert(#bursts == 23, "Brimstone bonus knife must release at most two bubbles")
player:GetData().HolyChaliceKnifeShotSerial = 2
knife.Position = vector(15, 0)
callback(mod, knife)
knife.Position = vector(60, 0)
callback(mod, knife)
assert(#bursts == 38, "main knife must retain the full burst")
print("holy chalice knife: OK")
