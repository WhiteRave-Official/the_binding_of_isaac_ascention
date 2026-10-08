local Targeting = {}

local MAX_TARGET_DISTANCE_SQUARED = 1000 * 1000

local function isEnemy(entity)
    if not entity or (type(entity) == "table" and entity.kind == "poop") then
        return false
    end
    local npc = entity and entity:ToNPC()
    return npc ~= nil
        and npc.Type ~= EntityType.ENTITY_FIREPLACE
        and npc:Exists()
        and not npc:IsDead()
        and npc:IsActiveEnemy(false)
        and npc:IsVulnerableEnemy()
        and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

local function isFire(entity)
    if not entity or (type(entity) == "table" and entity.kind == "poop") then
        return false
    end
    local npc = entity and entity:ToNPC()
    return npc ~= nil
        and npc.Type == EntityType.ENTITY_FIREPLACE
        and npc:Exists()
        and not npc:IsDead()
        and npc.HitPoints > 0
end

local function getPoop(target)
    local room = Game():GetRoom()
    if room:GetSpawnSeed() ~= target.roomSeed then return nil end
    local grid = room:GetGridEntity(target.gridIndex)
    if grid and grid:GetType() == GridEntityType.GRID_POOP
        and grid.State < 1000
    then
        return grid
    end
    return nil
end

function Targeting.IsEnemy(target)
    return isEnemy(target)
end

function Targeting.IsProp(target)
    if not target then return false end
    if type(target) == "table" and target.kind == "poop" then
        return target.kind == "poop" and getPoop(target) ~= nil
    end
    return isFire(target)
end

function Targeting.IsValid(target)
    return isEnemy(target) or Targeting.IsProp(target)
end

function Targeting.GetPosition(target)
    if type(target) == "table" and target.kind == "poop" then
        local grid = getPoop(target)
        return grid and grid.Position or nil
    end
    return target and target.Position or nil
end

function Targeting.FindEnemy(position)
    local closest, distance, seed = nil, MAX_TARGET_DISTANCE_SQUARED, math.huge
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if isEnemy(entity) then
            local candidateDistance = position:DistanceSquared(entity.Position)
            if candidateDistance < distance
                or (candidateDistance == distance and entity.InitSeed < seed)
            then
                closest, distance, seed = entity, candidateDistance, entity.InitSeed
            end
        end
    end
    return closest
end

function Targeting.FindProp(position)
    local closest, distance = nil, MAX_TARGET_DISTANCE_SQUARED
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if isFire(entity) then
            local candidateDistance = position:DistanceSquared(entity.Position)
            if candidateDistance < distance then
                closest, distance = entity, candidateDistance
            end
        end
    end

    local room = Game():GetRoom()
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        if grid and grid:GetType() == GridEntityType.GRID_POOP
            and grid.State < 1000
        then
            local candidateDistance = position:DistanceSquared(grid.Position)
            if candidateDistance < distance then
                closest = {
                    kind = "poop",
                    gridIndex = index,
                    roomSeed = room:GetSpawnSeed(),
                }
                distance = candidateDistance
            end
        end
    end
    return closest
end

function Targeting.FindTarget(position)
    return Targeting.FindEnemy(position) or Targeting.FindProp(position)
end

return Targeting
