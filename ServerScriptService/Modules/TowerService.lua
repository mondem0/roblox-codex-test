local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TowerConfigs = require(ReplicatedStorage.Modules.Config.TowerConfigs)
local SoundEffects = require(script.Parent.SoundEffects)

local TowerService = {}
TowerService.__index = TowerService

local TOWER_BASE_HALF_SIZE = 2
local DEFAULT_BASE_SIZE = Vector3.new(TOWER_BASE_HALF_SIZE * 2, 1, TOWER_BASE_HALF_SIZE * 2)
local PLACEMENT_EDGE_EPSILON = 0.01
local DEFAULT_PLACEMENT_SURFACE = "ground"
local CLIFF_PLACEMENT_SURFACE = "cliff"

local FARM_INCOME_DISPLAY_NAME = "FarmIncomeDisplay"
local FARM_INCOME_LABEL_NAME = "FarmIncomeText"
local FARM_INCOME_BASE_OFFSET = Vector3.new(0, 6, 0)
local FARM_INCOME_FLOAT_OFFSET = Vector3.new(0, 2.5, 0)
local FARM_INCOME_TEXT_COLOR = Color3.fromRGB(80, 255, 110)
local FARM_INCOME_APPEAR_TIME = 0.12
local FARM_INCOME_FLOAT_TIME = 1.75
local FARM_INCOME_FADE_DELAY = 0.95
local FARM_INCOME_FADE_TIME = 0.4

local function formatCurrency(amount)
    local numeric = tonumber(amount)
    if not numeric then
        numeric = 0
    end

    local rounded = math.floor(numeric + 0.5)
    local sign = ""
    if rounded < 0 then
        sign = "-"
        rounded = math.abs(rounded)
    end

    local formatted = tostring(rounded)
    local k
    repeat
        formatted, k = formatted:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until k == 0

    return string.format("%s$%s", sign, formatted)
end

local function normalizePlacementSurfaceValue(value)
    if typeof(value) == "string" then
        local lowered = string.lower(value)
        lowered = lowered:gsub("%s+", "")
        lowered = lowered:gsub("_", "")
        lowered = lowered:gsub("-", "")

        if lowered == "cliff" or lowered == "cliffs" or lowered == "cliffonly" or lowered == "clifftop"
            or lowered == "highground" or lowered == "highgrounds" or lowered == "elevated"
        then
            return CLIFF_PLACEMENT_SURFACE
        end

        if lowered == "ground" or lowered == "path" or lowered == "pathground" or lowered == "default"
            or lowered == "grass" or lowered == "field"
        then
            return DEFAULT_PLACEMENT_SURFACE
        end
    elseif typeof(value) == "table" then
        for _, entry in pairs(value) do
            local normalized = normalizePlacementSurfaceValue(entry)
            if normalized then
                return normalized
            end
        end
    end

    return nil
end

local function getPlacementSurface(towerType)
    local config = towerType and TowerConfigs[towerType]
    if not config then
        return DEFAULT_PLACEMENT_SURFACE
    end

    local surface = normalizePlacementSurfaceValue(config.PlacementSurface)
        or normalizePlacementSurfaceValue(config.SurfaceType)
        or normalizePlacementSurfaceValue(config.RequiredSurface)
        or normalizePlacementSurfaceValue(config.AllowedSurface)

    if not surface and config.CliffOnly == true then
        surface = CLIFF_PLACEMENT_SURFACE
    end

    return surface or DEFAULT_PLACEMENT_SURFACE
end

local function addPlacementPartName(target, value)
    if typeof(value) == "string" then
        local trimmed = string.gsub(value, "^%s*(.-)%s*$", "%1")
        if trimmed ~= "" then
            target[string.lower(trimmed)] = true
        end
    elseif typeof(value) == "Instance" then
        local name = value.Name
        if name and name ~= "" then
            target[string.lower(name)] = true
        end
    elseif typeof(value) == "table" then
        for _, entry in pairs(value) do
            addPlacementPartName(target, entry)
        end
    end
end

local PlacementPartCache = {}

local function getPlacementPartSet(towerType)
    local cached = PlacementPartCache[towerType]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local config = towerType and TowerConfigs[towerType]
    if not config then
        PlacementPartCache[towerType] = false
        return nil
    end

    local partNames = {}
    addPlacementPartName(partNames, config.PlacementSurfacePart)
    addPlacementPartName(partNames, config.PlacementSurfacePartName)
    addPlacementPartName(partNames, config.PlacementSurfaceParts)
    addPlacementPartName(partNames, config.PlacementSurfacePartNames)
    addPlacementPartName(partNames, config.RequiredSurfacePart)
    addPlacementPartName(partNames, config.RequiredSurfaceParts)
    addPlacementPartName(partNames, config.AllowedSurfacePart)
    addPlacementPartName(partNames, config.AllowedSurfaceParts)
    addPlacementPartName(partNames, config.ValidSurfaceParts)
    addPlacementPartName(partNames, config.ValidPlacementParts)

    if next(partNames) then
        PlacementPartCache[towerType] = partNames
        return partNames
    end

    PlacementPartCache[towerType] = false
    return nil
end

local function matchesAllowedPlacementPart(instance, mapModel, allowedParts)
    if not instance or not allowedParts or not next(allowedParts) then
        return false
    end

    local current = instance
    while current do
        if current == mapModel then
            local lowered = string.lower(current.Name)
            if allowedParts[lowered] then
                return true
            end
            break
        end

        local name = current.Name
        if name then
            local lowered = string.lower(name)
            if allowedParts[lowered] then
                if not mapModel or current:IsDescendantOf(mapModel) or current == mapModel then
                    return true
                end
            end
        end

        current = current.Parent
    end

    return false
end

local function isValidPlacementSurface(instance, mapModel, ground, placementSurface, allowedPlacementParts)
    if not instance then
        return false
    end

    if allowedPlacementParts and next(allowedPlacementParts) then
        if matchesAllowedPlacementPart(instance, mapModel, allowedPlacementParts) then
            return true
        end

        return false
    end

    if placementSurface == CLIFF_PLACEMENT_SURFACE then
        if ground and (instance == ground or instance:IsDescendantOf(ground)) then
            return false
        end

        if instance == workspace.Terrain then
            return false
        end

        if not instance:IsA("BasePart") then
            return false
        end

        if mapModel and not instance:IsDescendantOf(mapModel) then
            return false
        end

        if instance.CanCollide == false then
            return false
        end

        return true
    end

    if ground and (instance == ground or instance:IsDescendantOf(ground)) then
        return true
    end

    if instance == workspace.Terrain then
        return true
    end

    return false
end
local TowerFootprints = {}
local TowerLimits = {}
local OverallPlacementLimitCache

local function sanitizeLimitValue(value)
    local numeric = tonumber(value)
    if not numeric then
        return nil
    end

    numeric = math.floor(numeric)
    if numeric <= 0 then
        return nil
    end

    return numeric
end

local function resolvePlacementLimit(towerType)
    local cached = TowerLimits[towerType]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local towerConfig = TowerConfigs[towerType]
    if not towerConfig then
        TowerLimits[towerType] = false
        return nil
    end

    local raw = towerConfig.PlacementLimit or towerConfig.TowerLimit or towerConfig.MaxPlaced
    local limit

    if typeof(raw) == "number" then
        local perPlayer = sanitizeLimitValue(raw)
        if perPlayer then
            limit = {
                PerPlayer = perPlayer,
            }
        end
    elseif typeof(raw) == "table" then
        local normalized = {}

        local perPlayer = raw.PerPlayer or raw.perPlayer or raw.Player or raw.PlayerLimit or raw.MaxPerPlayer or raw.MaxOwned
        local globalLimit = raw.Global or raw.global or raw.Total or raw.total or raw.MaxTotal or raw.MaxGlobal

        perPlayer = sanitizeLimitValue(perPlayer)
        globalLimit = sanitizeLimitValue(globalLimit)

        if perPlayer then
            normalized.PerPlayer = perPlayer
        end

        if globalLimit then
            normalized.Global = globalLimit
        end

        if next(normalized) then
            limit = normalized
        end
    end

    TowerLimits[towerType] = limit or false
    return limit
end

local function getPlacementLimit(towerType)
    local limit = resolvePlacementLimit(towerType)
    if not limit then
        return nil
    end

    return limit
end

local function resolveOverallPlacementLimit()
    if OverallPlacementLimitCache ~= nil then
        if OverallPlacementLimitCache == false then
            return nil
        end
        return OverallPlacementLimitCache
    end

    local settings =
        TowerConfigs.OverallPlacementLimit
        or (TowerConfigs.Placement and TowerConfigs.Placement.OverallLimit)
        or (TowerConfigs.Settings and (
            TowerConfigs.Settings.OverallPlacementLimit
            or TowerConfigs.Settings.OverallLimit
        ))

    local limit

    if typeof(settings) == "number" then
        local perPlayer = sanitizeLimitValue(settings)
        if perPlayer then
            limit = {
                PerPlayer = perPlayer,
            }
        end
    elseif typeof(settings) == "table" then
        local perPlayer = settings.PerPlayer
            or settings.perPlayer
            or settings.Player
            or settings.PlayerLimit
            or settings.MaxPerPlayer
            or settings.MaxOwned

        local globalLimit = settings.Global
            or settings.global
            or settings.Total
            or settings.total
            or settings.GlobalLimit
            or settings.MaxGlobal
            or settings.MaxTotal

        perPlayer = sanitizeLimitValue(perPlayer)
        globalLimit = sanitizeLimitValue(globalLimit)

        local normalized = {}

        if perPlayer then
            normalized.PerPlayer = perPlayer
        end

        if globalLimit then
            normalized.Global = globalLimit
        end

        if next(normalized) then
            limit = normalized
        end
    end

    OverallPlacementLimitCache = limit or false
    return limit
end

local function getOverallPlacementLimit()
    local limit = resolveOverallPlacementLimit()
    if not limit then
        return nil
    end

    return limit
end

local function getTrackedPlayers(towerService)
    local players = {}

    if towerService and towerService.WaveService and towerService.WaveService.PlayerStats then
        for player in pairs(towerService.WaveService.PlayerStats) do
            if player and player.Parent then
                table.insert(players, player)
            end
        end
    end

    if #players > 0 then
        return players
    end

    return Players:GetPlayers()
end

local function getTowerPrimaryPart(model)
    if not model then
        return nil
    end

    local primary = model.PrimaryPart or model:FindFirstChild("Base")
    if primary then
        return primary
    end

    return model:FindFirstChildWhichIsA("BasePart")
end

local function cancelTween(tween)
    if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
        tween:Cancel()
    end
end

local function resetFarmIncomeVisual(towerData)
    local billboard = towerData and towerData.FarmIncomeBillboard
    local label = towerData and towerData.FarmIncomeLabel
    if billboard then
        billboard.Enabled = false
        if towerData.FarmIncomeBaseOffset then
            billboard.StudsOffsetWorldSpace = towerData.FarmIncomeBaseOffset
        end
    end
    if label then
        label.TextTransparency = 1
        label.TextStrokeTransparency = 1
    end
end

local function cleanupFarmIncomeTweens(towerData)
    if not towerData or not towerData.FarmIncomeTweens then
        return
    end

    for _, tween in ipairs(towerData.FarmIncomeTweens) do
        cancelTween(tween)
    end
    towerData.FarmIncomeTweens = nil
end

local function sanitizeIncomeAmount(value)
    local numeric = tonumber(value)
    if not numeric then
        return nil
    end

    numeric = math.floor(numeric + 0.5)
    if numeric < 0 then
        numeric = 0
    end

    return numeric
end

local function resolveFarmIncomeAmount(towerData, fallbackAmount)
    local configIncome
    if towerData and towerData.Config then
        configIncome = sanitizeIncomeAmount(towerData.Config.IncomePerWave)
    end

    if configIncome and configIncome > 0 then
        return configIncome
    end

    local baseConfig
    if towerData and towerData.Type then
        baseConfig = TowerConfigs[towerData.Type]
    end

    if baseConfig then
        local baseIncome = sanitizeIncomeAmount(baseConfig.IncomePerWave)
        if baseIncome and baseIncome > 0 then
            return baseIncome
        end
    end

    local fallback = sanitizeIncomeAmount(fallbackAmount)
    if fallback and fallback > 0 then
        return fallback
    end

    return 0
end

function TowerService:EnsureFarmIncomeDisplay(towerModel, towerData)
    if not towerData or towerData.Type ~= "Farm" then
        return nil
    end

    towerData.FarmIncomeEarned = towerData.FarmIncomeEarned or 0
    towerData.FarmIncomeBaseOffset = towerData.FarmIncomeBaseOffset or FARM_INCOME_BASE_OFFSET

    local model = towerModel or towerData.Model
    if not model or not model.Parent then
        return nil
    end

    local billboard = towerData.FarmIncomeBillboard
    if billboard and billboard.Parent == nil then
        billboard:Destroy()
        billboard = nil
        towerData.FarmIncomeBillboard = nil
        towerData.FarmIncomeLabel = nil
    end

    if not billboard then
        local primary = getTowerPrimaryPart(model)
        if not primary then
            return nil
        end

        billboard = Instance.new("BillboardGui")
        billboard.Name = FARM_INCOME_DISPLAY_NAME
        billboard.Size = UDim2.new(0, 180, 0, 60)
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.MaxDistance = 200
        billboard.StudsOffsetWorldSpace = towerData.FarmIncomeBaseOffset
        billboard.Adornee = primary
        billboard.Enabled = false
        billboard.Parent = model

        local textLabel = Instance.new("TextLabel")
        textLabel.Name = FARM_INCOME_LABEL_NAME
        textLabel.BackgroundTransparency = 1
        textLabel.Font = Enum.Font.GothamBold
        textLabel.TextScaled = true
        textLabel.TextColor3 = FARM_INCOME_TEXT_COLOR
        textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        textLabel.TextStrokeTransparency = 1
        textLabel.TextTransparency = 1
        textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        textLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.Text = ""
        textLabel.Parent = billboard

        towerData.FarmIncomeBillboard = billboard
        towerData.FarmIncomeLabel = textLabel
    else
        if billboard.Parent ~= model then
            billboard.Parent = model
        end

        local primary = getTowerPrimaryPart(model)
        if primary then
            billboard.Adornee = primary
        end

        if towerData.FarmIncomeBaseOffset then
            billboard.StudsOffsetWorldSpace = towerData.FarmIncomeBaseOffset
        end
    end

    resetFarmIncomeVisual(towerData)

    return towerData.FarmIncomeLabel
end

local function formatFarmIncomeBurst(amount)
    local payout = sanitizeIncomeAmount(amount)
    if not payout or payout <= 0 then
        return ""
    end

    return string.format("+%s", formatCurrency(payout))
end

function TowerService:UpdateFarmIncomeDisplay(towerModel, towerData, gainedAmount)
    if not towerData or towerData.Type ~= "Farm" then
        return
    end

    local label = self:EnsureFarmIncomeDisplay(towerModel, towerData)
    local billboard = towerData and towerData.FarmIncomeBillboard
    if not label or not billboard then
        return
    end

    cleanupFarmIncomeTweens(towerData)

    local gain = sanitizeIncomeAmount(gainedAmount) or 0

    if gain <= 0 then
        resetFarmIncomeVisual(towerData)
        label.Text = ""
        return
    end

    local baseOffset = towerData.FarmIncomeBaseOffset or FARM_INCOME_BASE_OFFSET
    local floatOffset = baseOffset + FARM_INCOME_FLOAT_OFFSET

    label.Text = formatFarmIncomeBurst(gain)
    label.TextTransparency = 1
    label.TextStrokeTransparency = 1
    billboard.Enabled = true
    billboard.StudsOffsetWorldSpace = baseOffset

    local appearTween = TweenService:Create(
        label,
        TweenInfo.new(FARM_INCOME_APPEAR_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            TextTransparency = 0,
            TextStrokeTransparency = 0.35,
        }
    )

    local floatTween = TweenService:Create(
        billboard,
        TweenInfo.new(FARM_INCOME_FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            StudsOffsetWorldSpace = floatOffset,
        }
    )

    local fadeTween = TweenService:Create(
        label,
        TweenInfo.new(FARM_INCOME_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
        }
    )

    towerData.FarmIncomeTweens = { appearTween, floatTween, fadeTween }

    appearTween:Play()
    floatTween:Play()
    task.delay(FARM_INCOME_FADE_DELAY, function()
        if towerData.FarmIncomeTweens == nil then
            return
        end
        fadeTween:Play()
    end)

    fadeTween.Completed:Connect(function(state)
        if state ~= Enum.PlaybackState.Completed then
            return
        end

        if towerData.FarmIncomeTweens ~= nil and towerData.FarmIncomeTweens[3] == fadeTween then
            resetFarmIncomeVisual(towerData)
            label.Text = ""
            towerData.FarmIncomeTweens = nil
        end
    end)
end

function TowerService:DestroyFarmIncomeDisplay(towerData)
    if not towerData then
        return
    end

    cleanupFarmIncomeTweens(towerData)

    if towerData.FarmIncomeBillboard then
        towerData.FarmIncomeBillboard:Destroy()
        towerData.FarmIncomeBillboard = nil
    end

    towerData.FarmIncomeLabel = nil
    towerData.FarmIncomeBaseOffset = nil
end

local function stopAndDestroySound(sound)
    if not sound then
        return
    end

    pcall(function()
        sound:Stop()
    end)

    pcall(function()
        sound:Destroy()
    end)
end

local function normalizeBaseSize(value)
    if typeof(value) == "Vector3" then
        return value
    elseif typeof(value) == "table" then
        local x = value.X or value.x or value.Width or value.width or value[1]
        local y = value.Y or value.y or value.Height or value.height or value[2]
        local z = value.Z or value.z or value.Depth or value.depth or value[3]
        if x and y and z then
            return Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
        end
    end

    return nil
end

local function sanitizeBaseSize(size)
    if not size then
        return DEFAULT_BASE_SIZE
    end

    return Vector3.new(
        math.max(0.1, math.abs(size.X)),
        math.max(0.1, math.abs(size.Y)),
        math.max(0.1, math.abs(size.Z))
    )
end

local function getTowerBaseSize(towerType)
    if towerType and TowerFootprints[towerType] then
        return TowerFootprints[towerType]
    end

    local baseSize
    local config = towerType and TowerConfigs[towerType]
    if config then
        baseSize = normalizeBaseSize(config.BaseSize)
    end

    if not baseSize and config then
        local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        local towersFolder = assetsFolder and assetsFolder:FindFirstChild("Towers")
        local modelName = config.ModelName or config.Name or towerType
        if towersFolder and modelName then
            local template = towersFolder:FindFirstChild(modelName)
            if template and template:IsA("Model") then
                local base = template.PrimaryPart or template:FindFirstChild("Base") or template:FindFirstChildWhichIsA("BasePart")
                if base and base:IsA("BasePart") then
                    baseSize = base.Size
                end
            end
        end
    end

    local sanitized = sanitizeBaseSize(baseSize)
    if towerType then
        TowerFootprints[towerType] = sanitized
    end
    return sanitized
end

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

    if towerData.PlacementPosition then
        towerModel:SetAttribute("PlacementPosition", towerData.PlacementPosition)
    end

    local invested = towerData.Invested or 0
    towerModel:SetAttribute("SellValue", math.floor(math.max(0, invested * 0.5)))
end

local function prepareTowerModelFromTemplate(template, towerConfig, towerType)
    if not template or not template:IsA("Model") then
        return nil
    end

    local cloned = template:Clone()
    cloned.Name = towerConfig.Name
    cloned:SetAttribute("TemplateModel", true)

    local base = cloned.PrimaryPart or cloned:FindFirstChild("Base") or cloned:FindFirstChildWhichIsA("BasePart")
    if base and not cloned.PrimaryPart then
        cloned.PrimaryPart = base
    end

    local head = cloned:FindFirstChild("Head")
    local barrel = cloned:FindFirstChild("Barrel")

    for _, descendant in ipairs(cloned:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
        end
    end

    if base then
        base.CanCollide = false
        TowerFootprints[towerType] = TowerFootprints[towerType] or sanitizeBaseSize(base.Size)
    end
    if head and head:IsA("BasePart") then
        head.Anchored = true
        head.CanCollide = false
    end
    if barrel and barrel:IsA("BasePart") then
        barrel.Anchored = true
        barrel.CanCollide = false
    end

    return cloned, head, barrel
end

function TowerService.new(mapModel, waveService, remotes)
    local self = setmetatable({}, TowerService)
    self.MapModel = mapModel
    self.WaveService = waveService
    self.Remotes = remotes
    self.Towers = {}

    TowerLimits = {}
    OverallPlacementLimitCache = nil

    if waveService and typeof(waveService) == "table" and waveService.SetTowerService then
        waveService:SetTowerService(self)
    end

    if not workspace:FindFirstChild("Towers") then
        local towersFolder = Instance.new("Folder")
        towersFolder.Name = "Towers"
        towersFolder.Parent = workspace
    end

    self:BroadcastTowerCounts()

    return self
end

function TowerService:BuildTowerCountSnapshot(player)
    local snapshot = {
        Total = {
            PlayerCount = self:GetOverallTowerCount(player),
            GlobalCount = self:GetOverallTowerCount(),
        },
        Towers = {},
    }

    local overallLimit = getOverallPlacementLimit()
    if overallLimit then
        snapshot.Total.PlayerLimit = overallLimit.PerPlayer
        snapshot.Total.GlobalLimit = overallLimit.Global
    end

    for towerType, config in pairs(TowerConfigs) do
        if typeof(config) == "table" and config.Cost then
            local entry = {
                PlayerCount = self:GetTowerCount(towerType, player),
                GlobalCount = self:GetTowerCount(towerType),
            }

            local limit = getPlacementLimit(towerType)
            if limit then
                entry.PlayerLimit = limit.PerPlayer
                entry.GlobalLimit = limit.Global
            end

            snapshot.Towers[towerType] = entry
        end
    end

    return snapshot
end

function TowerService:SendTowerCounts(player)
    if not (player and self.Remotes and self.Remotes.TowerCountsUpdated) then
        return
    end

    local payload = self:BuildTowerCountSnapshot(player)
    self.Remotes.TowerCountsUpdated:FireClient(player, payload)
end

function TowerService:BroadcastTowerCounts()
    if not (self.Remotes and self.Remotes.TowerCountsUpdated) then
        return
    end

    for _, player in ipairs(getTrackedPlayers(self)) do
        self:SendTowerCounts(player)
    end
end

function TowerService:GrantTowerIncome(towerType, amount)
    if not (self.WaveService and typeof(self.WaveService.AdjustMoney) == "function") then
        return
    end

    if typeof(towerType) ~= "string" or towerType == "" then
        return
    end

    local defaultPayout = sanitizeIncomeAmount(amount)
    if towerType ~= "Farm" then
        if not defaultPayout or defaultPayout <= 0 then
            return
        end
    end

    local rewards = {}

    for _, towerData in pairs(self.Towers) do
        if towerData and towerData.Type == towerType then
            local payout = defaultPayout or 0

            if towerType == "Farm" then
                payout = resolveFarmIncomeAmount(towerData, defaultPayout)
            end

            if payout and payout > 0 then
                local owner = towerData.Player
                if owner then
                    rewards[owner] = (rewards[owner] or 0) + payout
                end

                if towerType == "Farm" then
                    towerData.FarmIncomeEarned = (towerData.FarmIncomeEarned or 0) + payout
                    self:UpdateFarmIncomeDisplay(towerData.Model, towerData, payout)
                end
            elseif towerType == "Farm" then
                self:UpdateFarmIncomeDisplay(towerData.Model, towerData, 0)
            end
        end
    end

    for owner, reward in pairs(rewards) do
        if reward ~= 0 then
            self.WaveService:AdjustMoney(owner, reward)
        end
    end
end

local function buildTowerModel(towerType, overrideConfig)
    local towerConfig = overrideConfig or TowerConfigs[towerType]
    if not towerConfig then
        return nil
    end

    local template
    if typeof(towerConfig.ModelProvider) == "function" then
        local provided = towerConfig.ModelProvider(towerConfig, towerType)
        if typeof(provided) == "Instance" and provided:IsA("Model") then
            template = provided
        end
    elseif typeof(towerConfig.ModelBuilder) == "function" then
        local built = towerConfig.ModelBuilder(towerConfig, towerType)
        if typeof(built) == "Instance" and built:IsA("Model") then
            template = built
        end
    elseif towerConfig.ModelTemplate and typeof(towerConfig.ModelTemplate) == "Instance" then
        template = towerConfig.ModelTemplate
    elseif towerConfig.Model and typeof(towerConfig.Model) == "Instance" then
        template = towerConfig.Model
    end

    if template then
        local builtModel, head, barrel = prepareTowerModelFromTemplate(template, towerConfig, towerType)
        if builtModel then
            return builtModel, head, barrel
        end
    end

    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    local towersFolder = assetsFolder and assetsFolder:FindFirstChild("Towers")
    local modelName = towerConfig.ModelName or towerConfig.Name or towerType
    if towersFolder and modelName then
        local template = towersFolder:FindFirstChild(modelName)
        local builtModel, head, barrel = prepareTowerModelFromTemplate(template, towerConfig, towerType)
        if builtModel then
            return builtModel, head, barrel
        end
    end

    local model = Instance.new("Model")
    model.Name = towerConfig.Name

    local baseSize = sanitizeBaseSize(normalizeBaseSize(towerConfig.BaseSize))
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = baseSize or DEFAULT_BASE_SIZE
    base.Anchored = true
    base.Material = Enum.Material.SmoothPlastic
    base.Color = Color3.fromRGB(40, 40, 40)
    base.CanCollide = false
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
    elseif towerType == "CliffSniper" then
        head.Size = Vector3.new(1.6, 2.4, 1.6)
        head.Color = Color3.fromRGB(235, 235, 215)
        barrel.Size = Vector3.new(0.25, 0.25, 3.4)
        barrel.Color = Color3.fromRGB(210, 210, 210)
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
    TowerFootprints[towerType] = TowerFootprints[towerType] or base.Size

    return model, head, barrel
end

local function captureHeadGeometry(towerModel, head, barrel)
    if not towerModel then
        return nil
    end

    head = head or towerModel:FindFirstChild("Head")
    barrel = barrel or towerModel:FindFirstChild("Barrel") or towerModel:FindFirstChild("Barrel", true)
    if head and head:IsA("Model") and not head.PrimaryPart then
        local pivotCandidate = head:FindFirstChildWhichIsA("BasePart")
        if pivotCandidate then
            head.PrimaryPart = pivotCandidate
        end
    end

    local headPivot
    if head then
        if head:IsA("BasePart") then
            headPivot = head
        elseif head:IsA("Model") then
            headPivot = head.PrimaryPart
        end
    end

    local headOffsets = {}
    if head and headPivot then
        if head:IsA("Model") then
            for _, descendant in ipairs(head:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    headOffsets[descendant] = headPivot.CFrame:ToObjectSpace(descendant.CFrame)
                end
            end
        elseif head:IsA("BasePart") then
            headOffsets[head] = headPivot.CFrame:ToObjectSpace(head.CFrame)
        end
    end

    local barrelOffset
    if barrel and barrel:IsA("BasePart") and headPivot then
        barrelOffset = headPivot.CFrame:ToObjectSpace(barrel.CFrame)
    end

    return {
        Head = head,
        HeadPivot = headPivot,
        HeadOffsets = headOffsets,
        Barrel = barrel,
        BarrelOffset = barrelOffset,
    }
end

local function ensureHeadGeometry(towerData)
    if not towerData then
        return nil
    end

    local headInfo = towerData.HeadInfo
    if headInfo and headInfo.HeadPivot and headInfo.HeadPivot.Parent then
        return headInfo
    end

    headInfo = captureHeadGeometry(towerData.Model, towerData.Head, towerData.Barrel)
    towerData.HeadInfo = headInfo
    if headInfo then
        towerData.Head = headInfo.Head
        towerData.Barrel = headInfo.Barrel
    end
    return headInfo
end

function TowerService:CanAfford(player, towerType)
    local towerConfig = TowerConfigs[towerType]
    if not towerConfig then
        return false
    end

    if self:HasReachedTowerLimit(player, towerType) then
        return false
    end

    local stats = self.WaveService:GetPlayerStats(player)
    return stats and stats.Money >= towerConfig.Cost
end

function TowerService:ChargePlayer(player, amount)
    self.WaveService:AdjustMoney(player, -amount)
end

function TowerService:GetTowerCount(towerType, player)
    if not towerType then
        return 0
    end

    local count = 0
    for _, towerData in pairs(self.Towers) do
        if towerData and towerData.Type == towerType then
            if not player or towerData.Player == player then
                count += 1
            end
        end
    end

    return count
end

function TowerService:GetOverallTowerCount(player)
    local count = 0

    for _, towerData in pairs(self.Towers) do
        if towerData then
            if not player or towerData.Player == player then
                count += 1
            end
        end
    end

    return count
end

function TowerService:HasReachedTowerLimit(player, towerType)
    local overallLimit = getOverallPlacementLimit()
    if overallLimit then
        if overallLimit.PerPlayer and player then
            local ownedTotal = self:GetOverallTowerCount(player)
            if ownedTotal >= overallLimit.PerPlayer then
                return true
            end
        end

        if overallLimit.Global then
            local totalPlaced = self:GetOverallTowerCount()
            if totalPlaced >= overallLimit.Global then
                return true
            end
        end
    end

    local limit = getPlacementLimit(towerType)
    if not limit then
        return false
    end

    if limit.PerPlayer and player then
        local ownedCount = self:GetTowerCount(towerType, player)
        if ownedCount >= limit.PerPlayer then
            return true
        end
    end

    if limit.Global then
        local totalCount = self:GetTowerCount(towerType)
        if totalCount >= limit.Global then
            return true
        end
    end

    return false
end

function TowerService:IsPlacementValid(position, towerType)
    if not position then
        return false
    end

    local map = workspace:FindFirstChild("Map")
    if not map then
        return false
    end

    local ground = map:FindFirstChild("PathGround")
    local placementSurface = getPlacementSurface(towerType)
    local allowedPlacementParts = getPlacementPartSet(towerType)
    if (not allowedPlacementParts or not next(allowedPlacementParts)) and placementSurface ~= CLIFF_PLACEMENT_SURFACE and not ground then
        return false
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true

    local ignoreList = {}
    local towersFolderInstance = workspace:FindFirstChild("Towers")
    if towersFolderInstance then
        table.insert(ignoreList, towersFolderInstance)
    end

    params.FilterDescendantsInstances = ignoreList

    local rayOrigin = Vector3.new(position.X, position.Y + 200, position.Z)
    local rayDirection = Vector3.new(0, -400, 0)
    local result

    for _ = 1, 10 do
        result = workspace:Raycast(rayOrigin, rayDirection, params)
        if not result then
            return false
        end

        local instance = result.Instance
        if instance and instance:IsA("BasePart") then
            if instance.CanCollide ~= false then
                break
            end
        end

        if instance then
            table.insert(ignoreList, instance)
            params.FilterDescendantsInstances = ignoreList
        end
        rayOrigin = result.Position - Vector3.new(0, 0.05, 0)
    end

    if not result or not result.Instance then
        return false
    end

    if not isValidPlacementSurface(result.Instance, map, ground, placementSurface, allowedPlacementParts) then
        return false
    end

    local resolvedPosition = Vector3.new(result.Position.X, result.Position.Y, result.Position.Z)

    local candidateSize = getTowerBaseSize(towerType)
    local candidateHalfX = math.max(0.05, candidateSize.X / 2)
    local candidateHalfZ = math.max(0.05, candidateSize.Z / 2)

    local towersFolder = workspace:FindFirstChild("Towers")
    if towersFolder then
        for _, tower in ipairs(towersFolder:GetChildren()) do
            local primary = tower.PrimaryPart or tower:FindFirstChild("Base")
            if primary then
                local otherPos = primary.Position
                local otherSize = sanitizeBaseSize(primary.Size)
                local otherHalfX = math.max(0.05, otherSize.X / 2)
                local otherHalfZ = math.max(0.05, otherSize.Z / 2)
                local deltaX = math.abs(otherPos.X - resolvedPosition.X)
                local deltaZ = math.abs(otherPos.Z - resolvedPosition.Z)
                local limitX = otherHalfX + candidateHalfX + PLACEMENT_EDGE_EPSILON
                local limitZ = otherHalfZ + candidateHalfZ + PLACEMENT_EDGE_EPSILON
                if deltaX <= limitX and deltaZ <= limitZ then
                    return false
                end
            end
        end
    end

    return true, resolvedPosition
end

function TowerService:AddTower(player, towerType, position)
    local towerConfig = TowerConfigs[towerType]
    if not towerConfig then
        return
    end

    if self:HasReachedTowerLimit(player, towerType) then
        return
    end

    local placementValid, resolvedPosition = self:IsPlacementValid(position, towerType)
    if not placementValid then
        return
    end

    position = resolvedPosition or position

    local towerModel, head, barrel = buildTowerModel(towerType)
    if not towerModel then
        return
    end

    towerModel.Parent = workspace.Towers

    local primary = towerModel.PrimaryPart or towerModel:FindFirstChild("Base") or towerModel:FindFirstChildWhichIsA("BasePart")
    if not primary then
        towerModel:Destroy()
        return
    end
    if towerModel.PrimaryPart ~= primary then
        towerModel.PrimaryPart = primary
    end

    TowerFootprints[towerType] = TowerFootprints[towerType] or sanitizeBaseSize(primary.Size)

    local heightOffset = primary.Size.Y / 2
    towerModel:PivotTo(CFrame.new(position.X, position.Y + heightOffset, position.Z))
    towerModel:SetAttribute("PlacementPosition", position)

    if not towerModel:GetAttribute("TemplateModel") then
        if head and head:IsA("BasePart") then
            head.CFrame = primary.CFrame * CFrame.new(0, (primary.Size.Y + head.Size.Y) / 2, 0)
        end
        if head and barrel and head:IsA("BasePart") and barrel:IsA("BasePart") then
            barrel.CFrame = head.CFrame * CFrame.new(0, 0, -(head.Size.Z / 2 + barrel.Size.Z / 2))
        end
    end

    local towerData = {
        Player = player,
        Type = towerType,
        Config = cloneTowerConfig(towerConfig),
        Model = towerModel,
        Head = head,
        Barrel = barrel,
        Cooldown = 0,
        Level = 1,
        Invested = towerConfig.Cost,
        PlacementPosition = position
    }

    self.Towers[towerModel] = towerData
    ensureHeadGeometry(towerData)
    updateTowerAttributes(towerModel, towerData)
    if towerType == "Farm" then
        towerData.FarmIncomeEarned = towerData.FarmIncomeEarned or 0
        self:UpdateFarmIncomeDisplay(towerModel, towerData, 0)
    end
    self:BroadcastTowerCounts()
    return towerModel
end

local function getFarthestEnemyInRange(towerPosition, range, enemies, waveService, towerData)
    if not range or range <= 0 then
        return nil
    end

    local farthestEnemy
    local highestProgress = -math.huge
    local fallbackDistance = -math.huge

    for enemyModel, enemyData in pairs(enemies) do
        if enemyModel and enemyModel.PrimaryPart and enemyData.Health > 0 then
            if waveService and not waveService:TowerCanAffectEnemy(towerData, enemyData) then
                continue
            end
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

function TowerService:StartTowerStunSound(towerModel, towerData)
    if not towerData or towerData.StunSoundInstance or not towerData.StunSoundConfig then
        return
    end

    local parent = getTowerPrimaryPart(towerModel)
    if not parent then
        return
    end

    local sound = SoundEffects.CreateSound(towerData.StunSoundConfig)
    if not sound then
        return
    end

    if towerData.StunSoundName and towerData.StunSoundName ~= "" then
        sound.Name = towerData.StunSoundName
    elseif not sound.Name or sound.Name == "" then
        sound.Name = string.format("%sStunLoop", towerData.Type or "Tower")
    end

    local shouldLoop = towerData.StunForceLoop
    if shouldLoop == nil or shouldLoop then
        sound.Looped = true
    end

    sound.Parent = parent
    sound:Play()

    towerData.StunSoundInstance = sound
end

function TowerService:MaintainStunOrientation(towerData)
    if not towerData or not towerData.StunHeadCFrame then
        return
    end

    local headInfo = ensureHeadGeometry(towerData)
    if not headInfo or not headInfo.HeadPivot or not headInfo.HeadPivot.Parent then
        return
    end

    local pivotCFrame = towerData.StunHeadCFrame
    headInfo.HeadPivot.CFrame = pivotCFrame

    if headInfo.HeadOffsets then
        for part, offset in pairs(headInfo.HeadOffsets) do
            if part ~= headInfo.HeadPivot and part.Parent then
                part.CFrame = pivotCFrame * offset
            end
        end
    end

    if headInfo.Barrel and headInfo.Barrel.Parent and headInfo.BarrelOffset then
        headInfo.Barrel.CFrame = pivotCFrame * headInfo.BarrelOffset
    end
end

function TowerService:ClearTowerStun(towerModel, towerData, skipAttribute)
    if not towerData then
        return
    end

    if towerData.StunSoundInstance then
        stopAndDestroySound(towerData.StunSoundInstance)
        towerData.StunSoundInstance = nil
    end

    towerData.StunnedUntil = nil
    towerData.StunActive = nil
    towerData.StunFreeze = nil
    towerData.StunHeadCFrame = nil
    towerData.StunSoundConfig = nil
    towerData.StunSoundName = nil
    towerData.StunForceLoop = nil

    if not skipAttribute and towerModel and towerModel.Parent then
        towerModel:SetAttribute("Stunned", false)
    end
end

function TowerService:ActivateTowerStun(towerModel, towerData, config)
    if not towerModel or not towerData then
        return
    end

    if config then
        local sound = config.Sound or config.StunSound
        if sound then
            towerData.StunSoundConfig = sound
        end

        local soundName = config.SoundName or config.SoundLabel
        if soundName and soundName ~= "" then
            towerData.StunSoundName = soundName
        end

        if config.Loop ~= nil then
            towerData.StunForceLoop = config.Loop
        end

        if config.Freeze ~= nil then
            towerData.StunFreeze = config.Freeze ~= false
        end
    end

    if towerData.StunForceLoop == nil then
        towerData.StunForceLoop = true
    end

    if towerData.StunFreeze == nil then
        towerData.StunFreeze = true
    end

    if not towerData.StunActive then
        towerData.StunActive = true
        if towerModel.Parent then
            towerModel:SetAttribute("Stunned", true)
        end
    end

    if towerData.StunFreeze then
        local headInfo = ensureHeadGeometry(towerData)
        if headInfo and headInfo.HeadPivot and headInfo.HeadPivot.Parent then
            towerData.StunHeadCFrame = headInfo.HeadPivot.CFrame
        else
            towerData.StunHeadCFrame = nil
        end
    else
        towerData.StunHeadCFrame = nil
    end

    if towerData.StunSoundConfig and not towerData.StunSoundInstance then
        self:StartTowerStunSound(towerModel, towerData)
    elseif towerData.StunSoundInstance and not towerData.StunSoundInstance.IsPlaying then
        towerData.StunSoundInstance:Play()
    end

    local baseCooldown = towerData.Config and towerData.Config.FireRate
    if baseCooldown then
        towerData.Cooldown = math.max(towerData.Cooldown or 0, baseCooldown)
    end

    if towerData.StunFreeze and towerData.StunHeadCFrame then
        self:MaintainStunOrientation(towerData)
    end
end

function TowerService:ApplyTowerStun(origin, radius, duration, config)
    if not origin or not radius or radius <= 0 or not duration or duration <= 0 then
        return
    end

    local effectColor
    local pulseSound
    local pulseSoundName

    if type(config) == "table" then
        effectColor = config.EffectColor or config.Color or config.StunColor
        pulseSound = config.PulseSound or config.PulseSoundId
        pulseSoundName = config.PulseSoundName
    end

    if not effectColor then
        effectColor = Color3.fromRGB(140, 225, 255)
    end

    if pulseSound then
        local soundOptions = {
            Position = origin,
        }

        if pulseSoundName and pulseSoundName ~= "" then
            soundOptions.Name = pulseSoundName
        else
            soundOptions.Name = "StunPulseSound"
        end

        SoundEffects.Play(nil, pulseSound, soundOptions)
    end

    if self.Remotes and self.Remotes.TowerStunPulse then
        self.Remotes.TowerStunPulse:FireAllClients(origin, radius, effectColor)
    end

    local now = tick()
    for towerModel, towerData in pairs(self.Towers) do
        local primary = getTowerPrimaryPart(towerModel)
        if primary and primary.Parent then
            local distance = (primary.Position - origin).Magnitude
            if distance <= radius then
                local endsAt = now + duration
                if towerData.StunnedUntil then
                    if endsAt > towerData.StunnedUntil then
                        towerData.StunnedUntil = endsAt
                    end
                else
                    towerData.StunnedUntil = endsAt
                end

                self:ActivateTowerStun(towerModel, towerData, config)
            end
        end
    end
end

function TowerService:Tick(dt)
    local now = tick()
    local countsDirty = false

    for towerModel, towerData in pairs(self.Towers) do
        if not towerModel.Parent then
            self:ClearTowerStun(towerModel, towerData, true)
            self:DestroyFarmIncomeDisplay(towerData)
            self.Towers[towerModel] = nil
            countsDirty = true
        else
            local stunnedUntil = towerData.StunnedUntil
            if stunnedUntil and stunnedUntil > now then
                if towerData.StunFreeze and towerData.StunHeadCFrame then
                    self:MaintainStunOrientation(towerData)
                end

                local stunSound = towerData.StunSoundInstance
                if stunSound then
                    if stunSound.Parent then
                        if not stunSound.IsPlaying then
                            stunSound:Play()
                        end
                    else
                        towerData.StunSoundInstance = nil
                    end
                end

                if (not towerData.StunSoundInstance) and towerData.StunSoundConfig then
                    self:StartTowerStunSound(towerModel, towerData)
                end
            else
                if stunnedUntil and stunnedUntil <= now then
                    self:ClearTowerStun(towerModel, towerData)
                end

                towerData.Cooldown = math.max(0, (towerData.Cooldown or 0) - dt)
                if towerData.Cooldown <= 0 then
                    local headInfo = ensureHeadGeometry(towerData)
                    local headPivot = headInfo and headInfo.HeadPivot
                    if headPivot then
                        local target = getFarthestEnemyInRange(
                            headPivot.Position,
                            towerData.Config.Range,
                            self.WaveService.Enemies,
                            self.WaveService,
                            towerData
                        )
                        if target then
                            local targetPrimary = target.PrimaryPart
                            if targetPrimary then
                                local headPosition = headPivot.Position
                                local flatTarget = Vector3.new(targetPrimary.Position.X, headPosition.Y, targetPrimary.Position.Z)
                                local lookCFrame = CFrame.new(headPosition, flatTarget)
                                headPivot.CFrame = lookCFrame

                                if headInfo.HeadOffsets then
                                    for part, offset in pairs(headInfo.HeadOffsets) do
                                        if part ~= headPivot and part.Parent then
                                            part.CFrame = lookCFrame * offset
                                        end
                                    end
                                end

                                if headInfo.Barrel and headInfo.Barrel.Parent then
                                    towerData.Barrel = headInfo.Barrel
                                    local barrelOffset = headInfo.BarrelOffset
                                    if barrelOffset then
                                        headInfo.Barrel.CFrame = lookCFrame * barrelOffset
                                    end
                                end
                            end

                            local fireRate = towerData.Config.FireRate or 0
                            towerData.Cooldown = math.max(0.05, fireRate)
                            local splashRadius = towerData.Config.SplashRadius
                            if splashRadius and targetPrimary then
                                self.WaveService:SplashDamage(
                                    targetPrimary.Position,
                                    splashRadius,
                                    towerData,
                                    target
                                )
                                if self.Remotes and self.Remotes.SplashFired then
                                    local splashColor = towerData.Config.SplashColor
                                        or Color3.fromRGB(255, 185, 90)
                                    self.Remotes.SplashFired:FireAllClients(
                                        targetPrimary.Position,
                                        splashRadius,
                                        splashColor
                                    )
                                end
                            else
                                self.WaveService:DamageEnemy(target, towerData)
                            end

                            if towerData.Config.FireSound then
                                local soundParent
                                local soundPosition
                                local barrel = towerData.Barrel
                                if barrel and barrel.Parent then
                                    soundParent = barrel
                                    if barrel:IsA("BasePart") then
                                        soundPosition = barrel.Position
                                    end
                                end

                                if not soundParent then
                                    local primary = towerModel.PrimaryPart
                                    if primary and primary.Parent then
                                        soundParent = primary
                                        if primary:IsA("BasePart") then
                                            soundPosition = primary.Position
                                        end
                                    end
                                end

                                if not soundPosition and headInfo and headInfo.HeadPivot then
                                    soundPosition = headInfo.HeadPivot.Position
                                end

                                SoundEffects.Play(soundParent, towerData.Config.FireSound, {
                                    Name = string.format("%sFire", towerData.Type),
                                    Position = soundPosition,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if countsDirty then
        self:BroadcastTowerCounts()
    end
end

local function upgradeRequestsModelSwap(nextUpgrade)
    if not nextUpgrade then
        return false
    end

    if nextUpgrade.ModelName or nextUpgrade.Model then
        return true
    end

    if typeof(nextUpgrade.ModelProvider) == "function" or typeof(nextUpgrade.ModelBuilder) == "function" then
        return true
    end

    if nextUpgrade.ModelTemplate and typeof(nextUpgrade.ModelTemplate) == "Instance" then
        return true
    end

    return false
end

function TowerService:RebuildTowerModel(towerModel, towerData)
    if not towerModel or not towerData then
        return towerModel
    end

    if not towerData.PlacementPosition then
        local storedPlacement = towerModel:GetAttribute("PlacementPosition")
        if typeof(storedPlacement) == "Vector3" then
            towerData.PlacementPosition = storedPlacement
        else
            local currentPrimary = getTowerPrimaryPart(towerModel)
            if currentPrimary then
                towerData.PlacementPosition = Vector3.new(
                    currentPrimary.Position.X,
                    currentPrimary.Position.Y - currentPrimary.Size.Y / 2,
                    currentPrimary.Position.Z
                )
            end
        end
    end

    local config = towerData.Config
    local newModel, head, barrel = buildTowerModel(towerData.Type, config)
    if not newModel then
        return towerModel
    end

    local parent = towerModel.Parent
    local oldPrimary = getTowerPrimaryPart(towerModel)
    local oldSizeY = oldPrimary and oldPrimary.Size.Y or 0
    local oldCFrame = oldPrimary and oldPrimary.CFrame or towerModel:GetPivot()

    self:ClearTowerStun(towerModel, towerData, true)

    newModel.Parent = parent

    local newPrimary = getTowerPrimaryPart(newModel)
    if newPrimary and not newModel.PrimaryPart then
        newModel.PrimaryPart = newPrimary
    end

    if newPrimary and oldCFrame then
        local newSizeY = newPrimary.Size.Y
        local heightOffset = (newSizeY - oldSizeY) / 2
        newModel:PivotTo(oldCFrame * CFrame.new(0, heightOffset, 0))
        TowerFootprints[towerData.Type] = sanitizeBaseSize(newPrimary.Size)
    elseif oldCFrame then
        newModel:PivotTo(oldCFrame)
    end

    self.Towers[towerModel] = nil
    towerData.Model = newModel
    towerData.Head = head
    towerData.Barrel = barrel
    towerData.HeadInfo = nil
    self.Towers[newModel] = towerData

    updateTowerAttributes(newModel, towerData)
    ensureHeadGeometry(towerData)
    if towerData.Type == "Farm" then
        self:UpdateFarmIncomeDisplay(newModel, towerData, 0)
    end

    if towerModel then
        towerModel:Destroy()
    end

    return newModel
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
    towerData.Invested = (towerData.Invested or 0) + nextUpgrade.Cost
    local originalModel = towerModel

    if upgradeRequestsModelSwap(nextUpgrade) then
        towerModel = self:RebuildTowerModel(towerModel, towerData)
    else
        updateTowerAttributes(towerModel, towerData)
        ensureHeadGeometry(towerData)
    end

    if self.Remotes and self.Remotes.TowerUpgraded then
        self.Remotes.TowerUpgraded:FireClient(player, towerModel, towerData.Level, originalModel)
    end

    return true, towerModel
end

function TowerService:SellTower(player, towerModel)
    local towerData = self.Towers[towerModel]
    if not towerData or towerData.Player ~= player then
        return false, "You do not own this tower"
    end

    local refund = math.floor(math.max(0, (towerData.Invested or 0) * 0.5))

    self:ClearTowerStun(towerModel, towerData, true)
    self:DestroyFarmIncomeDisplay(towerData)
    self.Towers[towerModel] = nil

    if towerModel and towerModel.Parent then
        towerModel:Destroy()
    end

    if refund > 0 then
        self.WaveService:AdjustMoney(player, refund)
    end

    self:BroadcastTowerCounts()

    return true
end

function TowerService:Reset()
    local towersFolder = workspace:FindFirstChild("Towers")
    for towerModel, towerData in pairs(self.Towers) do
        self:ClearTowerStun(towerModel, towerData, true)
        self:DestroyFarmIncomeDisplay(towerData)
        if towerModel and towerModel.Parent then
            towerModel:Destroy()
        end
        self.Towers[towerModel] = nil
    end
    if towersFolder then
        towersFolder:ClearAllChildren()
    end
    self.Towers = {}

    TowerLimits = {}
    OverallPlacementLimitCache = nil

    self:BroadcastTowerCounts()
end

return TowerService
