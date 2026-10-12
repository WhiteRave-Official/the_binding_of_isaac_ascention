package.loaded.json = { encode = function(data) return data end,
    decode = function(data) return data end }
ActiveSlot = { SLOT_PRIMARY = 0, SLOT_SECONDARY = 1, SLOT_POCKET = 2 }
EntityType = { ENTITY_FAMILIAR = 3, ENTITY_NPC = 5, ENTITY_DUMMY = 964 }
EntityFlag = { FLAG_FRIENDLY = 1 }
FamiliarVariant = { MINISAAC = 1, INCUBUS = 2 }
ModCallbacks = {}
local names = { "MC_USE_ITEM", "MC_POST_GAME_STARTED", "MC_POST_PLAYER_UPDATE",
    "MC_POST_ADD_COLLECTIBLE", "MC_ENTITY_TAKE_DMG",
    "MC_POST_ENTITY_TAKE_DMG", "MC_POST_NEW_LEVEL", "MC_PRE_GAME_EXIT" }
for index, name in ipairs(names) do ModCallbacks[name] = index end

local callbacks = {}
local saved
local mod = {
    AddCallback = function(_, kind, callback, filter)
        callbacks[kind] = callbacks[kind] or {}
        callbacks[kind][#callbacks[kind] + 1] = { callback, filter }
    end,
    HasData = function() return saved ~= nil end,
    LoadData = function() return saved end,
    SaveData = function(_, data) saved = data end,
}
local function run(kind, filter, ...)
    local result
    for _, entry in ipairs(callbacks[kind] or {}) do
        if entry[2] == nil or entry[2] == filter then
            result = entry[1](mod, ...)
        end
    end
    return result
end

local guardians = {}
local players = {}
local nextSeed = 1
local function vector(x, y)
    return setmetatable({ X = x, Y = y }, {
        __add = function(a, b) return vector(a.X + b.X, a.Y + b.Y) end,
    })
end
Vector = vector
Game = function() return { GetNumPlayers = function() return #players end } end
GetPtrHash = function(entity) return entity end
Isaac = {
    GetPlayerTypeByName = function() return 41 end,
    GetPlayer = function(index) return players[index + 1] end,
    FindByType = function() return guardians end,
    DebugString = function() end,
}
include = function(name)
    return dofile(name:gsub("%.", "/") .. ".lua")
end

local function player(playerType, item)
    local value = { items = { [0] = 0, [1] = 0, [2] = item },
        charges = { [2] = 4 }, battery = { [2] = 0 },
        data = {}, Position = vector(0, 0), Damage = 3.8 }
    function value:GetPlayerType() return playerType end
    function value:ToPlayer() return self end
    function value:GetData() return self.data end
    function value:GetActiveItem(slot) return self.items[slot] end
    function value:GetActiveCharge(slot) return self.charges[slot] or 0 end
    function value:GetBatteryCharge(slot) return self.battery[slot] or 0 end
    function value:RemoveCollectible(item, _, slot)
        assert(self.items[slot] == item)
        self.items[slot] = 0
    end
    function value:SetPocketActiveItem(item, slot)
        self.items[slot] = item
    end
    function value:AddCollectible(item, charge, _, slot)
        self.items[slot] = item
        self.charges[slot] = charge
    end
    function value:SetActiveCharge(charge, slot) self.charges[slot] = charge end
    function value:AddActiveCharge(charge, slot)
        self.battery[slot] = charge
    end
    function value:AddMinisaac(position)
        local mini = { Player = self, Variant = FamiliarVariant.MINISAAC,
            Position = position, HitPoints = 25, MaxHitPoints = 25,
            InitSeed = nextSeed, data = {} }
        nextSeed = nextSeed + 1
        function mini:ToFamiliar() return self end
        function mini:ToPlayer() return nil end
        function mini:Exists() return not self.removed end
        function mini:IsDead() return false end
        function mini:Remove() self.removed = true end
        function mini:GetData() return self.data end
        guardians[#guardians + 1] = mini
        return mini
    end
    return value
end

local geburah = player(41, 101)
local other = player(0, 101)
players = { geburah, other }
local tiara = dofile("scripts/empress_tiara.lua")
tiara.Register(mod, { 101, 102, 103, 104 })
run(ModCallbacks.MC_POST_GAME_STARTED, nil, false)
run(ModCallbacks.MC_POST_PLAYER_UPDATE, nil, geburah)
run(ModCallbacks.MC_POST_PLAYER_UPDATE, nil, other)
assert(tiara.LevelForPlayer(geburah) == 1)
run(ModCallbacks.MC_USE_ITEM, 101, 101, nil, geburah)
assert(#guardians == 1)
guardians[1].HitPoints = 10
run(ModCallbacks.MC_USE_ITEM, 101, 101, nil, geburah)
assert(guardians[1].HitPoints == 22.5, "level I restores half max HP")

local function damage(owner, amount, health)
    local enemy = { HitPoints = health, data = {} }
    function enemy:GetData() return self.data end
    function enemy:ToNPC() return self end
    function enemy:IsVulnerableEnemy() return true end
    function enemy:HasEntityFlags() return false end
    local source = { Entity = owner }
    run(ModCallbacks.MC_ENTITY_TAKE_DMG, EntityType.ENTITY_NPC,
        enemy, amount, 0, source, 0, nil)
    enemy.HitPoints = math.max(0, health - amount)
    run(ModCallbacks.MC_POST_ENTITY_TAKE_DMG, EntityType.ENTITY_NPC,
        enemy, amount, 0, source, 0, nil)
end

damage(geburah, 10000, 10)
assert(tiara.LevelForPlayer(geburah) == 1,
    "overkill must not count beyond remaining health")
local dummy = { Type = EntityType.ENTITY_DUMMY, HitPoints = 0, data = {} }
function dummy:GetData() return self.data end
function dummy:ToNPC() return nil end
local directSource = { Entity = geburah }
run(ModCallbacks.MC_ENTITY_TAKE_DMG, EntityType.ENTITY_DUMMY,
    dummy, 100, 0, directSource, 0, nil)
run(ModCallbacks.MC_POST_ENTITY_TAKE_DMG, EntityType.ENTITY_DUMMY,
    dummy, 100, 0, directSource, 0, nil)
geburah.Damage = 15.2
damage(geburah, 1000, 1000)
assert(tiara.LevelForPlayer(geburah) == 1,
    "high player damage must normalize progress")
geburah.Damage = 3.8
damage(geburah, 1390, 1390)
run(ModCallbacks.MC_POST_PLAYER_UPDATE, nil, geburah)
assert(geburah.items[2] == 102 and geburah.charges[2] == 3)
assert(tiara.LevelForPlayer(other) == 1 and other.items[2] == 101)
run(ModCallbacks.MC_USE_ITEM, 102, 102, nil, geburah)
assert(#guardians == 2)
guardians[1].HitPoints = 1
run(ModCallbacks.MC_USE_ITEM, 102, 102, nil, geburah)
assert(guardians[1].HitPoints == 19.75, "level II restores 75% max HP")

local proxy = { Variant = FamiliarVariant.INCUBUS, data = {
    AscentionMiniIsaacWeaponProxy = true,
    AscentionMiniIsaacProxyOwner = { Ref = guardians[1] },
} }
function proxy:GetData() return self.data end
function proxy:ToFamiliar() return self end
function proxy:ToPlayer() return nil end
local laser = { data = { AscentionMiniIsaacOwner = { Ref = guardians[1] } } }
function laser:GetData() return self.data end
function laser:ToFamiliar() return nil end
function laser:ToPlayer() return nil end
damage(proxy, 2000, 2000)
run(ModCallbacks.MC_POST_PLAYER_UPDATE, nil, geburah)
assert(geburah.items[2] == 103)
run(ModCallbacks.MC_USE_ITEM, 103, 103, nil, geburah)
assert(#guardians == 3, "level III summons three guardians")
guardians[1].HitPoints = 1
run(ModCallbacks.MC_USE_ITEM, 103, 103, nil, geburah)
assert(guardians[1].HitPoints == 22.25,
    "level III restores 85% max HP")
damage(laser, 4000, 4000)
run(ModCallbacks.MC_POST_PLAYER_UPDATE, nil, geburah)
assert(geburah.items[2] == 104 and geburah.charges[2] == 2)
assert(tiara.HealthBonus(geburah) == 10)
geburah.items[0] = 103
geburah.charges[0] = 3
geburah.battery[0] = 1
geburah.data.AscentionEmpressTiaraSyncedLevel = nil
run(ModCallbacks.MC_POST_PLAYER_UPDATE, nil, geburah)
assert(geburah.items[0] == 104 and geburah.charges[0] == 2
    and geburah.battery[0] == 1, "other active slots preserve charge and battery")

run(ModCallbacks.MC_PRE_GAME_EXIT)
run(ModCallbacks.MC_POST_GAME_STARTED, nil, true)
assert(tiara.LevelForPlayer(geburah) == 4, "damage survives continue")

other.items[2] = 104
run(ModCallbacks.MC_POST_ADD_COLLECTIBLE, nil, 104, 0, true, 2, 0, other)
run(ModCallbacks.MC_POST_PLAYER_UPDATE, nil, other)
assert(other.items[2] == 101, "other characters cannot hold upgraded tiaras")
print("empress tiara: OK")
