local Pursuit = {}
local Router = include("scripts.minisaac.incubus_router")

local ASSIST_DISTANCE = 95
local ASSIST_SPEED = 3.5
local ASSIST_BLEND = 0.15

function Pursuit.Register(mod)
    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, function(_, mini)
        if not Router.IsManaging(mini) then return end
        local target = Router.TargetFor(mini)
        if not target then return end

        local delta = target.Position - mini.Position
        if delta:LengthSquared() <= ASSIST_DISTANCE * ASSIST_DISTANCE then return end

        local desired = delta:Normalized() * ASSIST_SPEED
        mini.Velocity = mini.Velocity * (1 - ASSIST_BLEND) + desired * ASSIST_BLEND
    end, FamiliarVariant.MINISAAC)
end

return Pursuit
