EntityType = { ENTITY_FAMILIAR = 3 }
FamiliarVariant = { INCUBUS = 80 }

local function entity(seed, familiar)
    local value = { InitSeed = seed, data = {} }
    function value:ToFamiliar() return familiar and self or nil end
    function value:GetData() return self.data end
    function value:Exists() return true end
    return value
end

local player = entity(1, false)
local mini = entity(2, true)
local proxy = entity(3, true)
proxy.Player = player
proxy:GetData().AscentionMiniIsaacWeaponProxy = true
proxy:GetData().AscentionMiniIsaacProxyOwner = { Ref = mini }
mini:GetData().AscentionMiniIsaacProxy = { Ref = proxy }
mini.Position = { X = 120, Y = 80 }
local aim = { X = 40, Y = -20 }
function aim:LengthSquared() return self.X * self.X + self.Y * self.Y end
mini:GetData().AscentionMiniIsaacAim = aim

Isaac = { FindByType = function() return { proxy } end }
local activeSeed = 0
AscentionNative = { FiringProxySeed = function() return activeSeed end }

local context = dofile("scripts/minisaac/arclight_context.lua")
local direct = entity(4, false)
direct.SpawnerEntity = proxy
assert(context.ForProjectile(direct) == proxy)

local parentOnly = entity(5, false)
parentOnly.Parent = proxy
assert(context.ForProjectile(parentOnly) == proxy)

local tagged = entity(6, false)
tagged.Parent = player
tagged:GetData().AscentionMiniIsaacOwner = { Ref = mini }
assert(context.ForProjectile(tagged) == proxy)

local scoped = entity(7, false)
scoped.Parent = player
activeSeed = proxy.InitSeed
assert(context.ForProjectile(scoped) == proxy)
activeSeed = 0
assert(context.ForProjectile(scoped) == nil)

assert(context.MiniForSource(proxy) == mini)
assert(context.Position(proxy) == mini.Position)
assert(context.Aim(proxy) == aim)
assert(context.Position(player) == nil)
print("arclight_minisaac_context: OK")
