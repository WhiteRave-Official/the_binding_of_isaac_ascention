EntityType = { ENTITY_FIREPLACE = 33 }
EntityFlag = { FLAG_FRIENDLY = 1 }
GridEntityType = { GRID_POOP = 14 }

local function vector(x, y)
    return setmetatable({
        X = x,
        Y = y,
        DistanceSquared = function(self, other)
            return (self.X - other.X) ^ 2 + (self.Y - other.Y) ^ 2
        end,
    }, {
        __sub = function(a, b) return vector(a.X - b.X, a.Y - b.Y) end,
    })
end

local function npc(kind, x, y, hp, seed)
    local entity = {
        Type = kind,
        Position = vector(x, y),
        HitPoints = hp,
        InitSeed = seed,
    }
    function entity:ToNPC() return self end
    function entity:Exists() return true end
    function entity:IsDead() return self.HitPoints <= 0 end
    function entity:IsActiveEnemy() return self.Type ~= EntityType.ENTITY_FIREPLACE end
    function entity:IsVulnerableEnemy() return true end
    function entity:HasEntityFlags() return false end
    return entity
end

local room = { seed = 123, grids = {} }
function room:GetSpawnSeed() return self.seed end
function room:GetGridSize() return 3 end
function room:GetGridEntity(index) return self.grids[index] end
Game = function() return { GetRoom = function() return room end } end

local entities = {}
Isaac = { GetRoomEntities = function() return entities end }
local targeting = dofile("scripts/golden_eye_targeting.lua")
local origin = vector(0, 0)

assert(targeting.FindTarget(origin) == nil)
local fire = npc(EntityType.ENTITY_FIREPLACE, 60, 0, 10, 1)
entities = { fire }
assert(targeting.FindTarget(origin) == fire)

room.grids[1] = {
    Position = vector(20, 0),
    State = 0,
    GetType = function() return GridEntityType.GRID_POOP end,
}
local poop = targeting.FindTarget(origin)
assert(poop.kind == "poop" and poop.gridIndex == 1)
assert(targeting.IsValid(poop))
assert(targeting.GetPosition(poop) == room.grids[1].Position)

local enemy = npc(10, 200, 0, 10, 2)
entities = { fire, enemy }
assert(targeting.FindTarget(origin) == enemy)

entities = { fire }
room.grids[1].State = 1000
assert(not targeting.IsValid(poop))
assert(targeting.FindTarget(origin) == fire)

fire.HitPoints = 0
assert(targeting.FindTarget(origin) == nil)
room.grids[1].State = 0
room.seed = 124
assert(not targeting.IsValid(poop))

package.loaded.json = { encode = function() end, decode = function() end }
FamiliarVariant = { INCUBUS = 1 }
local nextCallbackId = 1
ModCallbacks = setmetatable({ MC_POST_PLAYER_UPDATE = 1 }, {
    __index = function(self, key)
        nextCallbackId = nextCallbackId + 1
        rawset(self, key, nextCallbackId)
        return nextCallbackId
    end,
})
local callbacks = {}
local mod = {
    AddCallback = function(_, id, callback)
        callbacks[id] = callback
    end,
}
Isaac.FindByType = function() return {} end
local goldenEye = dofile("scripts/golden_eye.lua")
goldenEye.Register(mod, 1234, 5678, {}, targeting)

local playerData = {}
local player = {
    Position = origin,
    HasCollectible = function() return true end,
    GetData = function() return playerData end,
    SetCanShoot = function() end,
}
callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](mod, player)
assert(playerData.GoldenEyeFireInput == true)

room.grids[1].State = 1000
callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](mod, player)
assert(playerData.GoldenEyeFireInput == false)
assert(playerData.GoldenEyeAim == nil)
print("golden eye targeting: OK")
