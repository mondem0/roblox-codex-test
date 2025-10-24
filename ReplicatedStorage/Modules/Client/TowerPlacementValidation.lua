local PlacementValidation = {}
PlacementValidation.__index = PlacementValidation

local function defaultGetter()
        return nil
end

local function ensureGetter(getter)
        if typeof(getter) == "function" then
                return getter
        end
        return defaultGetter
end

function PlacementValidation.new(options)
        assert(options, "PlacementValidation requires options")

        local self = setmetatable({}, PlacementValidation)
        self.player = assert(options.player, "PlacementValidation requires a player reference")
        self.getPreviewPart = ensureGetter(options.getPreviewPart)
        self.getPreviewRangeRing = ensureGetter(options.getPreviewRangeRing)
        self.getRangeRing = ensureGetter(options.getRangeRing)
        self.getPreviewFootprintSize = ensureGetter(options.getPreviewFootprintSize)
        self.getPlacementSurface = assert(options.getPlacementSurface, "PlacementValidation requires getPlacementSurface")
        self.getPlacementPartSet = assert(options.getPlacementPartSet, "PlacementValidation requires getPlacementPartSet")
        self.isValidPlacementSurface = assert(options.isValidPlacementSurface, "PlacementValidation requires isValidPlacementSurface")
        self.CLIFF_PLACEMENT_SURFACE = assert(options.CLIFF_PLACEMENT_SURFACE, "PlacementValidation requires CLIFF_PLACEMENT_SURFACE")
        self.MAX_GROUND_RAYCAST_ATTEMPTS = assert(options.MAX_GROUND_RAYCAST_ATTEMPTS, "PlacementValidation requires MAX_GROUND_RAYCAST_ATTEMPTS")
        self.PLACEMENT_EDGE_EPSILON = assert(options.PLACEMENT_EDGE_EPSILON, "PlacementValidation requires PLACEMENT_EDGE_EPSILON")
        return self
end

function PlacementValidation:createPlacementValidationParams()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true

        local ignoreList = { self.player.Character }
        local previewPart = self.getPreviewPart()
        if previewPart then
                table.insert(ignoreList, previewPart)
        end

        local previewRangeRing = self.getPreviewRangeRing()
        if previewRangeRing then
                table.insert(ignoreList, previewRangeRing)
        end

        local rangeRing = self.getRangeRing()
        if rangeRing then
                table.insert(ignoreList, rangeRing)
        end

        local towersFolder = workspace:FindFirstChild("Towers")
        if towersFolder then
                table.insert(ignoreList, towersFolder)
        end

        params.FilterDescendantsInstances = ignoreList
        return params, ignoreList
end

local function hasAllowedPlacementParts(allowedPlacementParts)
        return allowedPlacementParts and next(allowedPlacementParts) ~= nil
end

function PlacementValidation:findPlacementSurface(position, towerType)
        local map = workspace:FindFirstChild("Map")
        if not map then
                return nil
        end

        local ground = map:FindFirstChild("PathGround")
        local placementSurface = self.getPlacementSurface(towerType)
        local allowedPlacementParts = self.getPlacementPartSet(towerType)
        if not hasAllowedPlacementParts(allowedPlacementParts) and placementSurface ~= self.CLIFF_PLACEMENT_SURFACE and not ground then
                return nil
        end

        local params, ignoreList = self:createPlacementValidationParams()
        local origin = position + Vector3.new(0, 200, 0)
        local direction = Vector3.new(0, -400, 0)

        for _ = 1, self.MAX_GROUND_RAYCAST_ATTEMPTS do
                local result = workspace:Raycast(origin, direction, params)
                if not result then
                        return nil
                end

                local instance = result.Instance
                if instance and instance:IsA("BasePart") then
                        if instance.CanCollide ~= false and (not instance.Transparency or instance.Transparency < 0.95) then
                                if self.isValidPlacementSurface(instance, map, ground, placementSurface, allowedPlacementParts) then
                                        return result
                                end

                                return nil
                        end
                end

                if instance then
                        table.insert(ignoreList, instance)
                        params.FilterDescendantsInstances = ignoreList
                end

                origin = result.Position - Vector3.new(0, 0.05, 0)
        end

        return nil
end

local function resolveFootprintSize(size)
        if typeof(size) == "Vector3" then
                return size
        end

        return Vector3.new()
end

function PlacementValidation:isPositionClear(position)
        local towersFolder = workspace:FindFirstChild("Towers")
        if not towersFolder then
                return true
        end

        local footprintSize = resolveFootprintSize(self.getPreviewFootprintSize())
        local candidateHalfX = math.max(0.05, footprintSize.X / 2)
        local candidateHalfZ = math.max(0.05, footprintSize.Z / 2)

        for _, tower in ipairs(towersFolder:GetChildren()) do
                local primary = tower.PrimaryPart or tower:FindFirstChild("Base")
                if primary then
                        local towerPos = primary.Position
                        local otherHalfX = math.max(0.05, primary.Size.X / 2)
                        local otherHalfZ = math.max(0.05, primary.Size.Z / 2)
                        local deltaX = math.abs(towerPos.X - position.X)
                        local deltaZ = math.abs(towerPos.Z - position.Z)
                        local limitX = otherHalfX + candidateHalfX + self.PLACEMENT_EDGE_EPSILON
                        local limitZ = otherHalfZ + candidateHalfZ + self.PLACEMENT_EDGE_EPSILON
                        if deltaX <= limitX and deltaZ <= limitZ then
                                return false
                        end
                end
        end

        return true
end

function PlacementValidation:evaluatePlacement(towerType, rayResult)
        if not towerType or not rayResult then
                return false
        end

        local hitInstance = rayResult.Instance
        local hitPosition = rayResult.Position
        if not hitInstance or not hitPosition then
                return false
        end

        local map = workspace:FindFirstChild("Map")
        if not map then
                return false
        end

        local ground = map:FindFirstChild("PathGround")
        local placementSurface = self.getPlacementSurface(towerType)
        local allowedPlacementParts = self.getPlacementPartSet(towerType)

        if not hasAllowedPlacementParts(allowedPlacementParts) and placementSurface ~= self.CLIFF_PLACEMENT_SURFACE and not ground then
                return false
        end

        if not hitInstance:IsA("BasePart") then
                return false
        end

        if hitInstance.CanCollide == false then
                return false
        end

        if not self.isValidPlacementSurface(hitInstance, map, ground, placementSurface, allowedPlacementParts) then
                return false
        end

        local placementPosition = Vector3.new(hitPosition.X, hitPosition.Y, hitPosition.Z)

        if not self:isPositionClear(placementPosition) then
                return false
        end

        return true, placementPosition
end

return PlacementValidation
