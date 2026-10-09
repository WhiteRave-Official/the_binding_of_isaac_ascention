local Proxy = {}
local Context = include("scripts.minisaac.arclight_context")

local MINI_DAMAGE = 0.15
local INCUBUS_DAMAGE = 0.75
local MINI_SCALE = 0.6

function Proxy.IsMini(familiar)
    return Context.MiniForSource(familiar) ~= nil
end

function Proxy.Adopt(tear, player)
    local proxy = Context.ForProjectile(tear)
    if not proxy or proxy.Player ~= player then return false end

    local data = tear:GetData()
    local mini = Context.MiniForSource(proxy)
    if mini then data.AscentionMiniIsaacOwner = EntityPtr(mini) end
    local alreadyAimed = data.AscentionMiniIsaacNativeAimed
    if not data.AscentionMiniIsaacNativeAimed and mini then
        local aim = Context.Aim(proxy, nil)
        if aim and aim:LengthSquared() > 0.01 then
            local velocity = tear.Velocity - (player.Velocity or Vector.Zero) * 1.2
            if velocity:LengthSquared() > 0.01 then
                tear.Velocity = velocity:Rotated(
                    aim:GetAngleDegrees() - velocity:GetAngleDegrees())
                tear.Position = proxy.Position
                data.AscentionMiniIsaacNativeAimed = true
            end
        end
    end
    if not data.AscentionMiniIsaacNativeScaled then
        local lilith = player:GetPlayerType() == PlayerType.PLAYER_LILITH
        tear.CollisionDamage = tear.CollisionDamage
            * MINI_DAMAGE / (lilith and 1 or INCUBUS_DAMAGE)
        if not alreadyAimed then
            tear.Scale = tear.Scale * MINI_SCALE
        end
        data.AscentionMiniIsaacNativeScaled = true
        tear:ResetSpriteScale(true)
    end
    return true
end

return Proxy
