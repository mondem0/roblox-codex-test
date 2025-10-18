local EnemyConfigs = require(game.ReplicatedStorage.Modules.Config.EnemyConfigs)
local PathService = require(game.ReplicatedStorage.Modules.PathService)
local RunService = game:GetService("RunService")

local WaveService = {}
WaveService.__index = WaveService

local Players = game:GetService("Players")

local waves = {
    {
        { Type = "Grunt", Count = 12, Delay = 0.75 },
    },
    {
        { Type = "Grunt", Count = 14, Delay = 0.7 },
        { Type = "Runner", Count = 6, Delay = 0.6 },
    },
    {
        { Type = "Runner", Count = 14, Delay = 0.55 },
        { Type = "Grunt", Count = 16, Delay = 0.65 },
    },
    {
        { Type = "Tank", Count = 6, Delay = 1.3 },
        { Type = "Runner", Count = 10, Delay = 0.6 },
    },
    {
        { Type = "Grunt", Count = 20, Delay = 0.6 },
        { Type = "Tank", Count = 8, Delay = 1.1 },
        { Type = "Runner", Count = 12, Delay = 0.55 },
    }
}

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
    for enemyModel, _ in pairs(self.Enemies) do
        if enemyModel then
            enemyModel:Destroy()
        end
    end
    self.Remotes.GameEnded:FireAllClients(false)
end

function WaveService:WinGame()
    self.IsSpawning = false
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
    if enemyModel.Parent then
        local reward = EnemyConfigs[enemyData.Type].Reward
        for player in pairs(self.PlayerStats) do
            self:AdjustMoney(player, reward)
        end
        enemyModel:Destroy()
    end
    self.Enemies[enemyModel] = nil
    if self:IsWaveComplete() then
        self:BeginNextWave()
    end
end

function WaveService:IsWaveComplete()
    if self.IsSpawning then
        return false
    end

    for _ in pairs(self.Enemies) do
        return false
    end

    return true
end

function WaveService:BeginNextWave()
    if self.ActiveWave >= #waves then
        self:WinGame()
        return
    end

    self.ActiveWave += 1
    self.IsSpawning = true
    self.Remotes.WaveStarted:FireAllClients(self.ActiveWave)

    task.spawn(function()
        self:SpawnWave(self.ActiveWave)
        self.IsSpawning = false
        if self:IsWaveComplete() then
            self:BeginNextWave()
        end
    end)
end

function WaveService:SpawnWave(waveNumber)
    local wave = waves[waveNumber]
    if not wave then
        return
    end

    for _, group in ipairs(wave) do
        local config = EnemyConfigs[group.Type]
        if config then
            for _ = 1, group.Count do
                self:SpawnEnemy(group.Type, config)
                task.wait(group.Delay)
            end
        end
    end
end

function WaveService:SpawnEnemy(enemyType, config)
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

    enemyModel.Parent = workspace.Enemies

    if enemyType == "Runner" then
        primary.Color = Color3.fromRGB(255, 200, 80)
    elseif enemyType == "Tank" then
        primary.Color = Color3.fromRGB(80, 120, 255)
        primary.Size = Vector3.new(3, 4, 3)
        head.Size = Vector3.new(3, 1.5, 3)
    end

    self.Enemies[enemyModel] = {
        Type = enemyType,
        Health = config.Health,
        Speed = config.Speed,
        Progress = 1,
        Slow = nil
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

function WaveService:MoveEnemy(enemyModel)
    local enemyData = self.Enemies[enemyModel]
    if not enemyData then
        return
    end

    local waypoints = self.PathCache.Waypoints
    local primary = enemyModel.PrimaryPart
    local head = enemyModel:FindFirstChild("Head")

    while enemyModel.Parent and enemyData.Health > 0 do
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
            head.CFrame = primary.CFrame * CFrame.new(0, 2, 0)
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
        self:DamageBase(1)
        enemyModel:Destroy()
        self.Enemies[enemyModel] = nil
        if self:IsWaveComplete() then
            self:BeginNextWave()
        end
    end
end

return WaveService
