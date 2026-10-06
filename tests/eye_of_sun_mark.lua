local callbackNames = {
    "MC_POST_GAME_STARTED", "MC_POST_TEAR_INIT", "MC_POST_FIRE_TEAR",
    "MC_POST_TEAR_UPDATE", "MC_POST_FIRE_SPLIT_TEAR", "MC_POST_TEAR_DEATH",
    "MC_PRE_EFFECT_RENDER", "MC_POST_RENDER", "MC_POST_NEW_ROOM",
    "MC_ENTITY_TAKE_DMG", "MC_POST_ENTITY_TAKE_DMG", "MC_NPC_UPDATE",
    "MC_POST_NPC_RENDER",
}
ModCallbacks = {}
for index, name in ipairs(callbackNames) do ModCallbacks[name] = index end
EntityType = { ENTITY_NPC = 5 }
EntityFlag = { FLAG_FRIENDLY = 1 }
FamiliarVariant = { MINISAAC = 1 }
EffectVariant = {
    TEAR_POOF_A = 1, TEAR_POOF_B = 2,
    TEAR_POOF_SMALL = 3, TEAR_POOF_VERYSMALL = 4,
}
Color = function() return {} end
EntityRef = function(entity) return { Entity = entity } end
EntityPtr = function(entity) return { Ref = entity } end
Isaac = { GetPlayerTypeByName = function() return 41 end }

local callbacks = {}
local mod = { AddCallback = function(_, id, callback) callbacks[id] = callback end }
dofile("scripts/characters/eye_of_sun.lua").Register(mod)

local function entity()
    local value = { data = {}, HitPoints = 50, MaxHitPoints = 50 }
    function value:GetData() return self.data end
    function value:ToNPC() return self end
    function value:ToTear() return nil end
    function value:ToPlayer() return nil end
    function value:ToFamiliar() return nil end
    function value:IsActiveEnemy() return true end
    function value:IsVulnerableEnemy() return true end
    function value:HasEntityFlags() return false end
    function value:Exists() return true end
    function value:IsDead() return false end
    function value:AddSlowing(_, duration, amount)
        self.slow = { duration = duration, amount = amount }
    end
    return value
end

local target = entity()
target.data.AscentionEyeOfSun = { stacks = 4 }
local mini = entity()
mini.Variant = FamiliarVariant.MINISAAC
mini.HitPoints = 20
mini.MaxHitPoints = 25
mini.Player = { GetPlayerType = function() return 41 end }
local laser = entity()
laser.data.AscentionMiniIsaacOwner = EntityPtr(mini)
laser.ToFamiliar = function() return nil end
laser.ToPlayer = function() return nil end

local pre = callbacks[ModCallbacks.MC_ENTITY_TAKE_DMG]
local post = callbacks[ModCallbacks.MC_POST_ENTITY_TAKE_DMG]
local source = { Entity = laser }
local modified = pre(nil, target, 10, 0, nil, 0, source)
assert(math.abs(modified.Damage - 11.5) < 0.001)
target.HitPoints = 38.5
post(nil, target, modified.Damage, 0, nil, 0, source)
assert(math.abs(mini.HitPoints - 21.15) < 0.001)

target.HitPoints = 3
modified = pre(nil, target, 10, 0, nil, 0, source)
target.HitPoints = 0
post(nil, target, modified.Damage, 0, nil, 0, source)
assert(math.abs(mini.HitPoints - 21.45) < 0.001)

target.HitPoints = 30
modified = pre(nil, target, 10, 0, nil, 0, nil)
target.HitPoints = 18.5
post(nil, target, modified.Damage, 0, nil, 0, nil)
assert(math.abs(mini.HitPoints - 21.45) < 0.001)

callbacks[ModCallbacks.MC_NPC_UPDATE](nil, target)
assert(target.slow.amount == 0.85 and target.slow.duration == 2)

local unmarked = entity()
assert(pre(nil, unmarked, 10, 0, nil, 0, source) == nil)
callbacks[ModCallbacks.MC_NPC_UPDATE](nil, unmarked)
assert(unmarked.slow == nil)

print("eye_of_sun_mark: OK")
