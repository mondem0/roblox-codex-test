local TowerConfigs = require(game.ReplicatedStorage.Modules.Config.TowerConfigs)

local TowerService = {}
TowerService.__index = TowerService

local TOWER_BASE_HALF_SIZE = 2

local function cloneTowerConfig(config)
    local newConfig = {}
    for key, value in pairs(config) do
        newConfig[key] = value
    end
    if config.Upgrades then
        newConfig.Upgrades = config.Upgrades
    end
    return newConfig
end

local function updateTowerAttributes(towerModel, towerData)
    if not towerModel then
        return
    end

    towerModel:SetAttribute("TowerType", towerData.Type)
    towerModel:SetAttribute("Level", towerData.Level)
    towerModel:SetAttribute("Range", towerData.Config.Range or 0)
    towerModel:SetAttribute("OwnerUserId", towerData.Player and towerData.Player.UserId or 0)
end

function TowerService.new(mapModel, waveService, remotes)
    local self = setmetatable({}, TowerService)
    self.MapModel = mapModel
    self.WaveService = waveService
    self.Remotes = remotes
    self.Towers = {}

    if not workspace:FindFirstChild("Towers") then
        local towersFolder = Instance.new("Folder")
        towersFolder.Name = "Towers"
        towersFolder.Parent = workspace
    end

    return self
end

local function buildTowerModel(towerType)
    local towerConfig = TowerConfigs[towerType]
    if not towerConfig then
        return nil
    end

    local model = Instance.new("Model")
    model.Name = towerConfig.Name

    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(TOWER_BASE_HALF_SIZE * 2, 1, TOWER_BASE_HALF_SIZE * 2)
    base.Anchored = true
    base.Material = Enum.Material.SmoothPlastic
    base.Color = Color3.fromRGB(40, 40, 40)
    base.Parent = model

    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(1.5, 2, 1.5)
    head.Anchored = true
    head.CanCollide = false
    head.Material = Enum.Material.Neon
    head.Color = Color3.fromRGB(0, 170, 255)
    head.Parent = model

    if towerType == "Cannon" then
        head.Size = Vector3.new(2.5, 1.5, 2.5)
        head.Color = Color3.fromRGB(20, 20, 20)
    elseif towerType == "FrostMage" then
        head.Color = Color3.fromRGB(160, 220, 255)
    end

    head.CFrame = base.CFrame * CFrame.new(0, (base.Size.Y + head.Size.Y) / 2, 0)

    local barrel = Instance.new("Part")
    barrel.Name = "Barrel"
    barrel.Size = Vector3.new(0.35, 0.35, 2.6)
    barrel.Anchored = true
    barrel.CanCollide = false
    barrel.Material = Enum.Material.Metal
    barrel.Color = Color3.fromRGB(255, 180, 60)
    barrel.Parent = model
    barrel.CFrame = head.CFrame * CFrame.new(0, 0, -(head.Size.Z / 2 + barrel.Size.Z / 2))

    model.PrimaryPart = base

    return model, head, barrel
end

function TowerService:CanAfford(player, towerType)
    local towerConfig = TowerConfigs[towerType]
    if not towerConfig then
        return false
    end
    local stats = self.WaveService:GetPlayerStats(player)
    return stats and stats.Money >= towerConfig.Cost
end

function TowerService:ChargePlayer(player, amount)
    self.WaveService:AdjustMoney(player, -amount)
end

function TowerService:IsPlacementValid(position)
    if not position then
        return false
    end

    local map = workspace:FindFirstChild("Map")
    local ground = map and map:FindFirstChild("PathGround")
    if ground then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.IgnoreWater = true

        local ignoreList = {}
        local towersFolderInstance = workspace:FindFirstChild("Towers")
        if towersFolderInstance then
            table.insert(ignoreList, towersFolderInstance)
        end

        params.FilterDescendantsInstances = ignoreList

        local rayOrigin = Vector3.new(position.X, position.Y + 50, position.Z)
        local rayDirection = Vector3.new(0, -200, 0)
        local result = workspace:Raycast(rayOrigin, rayDirection, params)
        if not result or (result.Instance ~= ground and not result.Instance:IsDescendantOf(ground)) then
            return false
        end
    end

    local towersFolder = workspace:FindFirstChild("Towers")
    if not towersFolder then
        return true
    end

    for _, tower in ipairs(towersFolder:GetChildren()) do
        local primary = tower.PrimaryPart or tower:FindFirstChild("Base")
        if primary then
            local otherPos = primary.Position
            local horizontalDistance = (Vector3.new(otherPos.X, 0, otherPos.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
            local spacing = (primary.Size.X / 2) + TOWER_BASE_HALF_SIZE
            if horizontalDistance < spacing then
                return false
            end
        end
    end

    return true
end

function TowerService:AddTower(player, towerType, position)
    local towerConfig = TowerConfigs[towerType]
    if not towerConfig then
        return
    end

    if not self:IsPlacementValid(position) then
        return
    end

    local towerModel, head, barrel = buildTowerModel(towerType)
    if not towerModel then
        return
    end

    towerModel.Parent = workspace.Towers
    towerModel:SetPrimaryPartCFrame(CFrame.new(position.X, position.Y + towerModel.PrimaryPart.Size.Y / 2, position.Z))

    local base = towerModel.PrimaryPart
    if base and head then
        head.CFrame = base.CFrame * CFrame.new(0, (base.Size.Y + head.Size.Y) / 2, 0)
    end
    if head and barrel then
        barrel.CFrame = head.CFrame * CFrame.new(0, 0, -(head.Size.Z / 2 + barrel.Size.Z / 2))
    end

    local towerData = {
        Player = player,
        Type = towerType,
        Config = cloneTowerConfig(towerConfig),
        Model = towerModel,
        Head = head,
        Barrel = barrel,
        Cooldown = 0,
        Level = 1
    }

    self.Towers[towerModel] = towerData
    updateTowerAttributes(towerModel, towerData)
    return towerModel
end

local function getFarthestEnemyInRange(towerPosition, range, enemies)
    if not range or range <= 0 then
        return nil
    end

    local farthestEnemy
    local highestProgress = -math.huge
    local fallbackDistance = -math.huge

    for enemyModel, enemyData in pairs(enemies) do
        if enemyModel and enemyModel.PrimaryPart and enemyData.Health > 0 then
            local distance = (towerPosition - enemyModel.PrimaryPart.Position).Magnitude
            if distance <= range then
                local progress = enemyData.Progress or 0
                if progress > highestProgress or (progress == highestProgress and distance > fallbackDistance) then
                    highestProgress = progress
                    fallbackDistance = distance
                    farthestEnemy = enemyModel
                end
            end
        end
    end

    return farthestEnemy
end

function TowerService:Tick(dt)
    for towerModel, towerData in pairs(self.Towers) do
        if not towerModel.Parent then
            self.Towers[towerModel] = nil
        else
            towerData.Cooldown = math.max(0, towerData.Cooldown - dt)
            if towerData.Cooldown <= 0 then
                local head = towerData.Head or towerModel:FindFirstChild("Head")
                if head then
                    towerData.Head = head
                end
                if head then
                    local target = getFarthestEnemyInRange(
                        head.Position,
                        towerData.Config.Range,
                        self.WaveService.Enemies
                    )
                    if target then
                        local targetPrimary = target.PrimaryPart
                        if targetPrimary then
                            local headPosition = head.Position
                            local flatTarget = Vector3.new(targetPrimary.Position.X, headPosition.Y, targetPrimary.Position.Z)
                            local lookCFrame = CFrame.new(headPosition, flatTarget)
                            head.CFrame = lookCFrame
                            local barrel = towerData.Barrel or towerModel:FindFirstChild("Barrel")
                            if barrel then
                                towerData.Barrel = barrel
                                barrel.CFrame = lookCFrame * CFrame.new(0, 0, -(head.Size.Z / 2 + barrel.Size.Z / 2))
                            end
                        end
                        towerData.Cooldown = towerData.Config.FireRate
                        if towerData.Config.SplashRadius then
                            self.WaveService:SplashDamage(
                                head.Position,
                                towerData.Config.SplashRadius,
                                towerData
                            )
                        else
                            self.WaveService:DamageEnemy(target, towerData)
                        end
                    end
                end
            end
        end
    end
end

function TowerService:UpgradeTower(player, towerModel)
    local towerData = self.Towers[towerModel]
    if not towerData or towerData.Player ~= player then
        return false, "You do not own this tower"
    end

    local upgrades = towerData.Config.Upgrades
    if not upgrades or towerData.Level >= #upgrades + 1 then
        return false, "Tower fully upgraded"
    end

    local nextUpgrade = upgrades[towerData.Level]
    if not nextUpgrade then
        return false, "No upgrade available"
    end

    local stats = self.WaveService:GetPlayerStats(player)
    if not stats or stats.Money < nextUpgrade.Cost then
        return false, "Not enough money"
    end

    self.WaveService:AdjustMoney(player, -nextUpgrade.Cost)

    for key, value in pairs(nextUpgrade) do
        if key ~= "Cost" and key ~= "Description" then
            towerData.Config[key] = value
        end
    end

    towerData.Level += 1
    updateTowerAttributes(towerModel, towerData)

    self.Remotes.TowerUpgraded:FireClient(player, towerModel, towerData.Level)
    return true
end

return TowerService
