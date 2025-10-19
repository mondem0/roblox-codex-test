local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfigs = require(ReplicatedStorage.Modules.Config.EnemyConfigs)
local WaveConfigs = require(ReplicatedStorage.Modules.Config.WaveConfigs)
local PathService = require(ReplicatedStorage.Modules.PathService)
local SoundEffects = require(script.Parent.SoundEffects)
local RunService = game:GetService("RunService")

local WaveService = {}
WaveService.__index = WaveService

local Players = game:GetService("Players")

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end
    return value
end

local function shallowCopyTable(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function toVector3(value)
    if typeof(value) == "Vector3" then
        return value
    elseif type(value) == "table" then
        local x = value.X or value.x or value[1] or 0
        local y = value.Y or value.y or value[2] or 0
        local z = value.Z or value.z or value[3] or 0
        return Vector3.new(x, y, z)
    end
    return nil
end

local function normalizeImmunityMap(raw)
    if type(raw) == "string" then
        local map = {}
        map[string.lower(raw)] = true
        return map
    elseif type(raw) == "table" then
        local map = {}
        local hasArrayValues = #raw > 0

        if hasArrayValues then
            for _, immunity in ipairs(raw) do
                if type(immunity) == "string" then
                    map[string.lower(immunity)] = true
                end
            end
        else
            for key, value in pairs(raw) do
                if value and type(key) == "string" then
                    map[string.lower(key)] = true
                end
            end
        end

        if next(map) then
            return map
        end
    end

    return nil
end

local function enemyImmuneTo(enemyData, debuffType)
    if not enemyData or not debuffType then
        return false
    end

    local immunities = enemyData.DebuffImmunities
    if not immunities then
        return false
    end

    return immunities[string.lower(debuffType)] == true
end

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
    self.TowerService = nil

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

function WaveService:SetTowerService(towerService)
    self.TowerService = towerService
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

    if towerData.Config.SlowPercent and not enemyImmuneTo(enemyData, "Slow") then
        enemyData.Slow = {
            EndsAt = tick() + (towerData.Config.SlowDuration or 2),
            Percent = towerData.Config.SlowPercent
        }
    end

    if enemyData.Health <= 0 then
        self:KillEnemy(enemyModel, enemyData)
    end
end

function WaveService:SplashDamage(origin, radius, towerData, targetEnemy)
    for enemyModel, enemyData in pairs(self.Enemies) do
        if enemyModel.PrimaryPart then
            local distance = (enemyModel.PrimaryPart.Position - origin).Magnitude
            if distance <= radius then
                local isPrimaryTarget = not targetEnemy or enemyModel == targetEnemy
                local immuneToSplash = (not isPrimaryTarget) and enemyImmuneTo(enemyData, "Explosion")
                if not immuneToSplash then
                    self:DamageEnemy(enemyModel, towerData)
                end
            end
        end
    end
end

function WaveService:KillEnemy(enemyModel, enemyData)
    if enemyData and enemyData.HealthValue then
        enemyData.HealthValue.Value = 0
    end
    if enemyModel.Parent then
        local enemyConfig = EnemyConfigs[enemyData.Type] or {}

        if enemyConfig.DeathSound then
            local primary = enemyModel.PrimaryPart
            local soundPosition = primary and primary.Position or nil
            SoundEffects.Play(nil, enemyConfig.DeathSound, {
                Name = string.format("%sDeath", enemyData.Type),
                Position = soundPosition,
            })
        end

        local reward = enemyConfig.Reward or 0
        for player in pairs(self.PlayerStats) do
            self:AdjustMoney(player, reward)
        end

        self:ApplyTowerStunOnDeath(enemyConfig, enemyModel)
        self:SpawnSplitChildren(enemyConfig, enemyData, enemyModel)

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
        self:SpawnGroup(group)
    end
end

function WaveService:SpawnGroup(group)
    if not group then
        return
    end

    if group.Streams then
        local completionEvent = Instance.new("BindableEvent")
        local activeStreams = 0

        local function markStreamFinished()
            activeStreams -= 1
            if activeStreams <= 0 then
                completionEvent:Fire()
            end
        end

        for _, stream in ipairs(group.Streams) do
            local spawnType = stream.Type
            local config = spawnType and EnemyConfigs[spawnType]
            if config then
                activeStreams += 1
                task.spawn(function()
                    local count = math.max(1, stream.Count or 1)
                    local interval = 0
                    if type(stream.Interval) == "number" then
                        interval = math.max(0, stream.Interval)
                    elseif type(stream.Rate) == "number" and stream.Rate > 0 then
                        interval = 1 / stream.Rate
                    elseif type(stream.Delay) == "number" then
                        interval = math.max(0, stream.Delay)
                    end

                    local startDelay = 0
                    if type(stream.StartDelay) == "number" then
                        startDelay = math.max(0, stream.StartDelay)
                    elseif type(stream.InitialDelay) == "number" then
                        startDelay = math.max(0, stream.InitialDelay)
                    end

                    if startDelay > 0 then
                        task.wait(startDelay)
                    end

                    for index = 1, count do
                        if self.GameEnded then
                            break
                        end

                        self:SpawnEnemy(spawnType, config)

                        if index < count and interval > 0 then
                            task.wait(interval)
                        end
                    end

                    markStreamFinished()
                end)
            end
        end

        if activeStreams > 0 then
            completionEvent.Event:Wait()
        end

        completionEvent:Destroy()

        local delay = group.Delay or 0
        if delay > 0 then
            task.wait(delay)
        end

        return
    end

    local enemyType = group.Type
    local config = enemyType and EnemyConfigs[enemyType]
    if not config then
        return
    end

    local count = math.max(1, group.Count or 1)
    local delay = group.Delay or 0
    for index = 1, count do
        if self.GameEnded then
            return
        end
        self:SpawnEnemy(enemyType, config)
        if index < count and delay > 0 then
            task.wait(delay)
        end
    end

    if delay > 0 then
        task.wait(delay)
    end
end

function WaveService:ClampProgress(progress)
    local waypoints = self.PathCache and self.PathCache.Waypoints
    if not waypoints or #waypoints <= 1 then
        return 1
    end

    local maxProgress = #waypoints - 0.001
    return clamp(progress or 1, 1, maxProgress)
end

function WaveService:GetPathCFrame(progress)
    local waypoints = self.PathCache and self.PathCache.Waypoints
    if not waypoints or #waypoints == 0 then
        return nil
    end

    if #waypoints == 1 then
        return CFrame.new(waypoints[1])
    end

    local clampedProgress = self:ClampProgress(progress)
    local index = clamp(math.floor(clampedProgress), 1, #waypoints - 1)
    local nextIndex = clamp(index + 1, 1, #waypoints)
    local startPos = waypoints[index]
    local endPos = waypoints[nextIndex] or startPos
    local alpha = clampedProgress - index
    local position = startPos:Lerp(endPos, alpha)
    return CFrame.new(position, endPos)
end

function WaveService:ApplyTowerStunOnDeath(enemyConfig, enemyModel)
    if not self.TowerService or not enemyConfig then
        return
    end

    local stunConfig = enemyConfig.TowerStunOnDeath or enemyConfig.StunTowersOnDeath or enemyConfig.StunOnDeath
    if type(stunConfig) ~= "table" then
        return
    end

    local radius = tonumber(stunConfig.Radius or stunConfig.Range or stunConfig[1])
    local duration = tonumber(stunConfig.Duration or stunConfig.Time or stunConfig.Length or stunConfig[2])
    if not radius or radius <= 0 or not duration or duration <= 0 then
        return
    end

    local position
    if enemyModel and enemyModel.PrimaryPart then
        position = enemyModel.PrimaryPart.Position
    elseif enemyModel then
        local pivot = enemyModel:GetPivot()
        if pivot then
            position = pivot.Position
        end
    end

    if not position then
        return
    end

    local options = {
        Freeze = stunConfig.Freeze,
        Loop = stunConfig.Loop,
    }

    local soundConfig = stunConfig.Sound or stunConfig.StunSound
    if soundConfig then
        options.Sound = soundConfig
    end

    local soundName = stunConfig.SoundName or stunConfig.SoundLabel
    if soundName and soundName ~= "" then
        options.SoundName = soundName
    end

    self.TowerService:ApplyTowerStun(position, radius, duration, options)
end

function WaveService:SpawnSplitChildren(enemyConfig, enemyData, enemyModel)
    if self.GameEnded then
        return
    end

    local splitConfig = enemyConfig.SplitChildren or enemyConfig.SplitOnDeath
    if type(splitConfig) ~= "table" then
        return
    end

    local entries
    if #splitConfig > 0 then
        entries = splitConfig
    else
        entries = {}
        for childType, entry in pairs(splitConfig) do
            if typeof(childType) == "string" then
                if type(entry) == "number" then
                    table.insert(entries, { Type = childType, Count = entry })
                elseif type(entry) == "table" then
                    local copy = shallowCopyTable(entry)
                    copy.Type = copy.Type or childType
                    table.insert(entries, copy)
                end
            end
        end
    end

    if not entries or #entries == 0 then
        return
    end

    local baseProgress = enemyData and enemyData.Progress or 1
    baseProgress = self:ClampProgress(baseProgress)
    local baseCFrame = nil
    if enemyModel and enemyModel.PrimaryPart then
        baseCFrame = enemyModel.PrimaryPart.CFrame
    end
    local hasPathWaypoints = self.PathCache and self.PathCache.Waypoints and #self.PathCache.Waypoints > 1

    for _, entry in ipairs(entries) do
        local childType = entry.Type or entry.Enemy or entry[1]
        local childConfig = childType and EnemyConfigs[childType]
        if childConfig then
            local count = math.max(1, entry.Count or entry.Quantity or 1)
            local progressOffset = tonumber(entry.ProgressOffset) or 0
            local spacing = entry.ProgressSpacing
            if spacing == nil and count > 1 then
                spacing = 0.04
            end
            spacing = spacing or 0

            local positionOffset = toVector3(entry.Offset or entry.PositionOffset)
            local offsetRadius = tonumber(entry.OffsetRadius)
            local playSpawnSound = entry.PlaySpawnSound == true or entry.UseSpawnSound == true

            for index = 1, count do
                local spawnProgress = self:ClampProgress(baseProgress + progressOffset + spacing * (index - 1))
                local spawnOptions = {
                    Progress = spawnProgress,
                    SkipSpawnSound = not playSpawnSound,
                }

                if baseCFrame and not hasPathWaypoints then
                    spawnOptions.CFrame = baseCFrame
                end

                if positionOffset then
                    spawnOptions.PositionOffset = positionOffset
                elseif offsetRadius and offsetRadius > 0 then
                    local angle = (index - 1) / count * math.pi * 2
                    spawnOptions.PositionOffset = Vector3.new(math.cos(angle) * offsetRadius, 0, math.sin(angle) * offsetRadius)
                end

                self:SpawnEnemy(childType, childConfig, spawnOptions)
            end
        end
    end
end

function WaveService:SpawnEnemy(enemyType, config, options)
    if self.GameEnded then
        return
    end

    local enemyModel, primary, head, isDefault = buildEnemyModel(enemyType, config)
    if not enemyModel or not primary then
        return
    end

    enemyModel.Parent = workspace.Enemies

    local skipSpawnSound = options and options.SkipSpawnSound
    if config.SpawnSound and not skipSpawnSound then
        SoundEffects.Play(primary, config.SpawnSound, {
            Name = string.format("%sSpawn", enemyType),
        })
    end

    local displayName = config.Name or enemyType
    enemyModel:SetAttribute("MaxHealth", config.Health)
    if displayName then
        enemyModel:SetAttribute("DisplayName", displayName)
    end
    local healthValue = enemyModel:FindFirstChild("HealthValue")
    if not healthValue or not healthValue:IsA("NumberValue") then
        healthValue = Instance.new("NumberValue")
        healthValue.Name = "HealthValue"
        healthValue.Parent = enemyModel
    end
    healthValue.Value = config.Health

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

    local partOffsets = {}
    for _, part in ipairs(enemyModel:GetDescendants()) do
        if part:IsA("BasePart") and part ~= primary then
            partOffsets[part] = primary.CFrame:ToObjectSpace(part.CFrame)
        end
    end

    local spawnProgress
    if options and options.Progress then
        spawnProgress = self:ClampProgress(options.Progress)
    end

    self.Enemies[enemyModel] = {
        Type = enemyType,
        Health = config.Health,
        Speed = config.Speed,
        Progress = spawnProgress or 1,
        Slow = nil,
        HealthValue = healthValue,
        PartOffsets = partOffsets,
        DebuffImmunities = normalizeImmunityMap(config.DebuffImmunities),
    }

    local appliedCFrame
    local pathCFrame

    if spawnProgress then
        pathCFrame = self:GetPathCFrame(spawnProgress)
    end

    if options and options.CFrame then
        appliedCFrame = options.CFrame
    elseif pathCFrame then
        appliedCFrame = pathCFrame
    elseif self.PathCache.SpawnCFrame then
        appliedCFrame = self.PathCache.SpawnCFrame
    elseif self.PathCache.Waypoints and self.PathCache.Waypoints[1] then
        appliedCFrame = CFrame.new(self.PathCache.Waypoints[1])
    end

    local offset = options and options.PositionOffset
    if offset then
        offset = toVector3(offset) or offset
        if typeof(offset) == "Vector3" then
            if not appliedCFrame then
                appliedCFrame = CFrame.new(primary.Position)
            end
            appliedCFrame = appliedCFrame * CFrame.new(offset)
        end
    end

    if appliedCFrame then
        primary.CFrame = appliedCFrame
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
    local partOffsets = enemyData.PartOffsets

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
        if partOffsets then
            for part, offset in pairs(partOffsets) do
                if part and part.Parent and part:IsDescendantOf(enemyModel) then
                    part.CFrame = primary.CFrame * offset
                end
            end
        end

        local speed = enemyData.Speed
        if enemyData.Slow then
            if enemyImmuneTo(enemyData, "Slow") then
                enemyData.Slow = nil
            elseif enemyData.Slow.EndsAt > tick() then
                speed = speed * (1 - enemyData.Slow.Percent)
            else
                enemyData.Slow = nil
            end
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
