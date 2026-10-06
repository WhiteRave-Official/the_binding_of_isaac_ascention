local EyeOfOldGod = {}

local ROLL_KEY = "AscentionOldGodEyeRolled"

function EyeOfOldGod.Chance(luck)
    return 0.15 + math.min(14, math.max(0, luck)) * (0.35 / 14)
end

function EyeOfOldGod.Register(mod, itemId, eyeOfSun)
    local function roll(tear)
        local data = tear:GetData()
        if data[ROLL_KEY] then return end
        local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        if not player or not player:HasCollectible(itemId) then return end
        data[ROLL_KEY] = true
        local rng = RNG()
        rng:SetSeed(tear.InitSeed, 35)
        if rng:RandomFloat() < EyeOfOldGod.Chance(player.Luck) then
            eyeOfSun.MarkOldGodTear(tear)
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, function(_, tear)
        roll(tear)
    end)
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
        roll(tear)
    end)
end

return EyeOfOldGod
