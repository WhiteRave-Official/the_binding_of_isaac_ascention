local Knife = {}

local KEY = "AscentionHolyChaliceNativeKnife"
local MIN_THROW_DISTANCE = 26
local BURST_ANGLE_SPREAD = 64
local BURST_LATERAL_SPREAD = 32

function Knife.Register(mod, itemId, spawnBubble)
    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, knife)
        local source = knife.SpawnerEntity or knife.Parent
        local player = source and source:ToPlayer()
        if not player or not player:HasCollectible(itemId) then return end

        local data = knife:GetData()
        local playerData = player:GetData()
        local serial = playerData.HolyChaliceKnifeShotSerial or 0
        local distance = knife.Position:Distance(player.Position)
        local state = data[KEY] or { serial = serial, previous = distance,
            throwing = false, burst = false }
        data[KEY] = state
        local charge = playerData.HolyChaliceKnifeChargeFraction
        if not charge or charge <= 0 then
            charge = playerData.HolyChaliceKnifeThrowCharge or 0.25
        end
        if serial ~= state.serial then
            state.serial = serial
            state.throwing = true
            state.burst = false
            state.charge = charge
        elseif not state.throwing and distance > MIN_THROW_DISTANCE
            and distance > state.previous + 5 then
            state.throwing = true
            state.burst = false
            state.charge = charge
        end
        if state.throwing and not state.burst
            and distance >= MIN_THROW_DISTANCE
            and distance > state.previous + 1 then
            state.burst = true
            local direction = (knife.Position - player.Position):Normalized()
            local rng = RNG()
            rng:SetSeed((knife.InitSeed or 1) + serial * 101, 35)
            local count = math.floor(3 + 12 * math.min(1,
                math.max(0, state.charge)) + 0.5)
            for _ = 1, count do
                local angle = (rng:RandomFloat() - 0.5)
                    * BURST_ANGLE_SPREAD
                local lateral = (rng:RandomFloat() - 0.5)
                    * BURST_LATERAL_SPREAD
                local position = knife.Position
                    + direction:Rotated(90) * lateral
                spawnBubble(player, position,
                    direction:Rotated(angle)
                        * ((3 + rng:RandomFloat() * 3) * player.ShotSpeed))
            end
        end

        if state.throwing and distance < MIN_THROW_DISTANCE * 0.5 then
            state.throwing = false
            state.burst = false
        end
        state.previous = distance
    end)
end

return Knife
