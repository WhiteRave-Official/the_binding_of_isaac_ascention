local Damage = {}

function Damage.Roll(rng)
    return 0.4 + rng:RandomFloat()
end

function Damage.Seeded(seed)
    local rng = RNG()
    rng:SetSeed(seed, 35)
    return Damage.Roll(rng), rng
end

return Damage
