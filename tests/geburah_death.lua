Isaac = {
    GetPlayerTypeByName = function() return 42 end,
    GetCostumeIdByPath = function() return 1 end,
}
CollectibleType = { COLLECTIBLE_MONSTROS_LUNG = 1, COLLECTIBLE_JUPITER = 2 }
ModCallbacks = {
    MC_POST_GAME_STARTED = 1,
    MC_POST_PLAYER_INIT = 2,
    MC_PRE_GAME_EXIT = 3,
    MC_EVALUATE_CACHE = 4,
    MC_POST_PLAYER_UPDATE = 5,
}

local callbacks = {}
local mod = { AddCallback = function(_, id, callback)
    callbacks[id] = callback
end }
local sprite = { loads = 0 }
function sprite:Load(path)
    self.path = path
    self.loads = self.loads + 1
end
function sprite:GetDefaultAnimationName() return "WalkDown" end
function sprite:Play(animation) self.animation = animation end

local player = { data = {}, type = 42 }
function player:GetPlayerType() return self.type end
function player:GetSprite() return sprite end
function player:GetData() return self.data end
function player:HasCollectible() return false end
function player:TryRemoveNullCostume() end
function player:AddNullCostume() end

local Geburah = dofile("scripts/characters/geburah.lua")
Geburah.Register(mod, 0)
callbacks[ModCallbacks.MC_POST_PLAYER_INIT](nil, player)
assert(sprite.path == "gfx/characters/player_geburah.anm2"
    and sprite.animation == "WalkDown" and sprite.loads == 1,
    "Geburah must load the custom player animator before death")
callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](nil, player)
assert(sprite.loads == 1, "ordinary updates must not reset player animation")
print("geburah death: OK")
