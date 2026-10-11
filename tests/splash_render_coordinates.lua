local vectorMeta = {}
vectorMeta.__index = vectorMeta
Vector = function(x, y) return setmetatable({ X = x, Y = y }, vectorMeta) end
function vectorMeta.__add(a, b) return Vector(a.X + b.X, a.Y + b.Y) end

local rendered = {}
Sprite = function()
    return {
        Load = function() end,
        ReplaceSpritesheet = function() end,
        SetFrame = function() end,
        Render = function(_, position) rendered[#rendered + 1] = position end,
    }
end

local callbackNames = { "MC_POST_TEAR_DEATH", "MC_PRE_EFFECT_RENDER",
    "MC_POST_RENDER", "MC_POST_NEW_ROOM", "MC_POST_GAME_STARTED",
    "MC_POST_TEAR_INIT", "MC_POST_FIRE_TEAR", "MC_POST_TEAR_UPDATE",
    "MC_POST_FIRE_SPLIT_TEAR", "MC_ENTITY_TAKE_DMG",
    "MC_POST_ENTITY_TAKE_DMG", "MC_NPC_UPDATE", "MC_POST_NPC_RENDER" }
ModCallbacks = {}
for i, name in ipairs(callbackNames) do ModCallbacks[name] = i end
EffectVariant = { TEAR_POOF_A = 1, TEAR_POOF_B = 2,
    TEAR_POOF_SMALL = 3, TEAR_POOF_VERYSMALL = 4 }
TearVariant = { FETUS = 50 }
TearFlags = { TEAR_FETUS = 1 }
EntityType = { ENTITY_NPC = 5 }
Color = function() return {} end
Isaac = {
    GetPlayerTypeByName = function() return 41 end,
    WorldToScreen = function(position)
        return Vector(position.X - 100, position.Y - 40)
    end,
    WorldToRenderPosition = function() error("wrong camera conversion") end,
}
Game = function() return { GetFrameCount = function() return 10 end } end

local function register(path)
    local callbacks = {}
    local mod = { AddCallback = function(_, id, callback)
        callbacks[id] = callback
    end }
    dofile(path).Register(mod)
    return callbacks
end

local bubble = register("scripts/holy_chalice_splash.lua")
local tear = { Position = Vector(300, 200), Height = 0, Scale = 1,
    data = { AscentionHolyChaliceBubble = {} } }
function tear:GetData() return self.data end
bubble[ModCallbacks.MC_POST_TEAR_DEATH](nil, tear)
bubble[ModCallbacks.MC_POST_RENDER]()
assert(rendered[1].X == 200 and rendered[1].Y == 160)

local golden = register("scripts/characters/eye_of_sun.lua")
local goldenTear = { Position = Vector(350, 250), Variant = 0,
    data = { AscentionGeburahGoldenTear = true } }
function goldenTear:GetData() return self.data end
function goldenTear:HasTearFlags() return false end
golden[ModCallbacks.MC_POST_TEAR_DEATH](nil, goldenTear)
golden[ModCallbacks.MC_POST_RENDER]()
assert(rendered[2].X == 250 and rendered[2].Y == 210)

print("splash_render_coordinates: OK")
