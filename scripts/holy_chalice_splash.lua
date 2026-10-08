local Splash = {}
local ANIMATION = "gfx/projectiles/bubble_tear_splash.anm2"
local RED_SHEET = "gfx/projectiles/bubble_tear_splash_red.png"
local DURATION = 14
local TEAR_KEY = "AscentionHolyChaliceBubble"

local active = {}
local recent = {}

function Splash.Show(tear)
    local data = tear:GetData()[TEAR_KEY]
    if not data or data.splashShown then return end
    data.splashShown = true

    local sprite = Sprite()
    sprite:Load(ANIMATION, true)
    if data.splashRed then
        sprite:ReplaceSpritesheet(0, RED_SHEET, true)
    end
    local scale = math.min(1, (tear.Scale or 1) * 0.55)
    sprite.Scale = Vector(scale, scale)
    local position = tear.Position
    local frame = Game():GetFrameCount()
    active[#active + 1] = {
        frame = frame, position = position + Vector(0, tear.Height or 0),
        sprite = sprite,
    }
    recent[#recent + 1] = { frame = frame, position = position }
    if #recent > 64 then table.remove(recent, 1) end
end

function Splash.Register(mod)
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_DEATH, function(_, tear)
        Splash.Show(tear)
    end)

    local function hideVanillaSplash(_, effect)
        local frame = Game():GetFrameCount()
        for i = #recent, 1, -1 do
            local death = recent[i]
            if frame - death.frame > 2 then
                table.remove(recent, i)
            elseif effect.Position:DistanceSquared(death.position) <= 256 then
                return false
            end
        end
    end
    for _, variant in ipairs({ EffectVariant.TEAR_POOF_A,
        EffectVariant.TEAR_POOF_B, EffectVariant.TEAR_POOF_SMALL,
        EffectVariant.TEAR_POOF_VERYSMALL }) do
        if variant then
            mod:AddCallback(ModCallbacks.MC_PRE_EFFECT_RENDER,
                hideVanillaSplash, variant)
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
        local frame = Game():GetFrameCount()
        for i = #active, 1, -1 do
            local splash = active[i]
            local age = frame - splash.frame
            if age < 0 or age >= DURATION then
                table.remove(active, i)
            else
                splash.sprite:SetFrame("Poof", age)
                splash.sprite:Render(
                    Isaac.WorldToRenderPosition(splash.position))
            end
        end
    end)

    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
        active = {}
        recent = {}
    end)
end

return Splash
