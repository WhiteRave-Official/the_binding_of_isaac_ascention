local Geburah = {}

local PLAYER_TYPE = Isaac.GetPlayerTypeByName("Geburah")
local PLAYER_SPRITE = "gfx/characters/player_geburah.anm2"
local HAIR_COSTUME = Isaac.GetCostumeIdByPath("gfx/characters/geburah_hair.anm2")
local MONSTROS_LUNG_HAIR_COSTUME = Isaac.GetCostumeIdByPath("gfx/characters/geburah_hair_monstros_lung.anm2")
local TAIL_COSTUME = Isaac.GetCostumeIdByPath("gfx/characters/geburah_tail.anm2")
local MONSTROS_LUNG = CollectibleType.COLLECTIBLE_MONSTROS_LUNG
local JUPITER = CollectibleType.COLLECTIBLE_JUPITER
local HAIR_STATE_KEY = "AscentionGeburahMonstrosLungHair"
local TAIL_STATE_KEY = "AscentionGeburahTail"
local PLAYER_SPRITE_KEY = "AscentionGeburahPlayerSprite"

local function isGeburah(player)
    return PLAYER_TYPE >= 0 and player:GetPlayerType() == PLAYER_TYPE
end

local function removeHairCostume(player, costumeId)
    if costumeId >= 0 then
        player:TryRemoveNullCostume(costumeId)
    end
end

local function addHairCostume(player, costumeId)
    if costumeId >= 0 then
        player:AddNullCostume(costumeId)
    end
end

local function loadPlayerSprite(player)
    local data = player:GetData()
    if data[PLAYER_SPRITE_KEY] then return end
    local sprite = player:GetSprite()
    sprite:Load(PLAYER_SPRITE, true)
    sprite:Play(sprite:GetDefaultAnimationName(), true)
    data[PLAYER_SPRITE_KEY] = true
end

local function updateHairCostume(_, player)
    local data = player:GetData()

    if not isGeburah(player) then
        data[PLAYER_SPRITE_KEY] = nil
        if data[HAIR_STATE_KEY] ~= nil then
            removeHairCostume(player, HAIR_COSTUME)
            removeHairCostume(player, MONSTROS_LUNG_HAIR_COSTUME)
            data[HAIR_STATE_KEY] = nil
        end
        if data[TAIL_STATE_KEY] then
            removeHairCostume(player, TAIL_COSTUME)
        end
        data[TAIL_STATE_KEY] = nil
        return
    end

    loadPlayerSprite(player)

    local useTailCostume = not player:HasCollectible(JUPITER)
    if data[TAIL_STATE_KEY] ~= useTailCostume then
        removeHairCostume(player, TAIL_COSTUME)
        if useTailCostume then
            addHairCostume(player, TAIL_COSTUME)
        end
        data[TAIL_STATE_KEY] = useTailCostume
    end

    local useMonstrosLungHair = player:HasCollectible(MONSTROS_LUNG)
    if data[HAIR_STATE_KEY] == useMonstrosLungHair then
        return
    end

    removeHairCostume(player, HAIR_COSTUME)
    removeHairCostume(player, MONSTROS_LUNG_HAIR_COSTUME)
    addHairCostume(player, useMonstrosLungHair and MONSTROS_LUNG_HAIR_COSTUME or HAIR_COSTUME)
    data[HAIR_STATE_KEY] = useMonstrosLungHair
end

local function evaluateStats(_, player, cacheFlag)
    if not isGeburah(player) then return end

    updateHairCostume(nil, player)

    if cacheFlag == CacheFlag.CACHE_SPEED then
        player.MoveSpeed = player.MoveSpeed + 0.1
    elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
        local tears = 30 / (player.MaxFireDelay + 1)
        player.MaxFireDelay = 30 / math.max(0.1, tears - 0.43) - 1
    elseif cacheFlag == CacheFlag.CACHE_DAMAGE then
        player.Damage = player.Damage + 0.3
    elseif cacheFlag == CacheFlag.CACHE_RANGE then
        player.TearRange = player.TearRange - 40
    elseif cacheFlag == CacheFlag.CACHE_SHOTSPEED then
        player.ShotSpeed = player.ShotSpeed - 0.15
    elseif cacheFlag == CacheFlag.CACHE_LUCK then
        player.Luck = player.Luck + 1
    end
end

function Geburah.Register(mod, tiaraId)
    local runStarted = false

    local function giveStartingTiara(player)
        if isGeburah(player) and tiaraId > 0
            and not player:HasCollectible(tiaraId) then
            player:AddCollectible(tiaraId, 2, true)
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
        runStarted = true
        if continued then return end
        for index = 0, Game():GetNumPlayers() - 1 do
            giveStartingTiara(Isaac.GetPlayer(index))
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, function(_, player)
        if isGeburah(player) then loadPlayerSprite(player) end
        if runStarted then giveStartingTiara(player) end
    end)

    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
        runStarted = false
    end)

    mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, evaluateStats)
    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, updateHairCostume)
end

return Geburah
