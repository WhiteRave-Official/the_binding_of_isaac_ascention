local Damage = {}

function Damage.Roll(rng)
    return 0.2 + rng:RandomFloat() * 1.4
end

function Damage.Seeded(seed)
    local rng = RNG()
    rng:SetSeed(seed, 35)
    return Damage.Roll(rng), rng
end

return Damage
