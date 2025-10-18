local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfigs = require(ReplicatedStorage.Modules.Config.EnemyConfigs)
local WaveConfigs = require(ReplicatedStorage.Modules.Config.WaveConfigs)
local PathService = require(ReplicatedStorage.Modules.PathService)
local RunService = game:GetService("RunService")

local WaveService = {}
WaveService.__index = WaveService

local Players = game:GetService("Players")

local function buildEnemyModel(enemyType, config)
    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    local enemiesFolder = assetsFolder and assetsFolder:FindFirstChild("Enemies")
    local modelName = config.ModelName or config.Name or enemyType

    if enemiesFolder and modelName then
        local template = enemiesFolder:FindFirstChild(modelName)
        if template and template:IsA("Model") then
            local cloned = template:Clone()
            cloned.Name = enemyType
            local primary = cloned.PrimaryPart or cloned:FindFirstChild("HumanoidRootPart") or cloned:FindFirstChildWhichIsA("BasePart")
            if not primary then
                cloned:Destroy()
            else
                if cloned.PrimaryPart ~= primary then
                    cloned.PrimaryPart = primary
                end
                for _, descendant in ipairs(cloned:GetDescendants()) do
                    if descendant:IsA("BasePart") then
                        descendant.Anchored = true
                        descendant.CanCollide = false
                    end
                end
                local head = cloned:FindFirstChild("Head")
                return cloned, primary, head, false
            end
        end
    end

    local enemyModel = Instance.new("Model")
    enemyModel.Name = enemyType

    local primary = Instance.new("Part")
    primary.Name = "HumanoidRootPart"
    primary.Size = Vector3.new(2, 3, 2)
    primary.Anchored = true
    primary.CanCollide = false
    primary.Color = Color3.fromRGB(120, 255, 120)
    primary.Parent = enemyModel

    enemyModel.PrimaryPart = primary

    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(2, 1, 2)
    head.Anchored = true
    head.CanCollide = false
    head.Color = Color3.fromRGB(90, 200, 90)
    head.Position = primary.Position + Vector3.new(0, 2, 0)
    head.Parent = enemyModel

    return enemyModel, primary, head, true
end

function WaveService.new(mapModel, remotes)
    local self = setmetatable({}, WaveService)
    self.MapModel = mapModel
    self.Remotes = remotes
    self.Enemies = {}
    self.PathCache = PathService:CreatePathCache(mapModel)
    self.ActiveWave = 0
    self.IsSpawning = false
    self.BaseHealth = 30
    self.PlayerStats = {}
    self.LastTick = tick()
    self.GameEnded = false

    local towersFolder = Instance.new("Folder")
    towersFolder.Name = "Towers"
    towersFolder.Parent = workspace

    local enemiesFolder = Instance.new("Folder")
    enemiesFolder.Name = "Enemies"
    enemiesFolder.Parent = workspace

    Players.PlayerAdded:Connect(function(player)
        self:SetupPlayer(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        self:SetupPlayer(player)
    end

    Players.PlayerRemoving:Connect(function(player)
        self.PlayerStats[player] = nil
    end)

    return self
end

function WaveService:SetupPlayer(player)
    self.PlayerStats[player] = { Money = 350, Lives = self.BaseHealth }
    self.Remotes.MoneyChanged:FireClient(player, self.PlayerStats[player].Money)
    self.Remotes.LivesChanged:FireClient(player, self.BaseHealth)
end

function WaveService:GetPlayerStats(player)
    return self.PlayerStats[player]
end

function WaveService:AdjustMoney(player, amount)
    local stats = self.PlayerStats[player]
    if not stats then
        return
    end
    stats.Money = math.max(0, stats.Money + amount)
    self.Remotes.MoneyChanged:FireClient(player, stats.Money)
end

function WaveService:BroadcastMoney(amount)
    for player, stats in pairs(self.PlayerStats) do
        stats.Money = stats.Money + amount
        self.Remotes.MoneyChanged:FireClient(player, stats.Money)
    end
end

function WaveService:DamageBase(amount)
    self.BaseHealth = math.max(0, self.BaseHealth - amount)
    for player in pairs(self.PlayerStats) do
        self.Remotes.LivesChanged:FireClient(player, self.BaseHealth)
    end
    if self.BaseHealth <= 0 then
        self:GameOver()
    end
end

function WaveService:GameOver()
    self.IsSpawning = false
    self.GameEnded = true
    for enemyModel in pairs(self.Enemies) do
        if enemyModel then
            enemyModel:Destroy()
        end
        self.Enemies[enemyModel] = nil
    end
    self.Remotes.GameEnded:FireAllClients(false)
end

function WaveService:WinGame()
    self.IsSpawning = false
    self.GameEnded = true
    self.Remotes.GameEnded:FireAllClients(true)
end

function WaveService:DamageEnemy(enemyModel, towerData)
    local enemyData = self.Enemies[enemyModel]
    if not enemyData then
        return
    end

    local damageAmount = towerData.Config.Damage or 0
    if damageAmount <= 0 then
        return
    end

    local appliedDamage = math.min(damageAmount, enemyData.Health)
    enemyData.Health -= appliedDamage
    if enemyData.HealthValue then
        enemyData.HealthValue.Value = enemyData.Health
    end

    if towerData.Player then
        self:AdjustMoney(towerData.Player, appliedDamage)
    end

    if towerData.Config.SlowPercent then
        enemyData.Slow = {
            EndsAt = tick() + (towerData.Config.SlowDuration or 2),
            Percent = towerData.Config.SlowPercent
        }
    end

    if enemyData.Health <= 0 then
        self:KillEnemy(enemyModel, enemyData)
    end
end

function WaveService:SplashDamage(origin, radius, towerData)
    for enemyModel, enemyData in pairs(self.Enemies) do
        if enemyModel.PrimaryPart then
            local distance = (enemyModel.PrimaryPart.Position - origin).Magnitude
            if distance <= radius then
                self:DamageEnemy(enemyModel, towerData)
            end
        end
    end
end

function WaveService:KillEnemy(enemyModel, enemyData)
    if enemyData and enemyData.HealthValue then
        enemyData.HealthValue.Value = 0
    end
    if enemyModel.Parent then
        local reward = EnemyConfigs[enemyData.Type].Reward
        for player in pairs(self.PlayerStats) do
            self:AdjustMoney(player, reward)
        end
        enemyModel:Destroy()
    end
    self.Enemies[enemyModel] = nil
    if not self.GameEnded and self:IsWaveComplete() then
        self:BeginNextWave()
    end
end

function WaveService:IsWaveComplete()
    if self.GameEnded then
        return false
    end
    if self.IsSpawning then
        return false
    end

    for _ in pairs(self.Enemies) do
        return false
    end

    return true
end

function WaveService:BeginNextWave()
    if self.GameEnded then
        return
    end
    if self.ActiveWave >= #WaveConfigs then
        self:WinGame()
        return
    end

    self.ActiveWave += 1
    self.IsSpawning = true
    self.Remotes.WaveStarted:FireAllClients(self.ActiveWave)

    task.spawn(function()
        self:SpawnWave(self.ActiveWave)
        self.IsSpawning = false
        if not self.GameEnded and self:IsWaveComplete() then
            self:BeginNextWave()
        end
    end)
end

function WaveService:SpawnWave(waveNumber)
    local wave = WaveConfigs[waveNumber]
    if not wave then
        return
    end

    for _, group in ipairs(wave) do
        if self.GameEnded then
            return
        end
        local config = EnemyConfigs[group.Type]
        if config then
            for _ = 1, group.Count do
                if self.GameEnded then
                    return
                end
                self:SpawnEnemy(group.Type, config)
                task.wait(group.Delay)
            end
        end
    end
end

function WaveService:SpawnEnemy(enemyType, config)
    local enemyModel, primary, head, isDefault = buildEnemyModel(enemyType, config)
    if not enemyModel or not primary then
        return
    end

    enemyModel.Parent = workspace.Enemies

    enemyModel:SetAttribute("MaxHealth", config.Health)
    local healthValue = enemyModel:FindFirstChild("HealthValue")
    if not healthValue or not healthValue:IsA("NumberValue") then
        healthValue = Instance.new("NumberValue")
        healthValue.Name = "HealthValue"
        healthValue.Parent = enemyModel
    end
    healthValue.Value = config.Health

    local healthDisplay = enemyModel:FindFirstChild("HealthDisplay")
    if not healthDisplay or not healthDisplay:IsA("BillboardGui") then
        if healthDisplay then
            healthDisplay:Destroy()
        end
        healthDisplay = Instance.new("BillboardGui")
        healthDisplay.Name = "HealthDisplay"
        healthDisplay.Parent = enemyModel
    end
    healthDisplay.AlwaysOnTop = true
    healthDisplay.Enabled = true
    healthDisplay.ExtentsOffsetWorldSpace = Vector3.new(0, 4, 0)
    healthDisplay.Size = UDim2.new(0, 140, 0, 32)
    healthDisplay.Adornee = primary

    local healthLabel = healthDisplay:FindFirstChildWhichIsA("TextLabel")
    if not healthLabel then
        healthLabel = Instance.new("TextLabel")
        healthLabel.Parent = healthDisplay
    end
    healthLabel.BackgroundTransparency = 1
    healthLabel.TextColor3 = Color3.new(1, 1, 1)
    healthLabel.TextStrokeTransparency = 0.2
    healthLabel.Font = Enum.Font.GothamBold
    healthLabel.TextScaled = true
    healthLabel.Size = UDim2.fromScale(1, 1)

    local maxHealth = config.Health
    local function updateHealthLabel()
        local current = math.max(0, math.floor(healthValue.Value + 0.5))
        if typeof(maxHealth) == "number" then
            healthLabel.Text = string.format("HP: %d / %d", current, maxHealth)
        else
            healthLabel.Text = string.format("HP: %d", current)
        end
    end

    updateHealthLabel()
    healthValue:GetPropertyChangedSignal("Value"):Connect(updateHealthLabel)

    if isDefault then
        if enemyType == "Runner" then
            primary.Color = Color3.fromRGB(255, 200, 80)
        elseif enemyType == "Tank" then
            primary.Color = Color3.fromRGB(80, 120, 255)
            primary.Size = Vector3.new(3, 4, 3)
            if head then
                head.Size = Vector3.new(3, 1.5, 3)
            end
        end
        if head then
            head.CFrame = primary.CFrame * CFrame.new(0, primary.Size.Y / 2 + head.Size.Y / 2, 0)
        end
    end

    local headOffset
    if head then
        headOffset = primary.CFrame:ToObjectSpace(head.CFrame)
    end

    self.Enemies[enemyModel] = {
        Type = enemyType,
        Health = config.Health,
        Speed = config.Speed,
        Progress = 1,
        Slow = nil,
        HealthValue = healthValue,
        HeadOffset = headOffset
    }

    if self.PathCache.SpawnCFrame then
        primary.CFrame = self.PathCache.SpawnCFrame
    elseif self.PathCache.Waypoints and self.PathCache.Waypoints[1] then
        primary.CFrame = CFrame.new(self.PathCache.Waypoints[1])
    end
    task.spawn(function()
        self:MoveEnemy(enemyModel)
    end)
end

function WaveService:ResetGame()
    self.IsSpawning = false
    self.GameEnded = false
    for enemyModel in pairs(self.Enemies) do
        if enemyModel then
            enemyModel:Destroy()
        end
        self.Enemies[enemyModel] = nil
    end
    self.Enemies = {}
    self.ActiveWave = 0
    self.BaseHealth = 30
    for player in pairs(self.PlayerStats) do
        self.PlayerStats[player] = { Money = 350, Lives = self.BaseHealth }
        self.Remotes.MoneyChanged:FireClient(player, 350)
        self.Remotes.LivesChanged:FireClient(player, self.BaseHealth)
    end
end

function WaveService:MoveEnemy(enemyModel)
    local enemyData = self.Enemies[enemyModel]
    if not enemyData then
        return
    end

    local waypoints = self.PathCache.Waypoints
    local primary = enemyModel.PrimaryPart
    local head = enemyModel:FindFirstChild("Head")
    local headOffset = enemyData.HeadOffset

    while enemyModel.Parent and enemyData.Health > 0 do
        if self.GameEnded then
            return
        end
        local index = math.floor(enemyData.Progress)
        local nextIndex = index + 1
        local startPos = waypoints[index]
        local endPos = waypoints[nextIndex]
        if not startPos or not endPos then
            break
        end

        local alpha = enemyData.Progress - index
        local currentPos = startPos:Lerp(endPos, alpha)
        primary.CFrame = CFrame.new(currentPos, endPos)
        if head then
            if headOffset then
                head.CFrame = primary.CFrame * headOffset
            else
                head.CFrame = primary.CFrame * CFrame.new(0, 2, 0)
            end
        end

        local speed = enemyData.Speed
        if enemyData.Slow and enemyData.Slow.EndsAt > tick() then
            speed = speed * (1 - enemyData.Slow.Percent)
        elseif enemyData.Slow and enemyData.Slow.EndsAt <= tick() then
            enemyData.Slow = nil
        end

        local step = RunService.Heartbeat:Wait()
        local segmentLength = (startPos - endPos).Magnitude
        if segmentLength < 0.1 then
            enemyData.Progress = nextIndex
        else
            enemyData.Progress += (speed * step) / segmentLength
        end

        if enemyData.Progress >= #waypoints then
            self:EnemyReachedGoal(enemyModel)
            return
        end
    end
end

function WaveService:EnemyReachedGoal(enemyModel)
    local enemyData = self.Enemies[enemyModel]
    if enemyData then
        if enemyData.HealthValue then
            enemyData.HealthValue.Value = 0
        end
        self:DamageBase(1)
        enemyModel:Destroy()
        self.Enemies[enemyModel] = nil
        if self:IsWaveComplete() then
            self:BeginNextWave()
        end
    end
end

return WaveService
