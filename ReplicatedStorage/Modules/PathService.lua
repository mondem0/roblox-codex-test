local PathService = {}

function PathService:GetWaypoints(pathFolder)
    local waypoints = {}
    if not pathFolder then
        warn("No path folder provided to PathService:GetWaypoints")
        return waypoints
    end

    local children = pathFolder:GetChildren()
    table.sort(children, function(a, b)
        return tonumber(a.Name) < tonumber(b.Name)
    end)

    for _, waypointPart in ipairs(children) do
        if waypointPart:IsA("BasePart") then
            table.insert(waypoints, waypointPart.Position)
        end
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
