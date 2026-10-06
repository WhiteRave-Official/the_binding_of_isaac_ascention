ActiveSlot = { SLOT_PRIMARY = 0, SLOT_POCKET = 2 }
ModCallbacks = {
    MC_POST_GAME_STARTED = 1,
    MC_POST_PLAYER_INIT = 2,
    MC_POST_PLAYER_UPDATE = 3,
    MC_PRE_GAME_EXIT = 4,
}

local callbacks = {}
local players = {}
local mod = { AddCallback = function(_, id, callback) callbacks[id] = callback end }
Game = function() return { GetNumPlayers = function() return #players end } end
Isaac = { GetPlayer = function(index) return players[index + 1] end }
EntityConfig = {
    GetPlayer = function(playerType)
        return { IsTainted = function() return playerType == 21 end }
    end,
}

local function player(playerType, item, charge, pocket)
    local value = {
        playerType = playerType,
        items = { [0] = item or 0, [2] = pocket or 0 },
        charges = { [0] = charge or 0, [2] = 0 },
        battery = { [0] = 0, [2] = 0 },
    }
    function value:GetPlayerType() return self.playerType end
    function value:GetActiveItem(slot) return self.items[slot] end
    function value:GetActiveCharge(slot) return self.charges[slot] end
    function value:GetBatteryCharge(slot) return self.battery[slot] end
    function value:RemoveCollectible(item, _, slot)
        assert(self.items[slot] == item)
        self.items[slot] = 0
    end
    function value:SetPocketActiveItem(item, slot, keepInPools)
        assert(keepInPools)
        self.items[slot] = item
    end
    function value:SetActiveCharge(charge, slot) self.charges[slot] = charge end
    function value:AddActiveCharge(charge, slot)
        self.battery[slot] = self.battery[slot] + charge
    end
    return value
end

dofile("scripts/characters/starting_pocket_actives.lua").Register(mod)

local isaac = player(0, 105, 6)
local geburah = player(41, 757, 2)
geburah.battery[0] = 1
local taintedIsaac = player(21, 710, 0)
local occupiedPocket = player(1, 45, 0, 123)
players = { isaac, geburah, taintedIsaac, occupiedPocket }
callbacks[ModCallbacks.MC_POST_GAME_STARTED](nil, false)
assert(isaac.items[0] == 0 and isaac.items[2] == 105 and isaac.charges[2] == 6)
assert(geburah.items[0] == 0 and geburah.items[2] == 757)
assert(geburah.charges[2] == 2 and geburah.battery[2] == 1)
assert(taintedIsaac.items[0] == 710 and taintedIsaac.items[2] == 0)
assert(occupiedPocket.items[0] == 45 and occupiedPocket.items[2] == 123)

isaac.items[0] = 300
callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](nil, isaac)
assert(isaac.items[0] == 300 and isaac.items[2] == 105)

local latePlayer = player(2, 34, 4)
callbacks[ModCallbacks.MC_POST_PLAYER_INIT](nil, latePlayer)
callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](nil, latePlayer)
assert(latePlayer.items[0] == 0 and latePlayer.items[2] == 34)

callbacks[ModCallbacks.MC_PRE_GAME_EXIT]()
local continuedPlayer = player(0, 105, 6)
players = { continuedPlayer }
callbacks[ModCallbacks.MC_POST_GAME_STARTED](nil, true)
callbacks[ModCallbacks.MC_POST_PLAYER_INIT](nil, continuedPlayer)
callbacks[ModCallbacks.MC_POST_PLAYER_UPDATE](nil, continuedPlayer)
assert(continuedPlayer.items[0] == 105 and continuedPlayer.items[2] == 0)

print("starting_pocket_actives: OK")
