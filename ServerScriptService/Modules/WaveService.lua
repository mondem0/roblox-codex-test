local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfigs = require(ReplicatedStorage.Modules.Config.EnemyConfigs)
local WaveConfigs = require(ReplicatedStorage.Modules.Config.WaveConfigs)
local PathService = require(ReplicatedStorage.Modules.PathService)
local SoundEffects = require(script.Parent.SoundEffects)
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local WaveService = {}
WaveService.__index = WaveService

function WaveService:BuildOverridePath(enemyModel, enemyData, targetProgress, abilityConfig)
    if not (enemyModel and enemyData) then
        return nil
    end

    local primary = enemyModel.PrimaryPart
    if not primary then
        return nil
    end

    local targetCFrame = self:GetPathCFrame(targetProgress)
    if not targetCFrame then
        return nil
    end

    local startPosition = primary.Position
    local targetPosition = targetCFrame.Position

    if (startPosition - targetPosition).Magnitude < 0.1 then
        return nil
    end

    local usePathfinding = true
    if abilityConfig and abilityConfig.Pathfind ~= nil then
        usePathfinding = abilityConfig.Pathfind ~= false
    end

    local points

    if usePathfinding then
        local success, computed = pcall(function()
            local pathParams = {}

            if abilityConfig then
                if abilityConfig.AgentRadius then
                    pathParams.AgentRadius = tonumber(abilityConfig.AgentRadius)
                end
                if abilityConfig.AgentHeight then
                    pathParams.AgentHeight = tonumber(abilityConfig.AgentHeight)
                end
                if abilityConfig.AgentCanJump ~= nil then
                    pathParams.AgentCanJump = abilityConfig.AgentCanJump ~= false
                end
                if abilityConfig.AgentCanClimb ~= nil then
                    pathParams.AgentCanClimb = abilityConfig.AgentCanClimb ~= false
                end
                if abilityConfig.Costs or abilityConfig.AgentCosts then
                    pathParams.Costs = abilityConfig.Costs or abilityConfig.AgentCosts
                end
            end

            local path = PathfindingService:CreatePath(pathParams)
            path:ComputeAsync(startPosition, targetPosition)
            if path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                local positions = {}
                for _, waypoint in ipairs(waypoints) do
                    table.insert(positions, waypoint.Position)
                end
                return positions
            end

            return nil
        end)

        if success and computed and #computed >= 2 then
            points = computed
        end
    end

    if not points or #points < 2 then
        points = { startPosition, targetPosition }
    else
        if (points[1] - startPosition).Magnitude > 1 then
            table.insert(points, 1, startPosition)
        else
            points[1] = startPosition
        end
        points[#points] = targetPosition
    end

    local speedMultiplier
    if abilityConfig then
        speedMultiplier = tonumber(
            abilityConfig.SpeedMultiplier
            or abilityConfig.SpeedBoost
            or abilityConfig.SpeedScale
        )
    end

    return {
        Points = points,
        Progress = 1,
        TargetProgress = targetProgress,
        TargetCFrame = targetCFrame,
        SpeedMultiplier = speedMultiplier,
    }
end

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

local function normalizeSpawnEntries(raw)
    if type(raw) ~= "table" then
        return nil
    end

    local collected = {}

    if #raw > 0 then
        for _, entry in ipairs(raw) do
            if type(entry) == "string" then
                table.insert(collected, { Type = entry })
            elseif type(entry) == "table" then
                local copy = shallowCopyTable(entry)
                copy.Type = copy.Type or copy.Enemy or copy[1]
                if type(copy.Type) == "string" then
                    table.insert(collected, copy)
                end
            end
        end
    else
        for key, entry in pairs(raw) do
            if type(key) == "string" then
                if type(entry) == "number" then
                    table.insert(collected, { Type = key, Count = entry })
                elseif type(entry) == "table" then
                    local copy = shallowCopyTable(entry)
                    copy.Type = copy.Type or copy.Enemy or key
                    if type(copy.Type) == "string" then
                        table.insert(collected, copy)
                    end
                elseif entry == true then
                    table.insert(collected, { Type = key, Count = 1 })
                end
            end
        end
    end

    if #collected == 0 then
        return nil
    end

    local normalized = {}
    for _, entry in ipairs(collected) do
        local enemyType = entry.Type or entry.Enemy or entry[1]
        if type(enemyType) == "string" then
            local copy = shallowCopyTable(entry)
            copy.Type = enemyType

            local countValue = copy.Count or copy.Quantity or copy.Amount or entry[2]
            countValue = tonumber(countValue)
            if not countValue or countValue < 1 then
                countValue = 1
            else
                countValue = math.floor(countValue)
            end
            copy.Count = math.max(1, countValue)

            table.insert(normalized, copy)
        end
    end

    if #normalized == 0 then
        return nil
    end

    return normalized
end

local function getSkipPromptDelay(waveNumber)
    local definitions = WaveConfigs.Definitions
    if not definitions then
        return nil
    end

    local metadata = definitions[waveNumber]
    if not metadata then
        return nil
    end

    local delay = metadata.SkipPromptDelay or metadata.SkipOfferDelay
    if delay == nil then
        local nested = metadata.Metadata
        if type(nested) == "table" then
            delay = nested.SkipPromptDelay or nested.SkipOfferDelay
        end
    end

    delay = tonumber(delay)
    if delay and delay > 0 then
        return delay
    end

    return nil
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

local function setModelPrimaryCFrame(enemyModel, primary, cframe, partOffsets)
    if not (enemyModel and primary and cframe) then
        return
    end

    primary.CFrame = cframe

    if not partOffsets then
        return
    end

    for part, offset in pairs(partOffsets) do
        if part and part.Parent and part:IsDescendantOf(enemyModel) then
            part.CFrame = cframe * offset
        end
    end
end

local function parseTriggerPercent(value)
    local number = tonumber(value)
    if not number then
        return nil
    end

    if number > 1 then
        number /= 100
    end

    if number <= 0 then
        return nil
    end

    if number > 1 then
        number = 1
    end

    return number
end

local function parseTriggerHealth(value)
    local number = tonumber(value)
    if not number then
        return nil
    end

    if number <= 0 then
        return nil
    end

    return number
end

local function normalizeAbilityType(rawType)
    if type(rawType) ~= "string" then
        return nil
    end

    local lowered = string.lower(rawType)

    if lowered == "skip" or lowered == "skipwaypoints" or lowered == "waypointskip" or lowered == "skipwaypoint" then
        return "SkipWaypoints"
    elseif lowered == "stunpulse" or lowered == "stun" or lowered == "towerstun" or lowered == "stunability" then
        return "StunPulse"
    elseif lowered == "spawnunits" or lowered == "spawn" or lowered == "summon" or lowered == "summonunits" or lowered == "callreinforcements" then
        return "SpawnUnits"
    end

    return nil
end

local AbilityHandlers = {}

local function normalizeAbilityEntry(typeHint, abilityConfig)
    if type(abilityConfig) ~= "table" then
        return nil
    end

    local abilityType = normalizeAbilityType(typeHint or abilityConfig.Type or abilityConfig.Ability)
    if not abilityType then
        return nil
    end

    local configCopy = shallowCopyTable(abilityConfig)
    configCopy.Type = nil
    configCopy.Ability = nil

    local triggerPercent =
        parseTriggerPercent(configCopy.TriggerHealthPercent)
        or parseTriggerPercent(configCopy.TriggerPercent)
        or parseTriggerPercent(configCopy.HealthPercent)
        or parseTriggerPercent(configCopy.Percent)
        or parseTriggerPercent(configCopy.TriggerAtPercent)
        or parseTriggerPercent(configCopy.Trigger)
        or parseTriggerPercent(configCopy.ThresholdPercent)

    local triggerHealth =
        parseTriggerHealth(configCopy.TriggerHealth)
        or parseTriggerHealth(configCopy.Health)
        or parseTriggerHealth(configCopy.TriggerValue)
        or parseTriggerHealth(configCopy.TriggerAtHealth)
        or parseTriggerHealth(configCopy.Threshold)

    if not triggerPercent and not triggerHealth then
        if abilityType == "SkipWaypoints" then
            triggerPercent = 0.5
        elseif abilityType == "StunPulse" then
            triggerPercent = 0.25
        elseif abilityType == "SpawnUnits" then
            triggerPercent = 0.75
        end
    end

    configCopy.TriggerHealthPercent = nil
    configCopy.TriggerPercent = nil
    configCopy.HealthPercent = nil
    configCopy.Percent = nil
    configCopy.TriggerAtPercent = nil
    configCopy.Trigger = nil
    configCopy.ThresholdPercent = nil
    configCopy.TriggerHealth = nil
    configCopy.Health = nil
    configCopy.TriggerValue = nil
    configCopy.TriggerAtHealth = nil
    configCopy.Threshold = nil

    return {
        Type = abilityType,
        Config = configCopy,
        TriggerPercent = triggerPercent,
        TriggerHealth = triggerHealth,
        Triggered = false,
    }
end

local enemyImmuneTo

local function getEnemySpeed(enemyData)
    if not enemyData then
        return 0
    end

    local speed = enemyData.Speed or 0

    if enemyData.Slow then
        if enemyImmuneTo and enemyImmuneTo(enemyData, "Slow") then
            enemyData.Slow = nil
        elseif enemyData.Slow.EndsAt > tick() then
            speed = speed * (1 - enemyData.Slow.Percent)
        else
            enemyData.Slow = nil
        end
    end

    return speed
end

local function appendAbilityEntry(destination, typeHint, abilityConfig)
    if type(abilityConfig) ~= "table" then
        return
    end

    if abilityConfig[1] ~= nil and not abilityConfig.Type and not abilityConfig.Ability then
        for _, nestedConfig in ipairs(abilityConfig) do
            appendAbilityEntry(destination, typeHint, nestedConfig)
        end
        return
    end

    local entry = normalizeAbilityEntry(typeHint, abilityConfig)
    if entry then
        table.insert(destination, entry)
    end
end

local function normalizeAbilities(rawAbilities)
    if type(rawAbilities) ~= "table" then
        return nil
    end

    local normalized = {}

    if #rawAbilities > 0 then
        for _, abilityConfig in ipairs(rawAbilities) do
            appendAbilityEntry(normalized, abilityConfig and (abilityConfig.Type or abilityConfig.Ability), abilityConfig)
        end
    else
        for key, abilityConfig in pairs(rawAbilities) do
            appendAbilityEntry(normalized, key, abilityConfig)
        end
    end

    if #normalized == 0 then
        return nil
    end

    table.sort(normalized, function(a, b)
        local aValue = a.TriggerHealth or ((a.TriggerPercent or 0) * 10000)
        local bValue = b.TriggerHealth or ((b.TriggerPercent or 0) * 10000)
        return aValue > bValue
    end)

    return normalized
end

function AbilityHandlers.SkipWaypoints(self, enemyModel, enemyData, abilityEntry)
    if not (enemyModel and enemyData) then
        return false
    end

    local config = abilityEntry.Config or {}
    local currentProgress = enemyData.Progress or 1

    local targetProgress
    if config.TargetProgress or config.Progress or config.ProgressIndex then
        targetProgress = tonumber(config.TargetProgress or config.Progress or config.ProgressIndex)
    elseif config.Waypoint or config.WaypointIndex then
        targetProgress = tonumber(config.Waypoint or config.WaypointIndex)
    end

    local skipAmount = tonumber(
        config.SkipWaypoints
        or config.SkipCount
        or config.Skip
        or config.Waypoints
        or config.Count
    )

    if not targetProgress then
        skipAmount = skipAmount or 1
        targetProgress = currentProgress + skipAmount
    elseif skipAmount then
        targetProgress += skipAmount
    end

    local offset = tonumber(config.ProgressOffset or config.Offset or config.AdditionalSkip)
    if offset then
        targetProgress = (targetProgress or currentProgress) + offset
    end

    targetProgress = self:ClampProgress(targetProgress or currentProgress)
    if targetProgress <= currentProgress then
        return true
    end

    if config.Teleport == true or config.Instant == true then
        enemyData.Progress = targetProgress
        local finalCFrame = self:GetPathCFrame(targetProgress)
        if finalCFrame then
            local primary = enemyModel.PrimaryPart
            setModelPrimaryCFrame(enemyModel, primary, finalCFrame, enemyData.PartOffsets)
        end
    else
        local override = self:BuildOverridePath(enemyModel, enemyData, targetProgress, config)
        if override then
            enemyData.OverridePath = override
        else
            enemyData.Progress = targetProgress
            local finalCFrame = self:GetPathCFrame(targetProgress)
            if finalCFrame then
                setModelPrimaryCFrame(enemyModel, enemyModel.PrimaryPart, finalCFrame, enemyData.PartOffsets)
            end
        end
    end

    local soundDescriptor = config.Sound or config.SoundId or config.SoundEffect
    if soundDescriptor then
        local soundName = config.SoundName or string.format("%sSkip", enemyData.Type or "Enemy")
        SoundEffects.Play(enemyModel.PrimaryPart, soundDescriptor, {
            Name = soundName,
        })
    end

    return true
end

function AbilityHandlers.StunPulse(self, enemyModel, enemyData, abilityEntry)
    local config = abilityEntry.Config or {}
    return self:TriggerStunPulse(config, enemyModel)
end

function AbilityHandlers.SpawnUnits(self, enemyModel, enemyData, abilityEntry)
    local config = abilityEntry.Config or {}

    local spawnConfig =
        config.Spawns
        or config.Units
        or config.Enemies
        or config.Children
        or config.Summons
        or config.Spawn

    if not spawnConfig then
        spawnConfig = config
    end

    local entries = normalizeSpawnEntries(spawnConfig)
    if not entries then
        return false
    end

    local baseProgress = self:ClampProgress(enemyData and enemyData.Progress or 1)

    local defaultProgressOffset = tonumber(config.ProgressOffset or config.OffsetProgress) or 0
    local defaultSpacing = config.ProgressSpacing or config.Spacing
    local defaultInterval = tonumber(config.Interval or config.SpawnInterval or config.DelayBetween) or 0
    if defaultInterval < 0 then
        defaultInterval = 0
    end
    local defaultStartDelay = tonumber(config.StartDelay or config.Delay or config.InitialDelay) or 0
    if defaultStartDelay < 0 then
        defaultStartDelay = 0
    end
    local defaultPlaySpawnSound
    if config.PlaySpawnSound ~= nil then
        defaultPlaySpawnSound = config.PlaySpawnSound == true
    elseif config.SkipSpawnSound ~= nil then
        defaultPlaySpawnSound = config.SkipSpawnSound == false
    end

    for _, entry in ipairs(entries) do
        local childType = entry.Type
        local childConfig = childType and EnemyConfigs[childType]
        if childConfig then
            local count = math.max(1, tonumber(entry.Count) or 1)

            local progressOffset = entry.ProgressOffset or entry.OffsetProgress
            if progressOffset == nil then
                progressOffset = defaultProgressOffset
            end
            progressOffset = tonumber(progressOffset) or 0

            local spacing = entry.ProgressSpacing or entry.Spacing
            if spacing == nil then
                spacing = defaultSpacing
            end
            spacing = tonumber(spacing) or 0

            local playSpawnSound = entry.PlaySpawnSound
            if playSpawnSound == nil then
                if entry.UseSpawnSound ~= nil then
                    playSpawnSound = entry.UseSpawnSound
                elseif defaultPlaySpawnSound ~= nil then
                    playSpawnSound = defaultPlaySpawnSound
                end
            end
            local useSpawnSound = playSpawnSound == true

            local interval = entry.Interval or entry.SpawnInterval or entry.DelayBetween
            if interval == nil then
                interval = defaultInterval
            end
            interval = tonumber(interval) or 0
            if interval < 0 then
                interval = 0
            end

            local startDelay = entry.StartDelay or entry.Delay or entry.InitialDelay
            if startDelay == nil then
                startDelay = defaultStartDelay
            end
            startDelay = tonumber(startDelay) or 0
            if startDelay < 0 then
                startDelay = 0
            end

            task.spawn(function()
                if startDelay > 0 then
                    task.wait(startDelay)
                end

                for index = 1, count do
                    if self.GameEnded then
                        break
                    end

                    if not (enemyModel and enemyModel.Parent) then
                        break
                    end

                    local sourceData = enemyData
                    if not (sourceData and self.Enemies[enemyModel] == sourceData) then
                        sourceData = self.Enemies[enemyModel]
                    end

                    local currentProgress = baseProgress
                    if sourceData and sourceData.Progress then
                        currentProgress = sourceData.Progress
                    end

                    local spawnProgress = self:ClampProgress(currentProgress + progressOffset + spacing * (index - 1))
                    local spawnOptions = {
                        Progress = spawnProgress,
                        SkipSpawnSound = not useSpawnSound,
                    }

                    local sourcePrimary = enemyModel.PrimaryPart
                    if sourcePrimary then
                        spawnOptions.CFrame = sourcePrimary.CFrame
                    end

                    self:SpawnEnemy(childType, childConfig, spawnOptions)

                    if index < count and interval > 0 then
                        task.wait(interval)
                    end
                end
            end)
        end
    end

    return true
end

function WaveService:NormalizeEnemyAbilities(rawAbilities)
    return normalizeAbilities(rawAbilities)
end

local function toColor3(value)
    if typeof(value) == "Color3" then
        return value
    elseif type(value) == "table" then
        local r = value.R or value.r or value.Red or value.red or value[1]
        local g = value.G or value.g or value.Green or value.green or value[2]
        local b = value.B or value.b or value.Blue or value.blue or value[3]

        if r and g and b then
            r = tonumber(r)
            g = tonumber(g)
            b = tonumber(b)

            if r and g and b then
                if r <= 1 and g <= 1 and b <= 1 then
                    return Color3.new(r, g, b)
                else
                    return Color3.fromRGB(r, g, b)
                end
            end
        end
    elseif type(value) == "string" then
        local hex = value:match("^#?(%x%x%x%x%x%x)$")
        if hex then
            local r = tonumber(hex:sub(1, 2), 16)
            local g = tonumber(hex:sub(3, 4), 16)
            local b = tonumber(hex:sub(5, 6), 16)
            if r and g and b then
                return Color3.fromRGB(r, g, b)
            end
        end
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


enemyImmuneTo = function(enemyData, debuffType)
    if not enemyData or not debuffType then
        return false
    end

    local immunities = enemyData.DebuffImmunities
    if not immunities then
        return false
    end

    return immunities[string.lower(debuffType)] == true
end

function WaveService:TowerCanAffectEnemy(towerData, enemyData)
    if not enemyData then
        return false
    end

    if enemyData.Hidden then
        local config = towerData and towerData.Config
        if not (config and config.HiddenDetection) then
            return false
        end
    end

    return true
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
    self.RoundFinishedCallback = nil
    self.ActivePlayerCount = 1
    self.TotalWaves = #WaveConfigs
    self.SkipOfferToken = 0
    self.ActiveSkipOffer = nil
    self.SkipWaveRequested = false

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

function WaveService:SetActivePlayerCount(count)
    local numeric = tonumber(count) or 1
    numeric = math.max(1, math.floor(numeric + 0.5))
    self.ActivePlayerCount = numeric
end

function WaveService:GetActivePlayerCount()
    return self.ActivePlayerCount or 1
end

function WaveService:BroadcastSkipOffer(payload, targetPlayer)
    if not (self.Remotes and self.Remotes.WaveSkipOfferUpdated) then
        return
    end

    if targetPlayer then
        self.Remotes.WaveSkipOfferUpdated:FireClient(targetPlayer, payload)
    else
        self.Remotes.WaveSkipOfferUpdated:FireAllClients(payload)
    end
end

function WaveService:ClearSkipOffer(reason, extraPayload, forceBroadcast)
    local hadOffer = self.ActiveSkipOffer ~= nil
    local wave = self.ActiveSkipOffer and self.ActiveSkipOffer.Wave or self.ActiveWave
    self.ActiveSkipOffer = nil

    if not (hadOffer or forceBroadcast) then
        return
    end

    local payload = {
        Active = false,
        Wave = wave,
        Reason = reason,
    }

    if type(extraPayload) == "table" then
        for key, value in pairs(extraPayload) do
            payload[key] = value
        end
    end

    self:BroadcastSkipOffer(payload)
end

function WaveService:ShowSkipOffer(waveNumber)
    self.ActiveSkipOffer = {
        Wave = waveNumber,
    }

    local nextWave
    if self.TotalWaves and waveNumber < self.TotalWaves then
        nextWave = waveNumber + 1
    end

    self:BroadcastSkipOffer({
        Active = true,
        Wave = waveNumber,
        NextWave = nextWave,
    })
end

function WaveService:ScheduleSkipOffer(waveNumber)
    local token = self.SkipOfferToken
    local delay = getSkipPromptDelay(waveNumber)
    if not delay or delay <= 0 then
        return
    end

    task.spawn(function()
        task.wait(delay)

        if self.GameEnded then
            return
        end
        if self.ActiveWave ~= waveNumber then
            return
        end
        if self.SkipOfferToken ~= token then
            return
        end
        if self.SkipWaveRequested then
            return
        end
        if self:IsWaveComplete() then
            return
        end

        self:ShowSkipOffer(waveNumber)
    end)
end

function WaveService:RequestWaveSkip(player)
    if self.GameEnded then
        return
    end
    if not player or not self.PlayerStats[player] then
        return
    end

    local offer = self.ActiveSkipOffer
    if not (offer and offer.Wave == self.ActiveWave) then
        return
    end
    if self.SkipWaveRequested then
        return
    end

    local currentWave = self.ActiveWave
    self.SkipWaveRequested = true
    local nextWave
    if self.TotalWaves and currentWave < self.TotalWaves then
        nextWave = currentWave + 1
    end

    local extra = {
        Skipped = true,
        RequestedBy = player.UserId,
        NextWave = nextWave,
    }

    self:ClearSkipOffer("skipped", extra, true)
    self.IsSpawning = false
    local targetWave = (nextWave or (currentWave + 1))
    self:BeginWave(targetWave, false)
end

function WaveService:GetEnemyHealthMultiplier()
    local playerCount = self:GetActivePlayerCount()
    if playerCount <= 1 then
        return 1
    elseif playerCount == 2 then
        return 1.5
    elseif playerCount == 3 then
        return 2
    else
        return 2.5
    end
end

function WaveService:SetMapModel(mapModel)
    self.MapModel = mapModel
    self.PathCache = PathService:CreatePathCache(mapModel)
end

function WaveService:SetRoundFinishedCallback(callback)
    self.RoundFinishedCallback = callback
end

function WaveService:SetupPlayer(player)
    self.PlayerStats[player] = { Money = 350, Lives = self.BaseHealth }
    self.Remotes.MoneyChanged:FireClient(player, self.PlayerStats[player].Money)
    self.Remotes.LivesChanged:FireClient(player, self.BaseHealth)
    if self.TowerService and self.TowerService.SendTowerCounts then
        self.TowerService:SendTowerCounts(player)
    end

    if self.ActiveSkipOffer then
        local wave = self.ActiveSkipOffer.Wave
        local nextWave
        if self.TotalWaves and wave and wave < self.TotalWaves then
            nextWave = wave + 1
        end

        self:BroadcastSkipOffer({
            Active = true,
            Wave = wave,
            NextWave = nextWave,
        }, player)
    end
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
    self.SkipOfferToken += 1
    self.SkipWaveRequested = false
    self:ClearSkipOffer("gameOver", nil, true)
    for enemyModel in pairs(self.Enemies) do
        if enemyModel then
            enemyModel:Destroy()
        end
        self.Enemies[enemyModel] = nil
    end
    self.Remotes.GameEnded:FireAllClients(false)
    if self.RoundFinishedCallback then
        pcall(self.RoundFinishedCallback, false)
    end
end

function WaveService:WinGame()
    self.IsSpawning = false
    self.GameEnded = true
    self.SkipOfferToken += 1
    self.SkipWaveRequested = false
    self:ClearSkipOffer("victory", nil, true)
    self.Remotes.GameEnded:FireAllClients(true)
    if self.RoundFinishedCallback then
        pcall(self.RoundFinishedCallback, true)
    end
end

function WaveService:ActivateEnemyAbility(enemyModel, enemyData, abilityEntry)
    if not (abilityEntry and abilityEntry.Type) then
        return false
    end

    local handler = AbilityHandlers[abilityEntry.Type]
    if not handler then
        return false
    end

    local success = handler(self, enemyModel, enemyData, abilityEntry)
    if success == nil then
        success = true
    end

    return success
end

function WaveService:ProcessEnemyAbilities(enemyModel, enemyData)
    if not enemyData or not enemyData.Abilities or enemyData.Health <= 0 then
        return
    end

    for _, abilityEntry in ipairs(enemyData.Abilities) do
        if abilityEntry.Triggered then
            continue
        end

        local threshold = abilityEntry.CalculatedHealth
        if not threshold then
            if abilityEntry.TriggerHealth then
                threshold = abilityEntry.TriggerHealth
            elseif abilityEntry.TriggerPercent then
                local maxHealth = enemyData.MaxHealth or abilityEntry.MaxHealth
                if not maxHealth and enemyData.HealthValue then
                    maxHealth = enemyData.HealthValue.Value
                end
                maxHealth = maxHealth or enemyData.Health
                if maxHealth then
                    threshold = maxHealth * abilityEntry.TriggerPercent
                end
            end
            abilityEntry.CalculatedHealth = threshold
        end

        if threshold and enemyData.Health <= threshold then
            local activated = self:ActivateEnemyAbility(enemyModel, enemyData, abilityEntry)
            abilityEntry.Triggered = true
            abilityEntry.WasSuccessful = activated
        end
    end
end

function WaveService:DamageEnemy(enemyModel, towerData)
    local enemyData = self.Enemies[enemyModel]
    if not enemyData then
        return
    end

    if not self:TowerCanAffectEnemy(towerData, enemyData) then
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

    if appliedDamage > 0 then
        for player in pairs(self.PlayerStats) do
            self:AdjustMoney(player, appliedDamage)
        end
        self:ProcessEnemyAbilities(enemyModel, enemyData)
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
            if not self:TowerCanAffectEnemy(towerData, enemyData) then
                continue
            end
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
        self:ClearSkipOffer("completed")
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

function WaveService:BeginWave(waveNumber, clearReason)
    if self.GameEnded then
        return
    end
    local totalWaves = self.TotalWaves
    if totalWaves and waveNumber > totalWaves then
        self:WinGame()
        return
    end

    if waveNumber <= self.ActiveWave then
        return
    end

    if clearReason ~= false then
        self:ClearSkipOffer(clearReason or "advance")
    end
    self.SkipOfferToken += 1

    self.ActiveWave = waveNumber
    self.SkipWaveRequested = false
    self.IsSpawning = true
    self.Remotes.WaveStarted:FireAllClients(waveNumber)
    self:ScheduleSkipOffer(waveNumber)

    task.spawn(function()
        local activeWave = waveNumber
        self:SpawnWave(activeWave)
        self.IsSpawning = false
        if not self.GameEnded and self:IsWaveComplete() then
            self:ClearSkipOffer("completed")
            self:BeginNextWave()
        end
    end)
end

function WaveService:BeginNextWave()
    local nextWave = self.ActiveWave + 1
    self:BeginWave(nextWave, "advance")
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
        if self.SkipWaveRequested then
            return
        end
        if self.ActiveWave ~= waveNumber then
            return
        end
        self:SpawnGroup(group, waveNumber)
        if self.SkipWaveRequested or self.ActiveWave ~= waveNumber then
            return
        end
    end
end

function WaveService:SpawnGroup(group, waveNumber)
    if not group then
        return
    end

    local activeWave = waveNumber or self.ActiveWave

    if self.GameEnded or self.SkipWaveRequested or self.ActiveWave ~= activeWave then
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
                    if self.GameEnded or self.SkipWaveRequested or self.ActiveWave ~= activeWave then
                        markStreamFinished()
                        return
                    end

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
                        if self.GameEnded or self.SkipWaveRequested or self.ActiveWave ~= activeWave then
                            markStreamFinished()
                            return
                        end
                    end

                    for index = 1, count do
                        if self.GameEnded or self.SkipWaveRequested or self.ActiveWave ~= activeWave then
                            break
                        end

                        self:SpawnEnemy(spawnType, config)

                        if index < count and interval > 0 then
                            task.wait(interval)
                            if self.GameEnded or self.SkipWaveRequested or self.ActiveWave ~= activeWave then
                                break
                            end
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
            if self.GameEnded or self.SkipWaveRequested or self.ActiveWave ~= activeWave then
                return
            end
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
        if self.GameEnded or self.SkipWaveRequested or self.ActiveWave ~= activeWave then
            return
        end
        self:SpawnEnemy(enemyType, config)
        if index < count and delay > 0 then
            task.wait(delay)
            if self.GameEnded or self.SkipWaveRequested or self.ActiveWave ~= activeWave then
                return
            end
        end
    end

    if delay > 0 then
        task.wait(delay)
        if self.GameEnded or self.SkipWaveRequested or self.ActiveWave ~= activeWave then
            return
        end
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

function WaveService:TriggerStunPulse(stunConfig, enemyModel)
    if not self.TowerService or type(stunConfig) ~= "table" then
        return false
    end

    local radius = tonumber(stunConfig.Radius or stunConfig.Range or stunConfig[1])
    local duration = tonumber(stunConfig.Duration or stunConfig.Time or stunConfig.Length or stunConfig[2])
    if not radius or radius <= 0 or not duration or duration <= 0 then
        return false
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
        return false
    end

    local options = {
        Freeze = stunConfig.Freeze,
        Loop = stunConfig.Loop,
    }

    local effectColor =
        toColor3(stunConfig.EffectColor)
        or toColor3(stunConfig.Color)
        or toColor3(stunConfig.StunColor)
        or toColor3(stunConfig.PulseColor)
        or Color3.fromRGB(140, 225, 255)
    options.EffectColor = effectColor

    local soundConfig = stunConfig.Sound or stunConfig.StunSound
    if not soundConfig then
        soundConfig = stunConfig.SoundId or stunConfig.StunSoundId
    end

    if soundConfig then
        options.Sound = soundConfig
    end

    local soundName = stunConfig.SoundName or stunConfig.SoundLabel
    if soundName and soundName ~= "" then
        options.SoundName = soundName
    end

    local pulseSound =
        stunConfig.PulseSound
        or stunConfig.PulseSoundId
        or stunConfig.ActivationSound
        or stunConfig.AbilitySound
        or stunConfig.CastSound

    if pulseSound then
        options.PulseSound = pulseSound
    end

    local pulseSoundName =
        stunConfig.PulseSoundName
        or stunConfig.ActivationSoundName
        or stunConfig.AbilitySoundName
        or stunConfig.CastSoundName

    if pulseSoundName and pulseSoundName ~= "" then
        options.PulseSoundName = pulseSoundName
    end

    if stunConfig.ForceLoop ~= nil then
        options.Loop = stunConfig.ForceLoop
    end

    if stunConfig.StunFreeze ~= nil then
        options.Freeze = stunConfig.StunFreeze
    end

    self.TowerService:ApplyTowerStun(position, radius, duration, options)
    return true
end

function WaveService:ApplyTowerStunOnDeath(enemyConfig, enemyModel)
    if not enemyConfig then
        return
    end

    local stunConfig = enemyConfig.TowerStunOnDeath or enemyConfig.StunTowersOnDeath or enemyConfig.StunOnDeath
    self:TriggerStunPulse(stunConfig, enemyModel)
end

function WaveService:SpawnSplitChildren(enemyConfig, enemyData, enemyModel)
    if self.GameEnded then
        return
    end

    local splitConfig = enemyConfig.SplitChildren or enemyConfig.SplitOnDeath
    if type(splitConfig) ~= "table" then
        return
    end

    local entries = normalizeSpawnEntries(splitConfig)
    if not entries then
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
        local childType = entry.Type
        local childConfig = childType and EnemyConfigs[childType]
        if childConfig then
            local count = math.max(1, tonumber(entry.Count) or 1)
            local progressOffset = tonumber(entry.ProgressOffset or entry.OffsetProgress) or 0
            local spacing = entry.ProgressSpacing
            if spacing == nil then
                spacing = entry.Spacing
            end
            if spacing == nil and count > 1 then
                spacing = 0.04
            end
            spacing = tonumber(spacing) or 0

            local positionOffset = toVector3(entry.Offset or entry.PositionOffset)
            local offsetRadius = tonumber(entry.OffsetRadius or entry.Radius)
            if offsetRadius and offsetRadius < 0 then
                offsetRadius = 0
            end
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
    local baseHealth = tonumber(config.Health) or 0
    local healthMultiplier = self:GetEnemyHealthMultiplier()
    local scaledHealth = baseHealth
    if baseHealth > 0 then
        scaledHealth = math.max(1, math.floor(baseHealth * healthMultiplier + 0.5))
    end
    enemyModel:SetAttribute("MaxHealth", scaledHealth)
    if displayName then
        enemyModel:SetAttribute("DisplayName", displayName)
    end
    local healthValue = enemyModel:FindFirstChild("HealthValue")
    if not healthValue or not healthValue:IsA("NumberValue") then
        healthValue = Instance.new("NumberValue")
        healthValue.Name = "HealthValue"
        healthValue.Parent = enemyModel
    end
    healthValue.Value = scaledHealth

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

    local hidden = false
    if config.Hidden ~= nil then
        hidden = config.Hidden and true or false
    elseif config.IsHidden ~= nil then
        hidden = config.IsHidden and true or false
    end

    if hidden then
        enemyModel:SetAttribute("IsHidden", true)
    else
        enemyModel:SetAttribute("IsHidden", false)
    end

    self.Enemies[enemyModel] = {
        Type = enemyType,
        Health = scaledHealth,
        MaxHealth = scaledHealth,
        Speed = config.Speed,
        Progress = spawnProgress or 1,
        Slow = nil,
        HealthValue = healthValue,
        PartOffsets = partOffsets,
        DebuffImmunities = normalizeImmunityMap(config.DebuffImmunities),
        Hidden = hidden,
        Abilities = self:NormalizeEnemyAbilities(config.Abilities),
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
    self.SkipOfferToken += 1
    self.SkipWaveRequested = false
    self:ClearSkipOffer("reset", nil, true)
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

    local primary = enemyModel.PrimaryPart
    if not primary then
        return
    end

    local waypoints = self.PathCache.Waypoints or {}
    if #waypoints < 2 then
        return
    end
    local partOffsets = enemyData.PartOffsets

    while enemyModel.Parent and enemyData.Health > 0 do
        if self.GameEnded then
            return
        end

        local override = enemyData.OverridePath
        if override and override.Points and #override.Points >= 2 then
            local points = override.Points
            local progress = override.Progress or 1
            local index = math.floor(progress)
            local nextIndex = math.min(index + 1, #points)
            local startPos = points[index]
            local endPos = points[nextIndex]

            if not startPos or not endPos then
                enemyData.OverridePath = nil
            else
                local alpha = progress - index
                local currentPos = startPos:Lerp(endPos, alpha)
                local delta = endPos - startPos
                local lookVector
                if delta.Magnitude < 0.001 then
                    lookVector = Vector3.new(0, 0, -1)
                else
                    lookVector = delta.Unit
                end

                setModelPrimaryCFrame(enemyModel, primary, CFrame.new(currentPos, currentPos + lookVector), partOffsets)

                local step = RunService.Heartbeat:Wait()
                local speed = getEnemySpeed(enemyData)
                if override.SpeedMultiplier and override.SpeedMultiplier > 0 then
                    speed *= override.SpeedMultiplier
                end

                local segmentLength = (startPos - endPos).Magnitude
                if segmentLength < 0.1 then
                    progress = nextIndex
                else
                    progress += (speed * step) / math.max(segmentLength, 0.001)
                end

                if progress >= #points then
                    enemyData.OverridePath = nil
                    enemyData.Progress = self:ClampProgress(override.TargetProgress or enemyData.Progress)
                    local finalCFrame = override.TargetCFrame or self:GetPathCFrame(enemyData.Progress)
                    if finalCFrame then
                        setModelPrimaryCFrame(enemyModel, primary, finalCFrame, partOffsets)
                    end
                else
                    override.Progress = progress
                end

                if enemyData.Progress >= #waypoints then
                    self:EnemyReachedGoal(enemyModel)
                    return
                end

                continue
            end
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
        setModelPrimaryCFrame(enemyModel, primary, CFrame.new(currentPos, endPos), partOffsets)

        local step = RunService.Heartbeat:Wait()
        local speed = getEnemySpeed(enemyData)
        local segmentLength = (startPos - endPos).Magnitude
        if segmentLength < 0.1 then
            enemyData.Progress = nextIndex
        else
            enemyData.Progress += (speed * step) / math.max(segmentLength, 0.001)
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
            self:ClearSkipOffer("completed")
            self:BeginNextWave()
        end
    end
end

return WaveService
