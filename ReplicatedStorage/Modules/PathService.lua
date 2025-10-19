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

local function findPathFolder(mapModel)
    local direct = mapModel:FindFirstChild("Path")
    if direct and direct:IsA("Folder") then
        return direct
    end

    local descendant = mapModel:FindFirstChild("Path", true)
    if descendant and descendant:IsA("Folder") then
        return descendant
    end

    return nil
end

local function hasMeaningfulChildren(mapModel)
    for _, child in ipairs(mapModel:GetChildren()) do
        -- Ignore temporary folders we create for housekeeping when nothing else exists
        if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
            return true
        end
    end
    return false
end

function PathService:CreatePathCache(mapModel)
    local cache = {}
    if not mapModel then
        return cache
    end

    local pathFolder = findPathFolder(mapModel)
    if pathFolder then
        cache.Waypoints = self:GetWaypoints(pathFolder)
    else
        if hasMeaningfulChildren(mapModel) then
            warn("Map missing Path folder")
        end
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
