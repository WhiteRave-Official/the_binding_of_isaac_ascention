local Formation = {}

local MAX_SHOTS = 8

local function score(params)
    local value = math.max(1, params:GetNumTears())
    value = value + math.max(0, params:GetNumEyesActive() - 1)
    value = value + math.max(0, params:GetNumRandomDirTears())
    if params:IsShootingBackwards() then value = value + 1 end
    if params:IsShootingSideways() then value = value + 2 end
    return value
end

function Formation.Build(player, weaponType, velocity)
    local params = player:GetMultiShotParams(weaponType)
    local parameterType = weaponType
    if weaponType ~= WeaponType.WEAPON_TEARS then
        local tearParams = player:GetMultiShotParams(WeaponType.WEAPON_TEARS)
        if score(tearParams) > score(params) then
            params = tearParams
            parameterType = WeaponType.WEAPON_TEARS
        end
    end

    local speed = math.max(1, velocity:Length())
    local direction = velocity:Normalized()
    local shots = {}
    local count = math.min(MAX_SHOTS, math.max(1, params:GetNumTears()))
    for index = 0, count - 1 do
        local shot = player:GetMultiShotPositionVelocity(
            index, parameterType, direction, speed, params
        )
        shots[#shots + 1] = {
            offset = shot.Position * 4,
            velocity = shot.Velocity,
        }
    end

    local backwardsAdded = false
    local sidewaysAdded = 0
    if params:IsShootingBackwards() and #shots < MAX_SHOTS then
        shots[#shots + 1] = { offset = Vector.Zero, velocity = velocity:Rotated(180) }
        backwardsAdded = true
    end
    if params:IsShootingSideways() then
        for _, angle in ipairs({ -90, 90 }) do
            if #shots < MAX_SHOTS then
                shots[#shots + 1] = {
                    offset = Vector.Zero,
                    velocity = velocity:Rotated(angle),
                }
                sidewaysAdded = sidewaysAdded + 1
            end
        end
    end
    return shots, backwardsAdded and sidewaysAdded == 2
end

return Formation
