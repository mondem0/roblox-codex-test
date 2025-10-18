local PathService = {}

function PathService:GetWaypoints(pathFolder)
    local waypoints = {}
    if not pathFolder then
        warn("No path folder provided to PathService:GetWaypoints")
        return waypoints
    end

    local waypointParts = {}

    for _, child in ipairs(pathFolder:GetChildren()) do
        if child:IsA("BasePart") then
            local numericName = tonumber(child.Name)
            if numericName then
                table.insert(waypointParts, {
                    Index = numericName,
                    Position = child.Position,
                })
            else
                warn(string.format(
                    "Ignoring waypoint %s because its name is not numeric",
                    child:GetFullName()
                ))
            end
        end
    end

    table.sort(waypointParts, function(a, b)
        return a.Index < b.Index
    end)

    for _, waypoint in ipairs(waypointParts) do
        table.insert(waypoints, waypoint.Position)
    end

    if #waypoints < 2 then
        warn("Path requires at least two waypoint parts with numeric names")
    end

    return waypoints
end

function PathService:CreatePathCache(mapModel)
    local cache = {}
    if not mapModel then
        return cache
    end

    local pathFolder = mapModel:FindFirstChild("Path")
    if pathFolder then
        cache.Waypoints = self:GetWaypoints(pathFolder)
    else
        warn("Map missing Path folder")
        cache.Waypoints = {}
    end

    if mapModel:FindFirstChild("EnemySpawn") then
        cache.SpawnCFrame = mapModel.EnemySpawn.CFrame
    end

    if mapModel:FindFirstChild("Exit") then
        cache.ExitPosition = mapModel.Exit.Position
    end

    return cache
end

return PathService
