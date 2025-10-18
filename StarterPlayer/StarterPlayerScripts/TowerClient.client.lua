local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local towerConfigs = require(ReplicatedStorage.Modules.Config.TowerConfigs)
local enemiesFolder = workspace:WaitForChild("Enemies")

local placingTowerType
local previewPart
local placementValid = false
local hoverBillboard
local hoverNameLabel
local hoverHealthLabel
local hoverCombinedLabel
local selectedTower
local screenGui
local shopFrame
local statusFrame
local moneyLabel
local livesLabel
local waveLabel
local startButton
local rangeRing
local rangeRingAdornment
local previewRangeRing
local previewRangeAdornment
local selectedTowerConnections = {}
local currentMoney = 0
local gameEnded = false
local lastVictoryState
local shopButtonConnections = {}
local beginPlacement
local shopDescendantConnection

local towerDetailsFrame
local towerNameLabel
local towerLevelLabel
local towerStatsLabel
local ownershipLabel
local upgradeDescriptionLabel
local upgradeButton
local sellButton

local DEFAULT_PREVIEW_SIZE = Vector3.new(4, 1, 4)
local DEFAULT_PREVIEW_RADIUS = math.max(DEFAULT_PREVIEW_SIZE.X, DEFAULT_PREVIEW_SIZE.Z) / 2
local previewFootprintSize = DEFAULT_PREVIEW_SIZE
local previewFootprintRadius = DEFAULT_PREVIEW_RADIUS
local footprintCache = {}
local RANGE_RING_HEIGHT = 0.05

local function disconnectSelectedConnections()
    for _, conn in ipairs(selectedTowerConnections) do
        conn:Disconnect()
    end
    selectedTowerConnections = {}
end

local function destroyRangeIndicator()
    if rangeRing then
        rangeRing:Destroy()
        rangeRing = nil
        rangeRingAdornment = nil
    end
end

local function destroyPreviewRangeIndicator()
    if previewRangeRing then
        previewRangeRing:Destroy()
        previewRangeRing = nil
        previewRangeAdornment = nil
    end
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

local function sanitizeFootprint(size)
    if not size then
        return DEFAULT_PREVIEW_SIZE
    end

    return Vector3.new(
        math.max(0.1, math.abs(size.X)),
        math.max(0.1, math.abs(size.Y)),
        math.max(0.1, math.abs(size.Z))
    )
end

local function getTowerFootprint(towerType)
    if not towerType then
        return DEFAULT_PREVIEW_SIZE
    end

    if footprintCache[towerType] then
        return footprintCache[towerType]
    end

    local config = towerConfigs[towerType]
    local baseSize
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

    local sanitized = sanitizeFootprint(baseSize)
    footprintCache[towerType] = sanitized
    return sanitized
end

local function createRangeRing(name, color, transparency)
    local anchor = Instance.new("Part")
    anchor.Name = name .. "Anchor"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.CastShadow = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.Parent = workspace

    local adornment = Instance.new("CylinderHandleAdornment")
    adornment.Name = name
    adornment.AlwaysOnTop = false
    adornment.Color3 = color
    adornment.Transparency = transparency
    adornment.Radius = 1
    adornment.Height = RANGE_RING_HEIGHT
    adornment.ZIndex = 1
    adornment.CFrame = CFrame.Angles(math.rad(90), 0, 0)
    adornment.Adornee = anchor
    adornment.Parent = anchor

    return anchor, adornment
end

local function updateRangeRing(anchor, adornment, radius, position)
    if not anchor or not adornment then
        return
    end

    local clampedRadius = math.max(0.1, radius)
    adornment.Radius = clampedRadius
    anchor.CFrame = CFrame.new(position)
end

local function showExplosion(position, radius, color)
    if typeof(position) ~= "Vector3" then
        return
    end

    local splashRadius = math.max(0.5, tonumber(radius) or 1)
    local sphere = Instance.new("Part")
    sphere.Name = "SplashEffect"
    sphere.Shape = Enum.PartType.Ball
    sphere.Material = Enum.Material.Neon
    sphere.Color = color or Color3.fromRGB(255, 185, 90)
    sphere.Transparency = 0.45
    sphere.CanCollide = false
    sphere.CanQuery = false
    sphere.CanTouch = false
    sphere.CastShadow = false
    sphere.Anchored = true
    sphere.Size = Vector3.new(0.5, 0.5, 0.5)
    sphere.CFrame = CFrame.new(position)
    sphere.Parent = workspace

    local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    local goal = {
        Size = Vector3.new(splashRadius * 2, splashRadius * 2, splashRadius * 2),
        Transparency = 1
    }

    local tween = TweenService:Create(sphere, tweenInfo, goal)
    tween:Play()
    tween.Completed:Connect(function()
        if sphere then
            sphere:Destroy()
        end
    end)

    task.delay(tweenInfo.Time + 0.1, function()
        if sphere then
            sphere:Destroy()
        end
    end)
end

local function cancelPlacement()
    placingTowerType = nil
    if previewPart then
        previewPart:Destroy()
        previewPart = nil
    end
    destroyPreviewRangeIndicator()
    placementValid = false
    previewFootprintSize = DEFAULT_PREVIEW_SIZE
    previewFootprintRadius = DEFAULT_PREVIEW_RADIUS
end

function beginPlacement(towerType)
    if not towerType or not towerConfigs[towerType] then
        return
    end

    cancelPlacement()
    placingTowerType = towerType

    previewPart = Instance.new("Part")
    previewPart.Name = "PlacementPreview"
    previewPart.Anchored = true
    previewPart.CanCollide = false
    previewPart.CanTouch = false
    previewPart.CanQuery = false
    previewPart.Transparency = 0.5
    previewPart.Color = Color3.fromRGB(255, 100, 100)
    previewPart.Parent = workspace

    local footprint = getTowerFootprint(placingTowerType)
    previewFootprintSize = Vector3.new(footprint.X, math.max(0.2, footprint.Y), footprint.Z)
    previewFootprintRadius = math.max(previewFootprintSize.X, previewFootprintSize.Z) / 2
    previewPart.Size = previewFootprintSize

    local config = towerConfigs[placingTowerType]
    if config and config.Range then
        if not previewRangeRing then
            previewRangeRing, previewRangeAdornment = createRangeRing("PlacementRange", Color3.fromRGB(120, 220, 255), 0.55)
        end
        if previewRangeAdornment then
            previewRangeAdornment.Color3 = Color3.fromRGB(120, 220, 255)
            previewRangeAdornment.Transparency = 0.55
        end
    else
        destroyPreviewRangeIndicator()
    end

    placementValid = false
    selectedTower = nil
    disconnectSelectedConnections()
    destroyRangeIndicator()
    if towerDetailsFrame then
        towerDetailsFrame.Visible = false
    end
    if upgradeDescriptionLabel then
        upgradeDescriptionLabel.Text = ""
    end
end

local function updateStartButtonVisual()
    if not startButton or not startButton.Parent then
        return
    end

    local autoText = startButton:GetAttribute("AutoText")
    local autoStyle = startButton:GetAttribute("AutoStyle")

    if gameEnded then
        local text = "Restart"
        local background = Color3.fromRGB(120, 120, 255)
        if lastVictoryState == true then
            text = "Victory! Restart"
            background = Color3.fromRGB(120, 255, 120)
        elseif lastVictoryState == false then
            text = "Defeat! Restart"
            background = Color3.fromRGB(255, 120, 120)
        end

        if autoText ~= false then
            startButton.Text = text
        end
        if autoStyle ~= false then
            startButton.BackgroundColor3 = background
        end
    else
        if autoText ~= false then
            startButton.Text = "Start"
        end
        if autoStyle ~= false then
            startButton.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
        end
    end
end

local function applyEnemyBillboardState(enemyModel)
    local display = enemyModel:FindFirstChild("HealthDisplay")
    if display and display:IsA("BillboardGui") then
        display.Enabled = true
    end
end

local function watchEnemy(enemyModel)
    if not enemyModel or not enemyModel:IsA("Model") then
        return
    end

    applyEnemyBillboardState(enemyModel)
    enemyModel.ChildAdded:Connect(function(child)
        if child.Name == "HealthDisplay" and child:IsA("BillboardGui") then
            child.Enabled = true
        end
    end)
end

local function updateAllEnemyBillboards()
    for _, enemy in ipairs(enemiesFolder:GetChildren()) do
        applyEnemyBillboardState(enemy)
    end
end

for _, enemy in ipairs(enemiesFolder:GetChildren()) do
    watchEnemy(enemy)
end

enemiesFolder.ChildAdded:Connect(function(enemy)
    watchEnemy(enemy)
end)

local function createRaycastParams()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.IgnoreWater = true

    local ignoreList = { player.Character }
    if previewPart then
        table.insert(ignoreList, previewPart)
    end
    if previewRangeRing then
        table.insert(ignoreList, previewRangeRing)
    end
    if rangeRing then
        table.insert(ignoreList, rangeRing)
    end

    params.FilterDescendantsInstances = ignoreList
    return params
end

local function getEnemyModelFromInstance(instance)
    if not instance then
        return nil
    end

    if not enemiesFolder then
        return nil
    end

    local ancestor = instance
    while ancestor and ancestor ~= workspace do
        if ancestor:IsA("Model") and ancestor.Parent == enemiesFolder then
            return ancestor
        end
        ancestor = ancestor.Parent
    end

    return nil
end

local function getTowerModelFromInstance(instance)
    if not instance then
        return nil
    end

    local towersFolder = workspace:FindFirstChild("Towers")
    if not towersFolder then
        return nil
    end

    local ancestor = instance
    while ancestor and ancestor ~= workspace do
        if ancestor:IsA("Model") and ancestor.Parent == towersFolder then
            return ancestor
        end
        ancestor = ancestor.Parent
    end

    return nil
end

local function getTowerTypeForButton(button)
    if not button or not button:IsA("TextButton") then
        return nil
    end

    local towerType = button:GetAttribute("TowerType")
    if towerType and towerConfigs[towerType] then
        return towerType
    end

    if towerConfigs[button.Name] then
        return button.Name
    end

    return nil
end

local function disconnectShopButton(button)
    local existing = shopButtonConnections[button]
    if existing then
        existing:Disconnect()
        shopButtonConnections[button] = nil
    end
end

local function connectShopButton(button)
    if not button or not button:IsA("TextButton") then
        return
    end

    if shopButtonConnections[button] then
        return
    end

    local towerType = getTowerTypeForButton(button)
    if not towerType then
        return
    end

    local config = towerConfigs[towerType]
    if config and button:GetAttribute("AutoText") ~= false then
        button.Text = string.format("%s | $%d", config.Name or towerType, config.Cost or 0)
    end

    shopButtonConnections[button] = button.MouseButton1Click:Connect(function()
        beginPlacement(towerType)
    end)

    button.AncestryChanged:Connect(function(_, parent)
        if not parent then
            disconnectShopButton(button)
        end
    end)
end

local function ensureHoverBillboard()
    if hoverBillboard then
        return hoverBillboard
    end

    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    local uiFolder = assetsFolder and assetsFolder:FindFirstChild("UI")
    local template = uiFolder and uiFolder:FindFirstChild("EnemyHoverTemplate")

    if template and template:IsA("BillboardGui") then
        hoverBillboard = template:Clone()
        hoverBillboard.Enabled = false
        hoverBillboard.Parent = playerGui
        hoverNameLabel = hoverBillboard:FindFirstChild("NameLabel", true)
        hoverHealthLabel = hoverBillboard:FindFirstChild("HealthLabel", true)
        hoverCombinedLabel = hoverBillboard:FindFirstChild("InfoLabel", true)
    else
        hoverBillboard = Instance.new("BillboardGui")
        hoverBillboard.Name = "EnemyHoverInfo"
        hoverBillboard.Size = UDim2.new(0, 160, 0, 48)
        hoverBillboard.AlwaysOnTop = true
        hoverBillboard.Enabled = false
        hoverBillboard.ExtentsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
        hoverBillboard.Parent = playerGui

        local background = Instance.new("Frame")
        background.BackgroundTransparency = 0.2
        background.BackgroundColor3 = Color3.new(0, 0, 0)
        background.Size = UDim2.fromScale(1, 1)
        background.Name = "Container"
        background.Parent = hoverBillboard

        hoverNameLabel = Instance.new("TextLabel")
        hoverNameLabel.Name = "NameLabel"
        hoverNameLabel.BackgroundTransparency = 1
        hoverNameLabel.Position = UDim2.new(0, 4, 0, 0)
        hoverNameLabel.Size = UDim2.new(1, -8, 0.5, 0)
        hoverNameLabel.Font = Enum.Font.GothamBold
        hoverNameLabel.TextScaled = true
        hoverNameLabel.TextColor3 = Color3.new(1, 1, 1)
        hoverNameLabel.TextStrokeTransparency = 0.3
        hoverNameLabel.Parent = background

        hoverHealthLabel = Instance.new("TextLabel")
        hoverHealthLabel.Name = "HealthLabel"
        hoverHealthLabel.BackgroundTransparency = 1
        hoverHealthLabel.Position = UDim2.new(0, 4, 0.5, 0)
        hoverHealthLabel.Size = UDim2.new(1, -8, 0.5, 0)
        hoverHealthLabel.Font = Enum.Font.Gotham
        hoverHealthLabel.TextScaled = true
        hoverHealthLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
        hoverHealthLabel.TextStrokeTransparency = 0.3
        hoverHealthLabel.Parent = background
    end

    if not hoverNameLabel and not hoverHealthLabel and not hoverCombinedLabel then
        hoverCombinedLabel = Instance.new("TextLabel")
        hoverCombinedLabel.Name = "InfoLabel"
        hoverCombinedLabel.BackgroundTransparency = 1
        hoverCombinedLabel.Size = UDim2.fromScale(1, 1)
        hoverCombinedLabel.Font = Enum.Font.GothamBold
        hoverCombinedLabel.TextScaled = true
        hoverCombinedLabel.TextColor3 = Color3.new(1, 1, 1)
        hoverCombinedLabel.TextStrokeTransparency = 0.3
        hoverCombinedLabel.Parent = hoverBillboard
    end

    return hoverBillboard
end

local function cloneStats(config)
    local stats = {}
    for key, value in pairs(config) do
        if key ~= "Upgrades" then
            stats[key] = value
        end
    end
    return stats
end

local function applyUpgrade(stats, upgrade)
    if not upgrade then
        return
    end
    for key, value in pairs(upgrade) do
        if key ~= "Cost" and key ~= "Description" then
            stats[key] = value
        end
    end
end

local function getTowerStatsForLevel(towerType, level)
    local config = towerConfigs[towerType]
    if not config then
        return nil
    end

    local stats = cloneStats(config)
    if config.Upgrades then
        for i = 1, math.max(0, (level or 1) - 1) do
            applyUpgrade(stats, config.Upgrades[i])
        end
    end

    return stats
end

local function getNextUpgrade(towerType, level)
    local config = towerConfigs[towerType]
    if not config or not config.Upgrades then
        return nil
    end
    return config.Upgrades[level or 1]
end

local function resolveTowerType(towerModel)
    local towerType = towerModel:GetAttribute("TowerType")
    if towerType then
        return towerType
    end

    for key, config in pairs(towerConfigs) do
        if config.Name == towerModel.Name then
            return key
        end
    end

    return nil
end

local function showRangeIndicator(towerModel, range)
    destroyRangeIndicator()
    if not range then
        return
    end

    local base = towerModel.PrimaryPart or towerModel:FindFirstChild("Base")
    if not base then
        return
    end

    rangeRing, rangeRingAdornment = createRangeRing("TowerRangeRing", Color3.fromRGB(80, 200, 255), 0.35)
    local groundY = base.Position.Y - (base.Size.Y / 2) + 0.05
    updateRangeRing(rangeRing, rangeRingAdornment, range, Vector3.new(base.Position.X, groundY, base.Position.Z))
end

local function updateUpgradeButton(towerType, level, ownerUserId)
    if not upgradeButton then
        return
    end

    local nextUpgrade = getNextUpgrade(towerType, level)

    if upgradeDescriptionLabel then
        if nextUpgrade and nextUpgrade.Description then
            if ownerUserId == player.UserId then
                upgradeDescriptionLabel.Text = string.format("%s\nPress E to upgrade.", nextUpgrade.Description)
            else
                upgradeDescriptionLabel.Text = nextUpgrade.Description
            end
        else
            if ownerUserId == player.UserId then
                upgradeDescriptionLabel.Text = "Fully upgraded\nPress X to sell if you need the space."
            else
                upgradeDescriptionLabel.Text = "Fully upgraded"
            end
        end
    end

    if not nextUpgrade then
        upgradeButton.Text = "Max Level"
        upgradeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        upgradeButton.AutoButtonColor = false
        upgradeButton.Active = false
        upgradeButton.Visible = true
        return
    end

    if ownerUserId ~= player.UserId then
        upgradeButton.Text = "Not your tower"
        upgradeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        upgradeButton.AutoButtonColor = false
        upgradeButton.Active = false
        upgradeButton.Visible = true
        return
    end

    local affordable = currentMoney >= nextUpgrade.Cost
    upgradeButton.Text = string.format("Upgrade (E) - $%d", nextUpgrade.Cost)
    upgradeButton.BackgroundColor3 = affordable and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(120, 70, 70)
    upgradeButton.AutoButtonColor = affordable
    upgradeButton.Active = affordable
    upgradeButton.Visible = true
end

local function updateSellButton(towerModel, ownerUserId)
    if not sellButton then
        return
    end

    if not towerModel then
        sellButton.Visible = false
        return
    end

    local sellValue = towerModel:GetAttribute("SellValue")
    if typeof(sellValue) ~= "number" or sellValue <= 0 then
        sellButton.Visible = false
        return
    end

    local refund = math.floor(sellValue + 0.5)
    sellButton.Text = string.format("Sell (X) +$%d", refund)
    sellButton.Visible = true

    local isOwner = ownerUserId == player.UserId
    local active = isOwner and not gameEnded
    sellButton.AutoButtonColor = active
    sellButton.Active = active
    sellButton.BackgroundColor3 = active and Color3.fromRGB(220, 120, 120) or Color3.fromRGB(70, 70, 70)
    sellButton.TextColor3 = active and Color3.new(0, 0, 0) or Color3.fromRGB(200, 200, 200)
end

local function updateTowerDetails(towerModel)
    if not towerDetailsFrame or not towerModel then
        return
    end

    local towerType = resolveTowerType(towerModel)
    if not towerType then
        towerDetailsFrame.Visible = false
        destroyRangeIndicator()
        return
    end

    local level = towerModel:GetAttribute("Level") or 1
    local ownerUserId = towerModel:GetAttribute("OwnerUserId") or 0
    local ownerText = "Unknown"
    if ownerUserId == player.UserId then
        ownerText = "You"
    else
        local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
        if ownerPlayer then
            ownerText = ownerPlayer.DisplayName or ownerPlayer.Name
        end
    end

    local config = towerConfigs[towerType]
    if towerNameLabel then
        local displayName = config and config.Name or towerModel.Name
        towerNameLabel.Text = displayName
    end
    if towerLevelLabel then
        towerLevelLabel.Text = string.format("Level: %d", level)
    end

    local stats = getTowerStatsForLevel(towerType, level)
    if stats and towerStatsLabel then
        local lines = {}
        if stats.Range then
            table.insert(lines, string.format("Range: %.1f", stats.Range))
        end
        if stats.Damage then
            table.insert(lines, string.format("Damage: %d", stats.Damage))
        end
        if stats.FireRate then
            table.insert(lines, string.format("Fire Rate: %.2fs", stats.FireRate))
        end
        if stats.SplashRadius then
            table.insert(lines, string.format("Splash Radius: %.1f", stats.SplashRadius))
        end
        if stats.SlowPercent then
            table.insert(lines, string.format("Slow: %d%% for %.1fs", math.floor(stats.SlowPercent * 100 + 0.5), stats.SlowDuration or 0))
        end
        towerStatsLabel.Text = table.concat(lines, "\n")
    elseif towerStatsLabel then
        towerStatsLabel.Text = ""
    end

    if ownershipLabel then
        if ownerUserId == player.UserId then
            ownershipLabel.Text = "Owner: You (E to upgrade, X to sell)"
        else
            ownershipLabel.Text = string.format("Owner: %s", ownerText)
        end
    end

    towerDetailsFrame.Visible = true
    showRangeIndicator(towerModel, stats and stats.Range)
    updateUpgradeButton(towerType, level, ownerUserId)
    updateSellButton(towerModel, ownerUserId)
end

local function createGui()
    if screenGui then
        return screenGui
    end

    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    local uiFolder = assetsFolder and assetsFolder:FindFirstChild("UI")
    local template = uiFolder and uiFolder:FindFirstChild("TowerHUD")

    if template and template:IsA("ScreenGui") then
        screenGui = template:Clone()
        screenGui.ResetOnSpawn = false
        screenGui.IgnoreGuiInset = true
        screenGui.Parent = playerGui
    else
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "TowerDefenseUI"
        screenGui.ResetOnSpawn = false
        screenGui.IgnoreGuiInset = true
        screenGui.Parent = playerGui

        shopFrame = Instance.new("Frame")
        shopFrame.Name = "Shop"
        shopFrame.Size = UDim2.new(0, 250, 0, 200)
        shopFrame.Position = UDim2.new(0, 20, 1, -210)
        shopFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        shopFrame.BackgroundTransparency = 0.2
        shopFrame.BorderSizePixel = 0
        shopFrame.Parent = screenGui

        local uiList = Instance.new("UIListLayout")
        uiList.Padding = UDim.new(0, 6)
        uiList.FillDirection = Enum.FillDirection.Vertical
        uiList.SortOrder = Enum.SortOrder.LayoutOrder
        uiList.Parent = shopFrame

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 24)
        title.Text = "TOWERS"
        title.TextColor3 = Color3.new(1, 1, 1)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 18
        title.Parent = shopFrame

        for key, config in pairs(towerConfigs) do
            local button = Instance.new("TextButton")
            button.Name = key
            button.Size = UDim2.new(1, -10, 0, 30)
            button.Position = UDim2.new(0, 5, 0, 0)
            button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            button.TextColor3 = Color3.new(1, 1, 1)
            button.Font = Enum.Font.Gotham
            button.TextSize = 16
            button.Text = string.format("%s | $%d", config.Name, config.Cost)
            button:SetAttribute("TowerType", key)
            button.Parent = shopFrame
        end

        statusFrame = Instance.new("Frame")
        statusFrame.Name = "Status"
        statusFrame.Size = UDim2.new(0, 220, 0, 130)
        statusFrame.Position = UDim2.new(1, -240, 0, 20)
        statusFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        statusFrame.BackgroundTransparency = 0.2
        statusFrame.BorderSizePixel = 0
        statusFrame.Parent = screenGui

        local statusLayout = Instance.new("UIListLayout")
        statusLayout.Padding = UDim.new(0, 4)
        statusLayout.FillDirection = Enum.FillDirection.Vertical
        statusLayout.SortOrder = Enum.SortOrder.LayoutOrder
        statusLayout.Parent = statusFrame

        moneyLabel = Instance.new("TextLabel")
        moneyLabel.Name = "MoneyLabel"
        moneyLabel.Size = UDim2.new(1, -10, 0, 24)
        moneyLabel.Position = UDim2.new(0, 5, 0, 0)
        moneyLabel.BackgroundTransparency = 1
        moneyLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
        moneyLabel.Font = Enum.Font.GothamBold
        moneyLabel.TextSize = 18
        moneyLabel.Text = "$0"
        moneyLabel.Parent = statusFrame

        livesLabel = Instance.new("TextLabel")
        livesLabel.Name = "LivesLabel"
        livesLabel.Size = UDim2.new(1, -10, 0, 24)
        livesLabel.Position = UDim2.new(0, 5, 0, 30)
        livesLabel.BackgroundTransparency = 1
        livesLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        livesLabel.Font = Enum.Font.GothamBold
        livesLabel.TextSize = 18
        livesLabel.Text = "Lives: 0"
        livesLabel.Parent = statusFrame

        waveLabel = Instance.new("TextLabel")
        waveLabel.Name = "WaveLabel"
        waveLabel.Size = UDim2.new(1, -10, 0, 24)
        waveLabel.Position = UDim2.new(0, 5, 0, 56)
        waveLabel.BackgroundTransparency = 1
        waveLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
        waveLabel.Font = Enum.Font.GothamBold
        waveLabel.TextSize = 18
        waveLabel.Text = "Wave: 0"
        waveLabel.Parent = statusFrame

        startButton = Instance.new("TextButton")
        startButton.Name = "StartButton"
        startButton.Size = UDim2.new(0, 180, 0, 36)
        startButton.Position = UDim2.new(0.5, -90, 0, 86)
        startButton.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
        startButton.TextColor3 = Color3.new(0, 0, 0)
        startButton.Font = Enum.Font.GothamBlack
        startButton.TextSize = 18
        startButton.Text = "Start"
        startButton.Parent = statusFrame

        towerDetailsFrame = Instance.new("Frame")
        towerDetailsFrame.Name = "TowerDetails"
        towerDetailsFrame.Size = UDim2.new(0, 220, 0, 260)
        towerDetailsFrame.Position = UDim2.new(1, -240, 0, 160)
        towerDetailsFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        towerDetailsFrame.BackgroundTransparency = 0.2
        towerDetailsFrame.BorderSizePixel = 0
        towerDetailsFrame.Visible = false
        towerDetailsFrame.Parent = screenGui

        local detailLayout = Instance.new("UIListLayout")
        detailLayout.Padding = UDim.new(0, 4)
        detailLayout.FillDirection = Enum.FillDirection.Vertical
        detailLayout.SortOrder = Enum.SortOrder.LayoutOrder
        detailLayout.Parent = towerDetailsFrame

        towerNameLabel = Instance.new("TextLabel")
        towerNameLabel.Name = "TowerNameLabel"
        towerNameLabel.BackgroundTransparency = 1
        towerNameLabel.Font = Enum.Font.GothamBold
        towerNameLabel.TextSize = 18
        towerNameLabel.TextColor3 = Color3.new(1, 1, 1)
        towerNameLabel.Text = ""
        towerNameLabel.Size = UDim2.new(1, -10, 0, 24)
        towerNameLabel.Position = UDim2.new(0, 5, 0, 0)
        towerNameLabel.Parent = towerDetailsFrame

        towerLevelLabel = Instance.new("TextLabel")
        towerLevelLabel.Name = "TowerLevelLabel"
        towerLevelLabel.BackgroundTransparency = 1
        towerLevelLabel.Font = Enum.Font.Gotham
        towerLevelLabel.TextSize = 16
        towerLevelLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerLevelLabel.Text = ""
        towerLevelLabel.Size = UDim2.new(1, -10, 0, 20)
        towerLevelLabel.Position = UDim2.new(0, 5, 0, 28)
        towerLevelLabel.Parent = towerDetailsFrame

        towerStatsLabel = Instance.new("TextLabel")
        towerStatsLabel.Name = "TowerStatsLabel"
        towerStatsLabel.BackgroundTransparency = 1
        towerStatsLabel.Font = Enum.Font.Gotham
        towerStatsLabel.TextSize = 15
        towerStatsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerStatsLabel.Text = ""
        towerStatsLabel.TextWrapped = true
        towerStatsLabel.Size = UDim2.new(1, -10, 0, 70)
        towerStatsLabel.Position = UDim2.new(0, 5, 0, 52)
        towerStatsLabel.Parent = towerDetailsFrame

        ownershipLabel = Instance.new("TextLabel")
        ownershipLabel.Name = "OwnershipLabel"
        ownershipLabel.BackgroundTransparency = 1
        ownershipLabel.Font = Enum.Font.Gotham
        ownershipLabel.TextSize = 14
        ownershipLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
        ownershipLabel.Text = ""
        ownershipLabel.Size = UDim2.new(1, -10, 0, 20)
        ownershipLabel.Position = UDim2.new(0, 5, 0, 124)
        ownershipLabel.Parent = towerDetailsFrame

        upgradeDescriptionLabel = Instance.new("TextLabel")
        upgradeDescriptionLabel.Name = "UpgradeDescriptionLabel"
        upgradeDescriptionLabel.BackgroundTransparency = 1
        upgradeDescriptionLabel.Font = Enum.Font.Gotham
        upgradeDescriptionLabel.TextSize = 14
        upgradeDescriptionLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
        upgradeDescriptionLabel.TextWrapped = true
        upgradeDescriptionLabel.Text = ""
        upgradeDescriptionLabel.Size = UDim2.new(1, -10, 0, 40)
        upgradeDescriptionLabel.Position = UDim2.new(0, 5, 0, 146)
        upgradeDescriptionLabel.Parent = towerDetailsFrame

        upgradeButton = Instance.new("TextButton")
        upgradeButton.Name = "UpgradeButton"
        upgradeButton.Size = UDim2.new(1, -10, 0, 32)
        upgradeButton.Position = UDim2.new(0, 5, 0, 190)
        upgradeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        upgradeButton.TextColor3 = Color3.new(1, 1, 1)
        upgradeButton.Font = Enum.Font.GothamBold
        upgradeButton.TextSize = 16
        upgradeButton.Text = "Upgrade (E)"
        upgradeButton.AutoButtonColor = false
        upgradeButton.Visible = false
        upgradeButton.Parent = towerDetailsFrame

        sellButton = Instance.new("TextButton")
        sellButton.Name = "SellButton"
        sellButton.Size = UDim2.new(1, -10, 0, 32)
        sellButton.Position = UDim2.new(0, 5, 0, 228)
        sellButton.BackgroundColor3 = Color3.fromRGB(220, 120, 120)
        sellButton.TextColor3 = Color3.new(0, 0, 0)
        sellButton.Font = Enum.Font.GothamBold
        sellButton.TextSize = 16
        sellButton.Text = "Sell (X)"
        sellButton.AutoButtonColor = true
        sellButton.Visible = false
        sellButton.Parent = towerDetailsFrame
    end

    shopFrame = shopFrame or screenGui:FindFirstChild("Shop")
    if shopFrame then
        for _, descendant in ipairs(shopFrame:GetDescendants()) do
            if descendant:IsA("TextButton") then
                connectShopButton(descendant)
            end
        end
        if shopDescendantConnection then
            shopDescendantConnection:Disconnect()
        end
        shopDescendantConnection = shopFrame.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("TextButton") then
                connectShopButton(descendant)
            end
        end)
    else
        warn("TowerClient: Shop frame named 'Shop' was not found inside the Tower HUD. Add one to enable tower placement buttons.")
    end

    statusFrame = statusFrame or screenGui:FindFirstChild("Status")
    if statusFrame then
        moneyLabel = moneyLabel or statusFrame:FindFirstChild("MoneyLabel")
        if not moneyLabel then
            moneyLabel = Instance.new("TextLabel")
            moneyLabel.Name = "MoneyLabel"
            moneyLabel.Size = UDim2.new(1, -10, 0, 24)
            moneyLabel.Position = UDim2.new(0, 5, 0, 0)
            moneyLabel.BackgroundTransparency = 1
            moneyLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
            moneyLabel.Font = Enum.Font.GothamBold
            moneyLabel.TextSize = 18
            moneyLabel.Text = "$0"
            moneyLabel.Parent = statusFrame
        end

        livesLabel = livesLabel or statusFrame:FindFirstChild("LivesLabel")
        if not livesLabel then
            livesLabel = Instance.new("TextLabel")
            livesLabel.Name = "LivesLabel"
            livesLabel.Size = UDim2.new(1, -10, 0, 24)
            livesLabel.Position = UDim2.new(0, 5, 0, 30)
            livesLabel.BackgroundTransparency = 1
            livesLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
            livesLabel.Font = Enum.Font.GothamBold
            livesLabel.TextSize = 18
            livesLabel.Text = "Lives: 0"
            livesLabel.Parent = statusFrame
        end

        waveLabel = waveLabel or statusFrame:FindFirstChild("WaveLabel")
        if not waveLabel then
            waveLabel = Instance.new("TextLabel")
            waveLabel.Name = "WaveLabel"
            waveLabel.Size = UDim2.new(1, -10, 0, 24)
            waveLabel.Position = UDim2.new(0, 5, 0, 56)
            waveLabel.BackgroundTransparency = 1
            waveLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
            waveLabel.Font = Enum.Font.GothamBold
            waveLabel.TextSize = 18
            waveLabel.Text = "Wave: 0"
            waveLabel.Parent = statusFrame
        end

        startButton = startButton or statusFrame:FindFirstChild("StartButton")
        if not (startButton and startButton:IsA("TextButton")) then
            startButton = Instance.new("TextButton")
            startButton.Name = "StartButton"
            startButton.Size = UDim2.new(0, 180, 0, 36)
            startButton.Position = UDim2.new(0.5, -90, 0, 86)
            startButton.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
            startButton.TextColor3 = Color3.new(0, 0, 0)
            startButton.Font = Enum.Font.GothamBlack
            startButton.TextSize = 18
            startButton.Text = "Start"
            startButton.Parent = statusFrame
        end

        if not startButton:GetAttribute("TowerClientHooked") then
            startButton.MouseButton1Click:Connect(function()
                if gameEnded then
                    remotes.RequestRestart:FireServer()
                else
                    remotes.RequestWaveStart:FireServer()
                end
            end)
            startButton:SetAttribute("TowerClientHooked", true)
        end
    else
        warn("TowerClient: Status frame named 'Status' was not found. Add one to show money, lives, and wave info.")
    end

    towerDetailsFrame = towerDetailsFrame or screenGui:FindFirstChild("TowerDetails")
    if not towerDetailsFrame then
        towerDetailsFrame = Instance.new("Frame")
        towerDetailsFrame.Name = "TowerDetails"
        towerDetailsFrame.Size = UDim2.new(0, 220, 0, 260)
        towerDetailsFrame.Position = UDim2.new(1, -240, 0, 160)
        towerDetailsFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        towerDetailsFrame.BackgroundTransparency = 0.2
        towerDetailsFrame.BorderSizePixel = 0
        towerDetailsFrame.Visible = false
        towerDetailsFrame.Parent = screenGui

        local detailLayout = Instance.new("UIListLayout")
        detailLayout.Padding = UDim.new(0, 4)
        detailLayout.FillDirection = Enum.FillDirection.Vertical
        detailLayout.SortOrder = Enum.SortOrder.LayoutOrder
        detailLayout.Parent = towerDetailsFrame
    end

    towerNameLabel = towerNameLabel or towerDetailsFrame:FindFirstChild("TowerNameLabel")
    if not towerNameLabel then
        towerNameLabel = Instance.new("TextLabel")
        towerNameLabel.Name = "TowerNameLabel"
        towerNameLabel.BackgroundTransparency = 1
        towerNameLabel.Font = Enum.Font.GothamBold
        towerNameLabel.TextSize = 18
        towerNameLabel.TextColor3 = Color3.new(1, 1, 1)
        towerNameLabel.Text = ""
        towerNameLabel.Size = UDim2.new(1, -10, 0, 24)
        towerNameLabel.Position = UDim2.new(0, 5, 0, 0)
        towerNameLabel.Parent = towerDetailsFrame
    end

    towerLevelLabel = towerLevelLabel or towerDetailsFrame:FindFirstChild("TowerLevelLabel")
    if not towerLevelLabel then
        towerLevelLabel = Instance.new("TextLabel")
        towerLevelLabel.Name = "TowerLevelLabel"
        towerLevelLabel.BackgroundTransparency = 1
        towerLevelLabel.Font = Enum.Font.Gotham
        towerLevelLabel.TextSize = 16
        towerLevelLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerLevelLabel.Text = ""
        towerLevelLabel.Size = UDim2.new(1, -10, 0, 20)
        towerLevelLabel.Position = UDim2.new(0, 5, 0, 28)
        towerLevelLabel.Parent = towerDetailsFrame
    end

    towerStatsLabel = towerStatsLabel or towerDetailsFrame:FindFirstChild("TowerStatsLabel")
    if not towerStatsLabel then
        towerStatsLabel = Instance.new("TextLabel")
        towerStatsLabel.Name = "TowerStatsLabel"
        towerStatsLabel.BackgroundTransparency = 1
        towerStatsLabel.Font = Enum.Font.Gotham
        towerStatsLabel.TextSize = 15
        towerStatsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerStatsLabel.Text = ""
        towerStatsLabel.TextWrapped = true
        towerStatsLabel.Size = UDim2.new(1, -10, 0, 70)
        towerStatsLabel.Position = UDim2.new(0, 5, 0, 52)
        towerStatsLabel.Parent = towerDetailsFrame
    end

    ownershipLabel = ownershipLabel or towerDetailsFrame:FindFirstChild("OwnershipLabel")
    if not ownershipLabel then
        ownershipLabel = Instance.new("TextLabel")
        ownershipLabel.Name = "OwnershipLabel"
        ownershipLabel.BackgroundTransparency = 1
        ownershipLabel.Font = Enum.Font.Gotham
        ownershipLabel.TextSize = 14
        ownershipLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
        ownershipLabel.Text = ""
        ownershipLabel.Size = UDim2.new(1, -10, 0, 20)
        ownershipLabel.Position = UDim2.new(0, 5, 0, 124)
        ownershipLabel.Parent = towerDetailsFrame
    end

    upgradeDescriptionLabel = upgradeDescriptionLabel or towerDetailsFrame:FindFirstChild("UpgradeDescriptionLabel")
    if not upgradeDescriptionLabel then
        upgradeDescriptionLabel = Instance.new("TextLabel")
        upgradeDescriptionLabel.Name = "UpgradeDescriptionLabel"
        upgradeDescriptionLabel.BackgroundTransparency = 1
        upgradeDescriptionLabel.Font = Enum.Font.Gotham
        upgradeDescriptionLabel.TextSize = 14
        upgradeDescriptionLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
        upgradeDescriptionLabel.TextWrapped = true
        upgradeDescriptionLabel.Text = ""
        upgradeDescriptionLabel.Size = UDim2.new(1, -10, 0, 40)
        upgradeDescriptionLabel.Position = UDim2.new(0, 5, 0, 146)
        upgradeDescriptionLabel.Parent = towerDetailsFrame
    end

    upgradeButton = upgradeButton or towerDetailsFrame:FindFirstChild("UpgradeButton")
    if not (upgradeButton and upgradeButton:IsA("TextButton")) then
        upgradeButton = Instance.new("TextButton")
        upgradeButton.Name = "UpgradeButton"
        upgradeButton.Size = UDim2.new(1, -10, 0, 32)
        upgradeButton.Position = UDim2.new(0, 5, 0, 190)
        upgradeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        upgradeButton.TextColor3 = Color3.new(1, 1, 1)
        upgradeButton.Font = Enum.Font.GothamBold
        upgradeButton.TextSize = 16
        upgradeButton.Text = "Upgrade (E)"
        upgradeButton.AutoButtonColor = false
        upgradeButton.Visible = false
        upgradeButton.Parent = towerDetailsFrame
    end

    if not upgradeButton:GetAttribute("TowerClientHooked") then
        upgradeButton.MouseButton1Click:Connect(function()
            if selectedTower then
                remotes.TowerUpgradeRequested:FireServer(selectedTower)
            end
        end)
        upgradeButton:SetAttribute("TowerClientHooked", true)
    end

    sellButton = sellButton or towerDetailsFrame:FindFirstChild("SellButton")
    if not (sellButton and sellButton:IsA("TextButton")) then
        sellButton = Instance.new("TextButton")
        sellButton.Name = "SellButton"
        sellButton.Size = UDim2.new(1, -10, 0, 32)
        sellButton.Position = UDim2.new(0, 5, 0, 228)
        sellButton.BackgroundColor3 = Color3.fromRGB(220, 120, 120)
        sellButton.TextColor3 = Color3.new(0, 0, 0)
        sellButton.Font = Enum.Font.GothamBold
        sellButton.TextSize = 16
        sellButton.Text = "Sell (X)"
        sellButton.AutoButtonColor = true
        sellButton.Visible = false
        sellButton.Parent = towerDetailsFrame
    end

    if not sellButton:GetAttribute("TowerClientHooked") then
        sellButton.MouseButton1Click:Connect(function()
            if selectedTower then
                remotes.TowerSoldRequested:FireServer(selectedTower)
            end
        end)
        sellButton:SetAttribute("TowerClientHooked", true)
    end

    updateAllEnemyBillboards()
    updateStartButtonVisual()

    remotes.MoneyChanged.OnClientEvent:Connect(function(money)
        currentMoney = money
        if moneyLabel then
            moneyLabel.Text = string.format("$%d", money)
        end
        if selectedTower then
            updateTowerDetails(selectedTower)
        end
    end)

    remotes.LivesChanged.OnClientEvent:Connect(function(lives)
        if livesLabel then
            livesLabel.Text = string.format("Lives: %d", lives)
        end
    end)

    remotes.WaveStarted.OnClientEvent:Connect(function(wave)
        if waveLabel then
            waveLabel.Text = string.format("Wave: %d", wave)
        end
    end)

    remotes.GameEnded.OnClientEvent:Connect(function(victory)
        gameEnded = true
        lastVictoryState = victory
        updateStartButtonVisual()
        if selectedTower then
            updateTowerDetails(selectedTower)
        end
    end)

    remotes.GameRestarted.OnClientEvent:Connect(function()
        gameEnded = false
        lastVictoryState = nil
        updateStartButtonVisual()
        clearSelection()
        destroyRangeIndicator()
        cancelPlacement()
        if waveLabel then
            waveLabel.Text = "Wave: 0"
        end
        if hoverBillboard then
            hoverBillboard.Enabled = false
        end
        updateAllEnemyBillboards()
    end)

    return screenGui
end

createGui()

local function clearSelection()
    selectedTower = nil
    disconnectSelectedConnections()
    destroyRangeIndicator()
    if towerDetailsFrame then
        towerDetailsFrame.Visible = false
    end
    if upgradeDescriptionLabel then
        upgradeDescriptionLabel.Text = ""
    end
    if sellButton then
        sellButton.Visible = false
    end
end

local function selectTower(towerModel)
    if not towerModel then
        clearSelection()
        return
    end

    if selectedTower == towerModel then
        updateTowerDetails(towerModel)
        return
    end

    clearSelection()
    selectedTower = towerModel
    updateTowerDetails(towerModel)

    selectedTowerConnections = {
        towerModel.AncestryChanged:Connect(function(_, parent)
            if not parent then
                clearSelection()
            end
        end),
        towerModel:GetAttributeChangedSignal("Level"):Connect(function()
            if selectedTower == towerModel then
                updateTowerDetails(towerModel)
            end
        end),
        towerModel:GetAttributeChangedSignal("Range"):Connect(function()
            if selectedTower == towerModel then
                updateTowerDetails(towerModel)
            end
        end),
        towerModel:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
            if selectedTower == towerModel then
                updateTowerDetails(towerModel)
            end
        end),
        towerModel:GetAttributeChangedSignal("SellValue"):Connect(function()
            if selectedTower == towerModel then
                updateTowerDetails(towerModel)
            end
        end)
    }
end

local function isOnBuildableGround(hitInstance)
    if not hitInstance then
        return false
    end

    local map = workspace:FindFirstChild("Map")
    if not map then
        return false
    end

    local ground = map:FindFirstChild("PathGround")
    if not ground then
        return false
    end

    if hitInstance == ground then
        return true
    end

    return hitInstance:IsDescendantOf(ground)
end

local function isPositionClear(position)
    local towersFolder = workspace:FindFirstChild("Towers")
    if not towersFolder then
        return true
    end

    for _, tower in ipairs(towersFolder:GetChildren()) do
        local primary = tower.PrimaryPart or tower:FindFirstChild("Base")
        if primary then
            local towerPos = primary.Position
            local horizontalDistance = (Vector3.new(towerPos.X, 0, towerPos.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
            local otherRadius = math.max(primary.Size.X, primary.Size.Z) / 2
            local spacing = otherRadius + previewFootprintRadius
            if horizontalDistance < spacing then
                return false
            end
        end
    end

    return true
end

local function computePlacementValidity(position, hitInstance)
    if not hitInstance then
        return false
    end

    if not isOnBuildableGround(hitInstance) then
        return false
    end

    return isPositionClear(position)
end

local function updatePreview()
    if not placingTowerType or not previewPart then
        placementValid = false
        return
    end

    local unitRay = mouse.UnitRay
    local rayResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, createRaycastParams())
    if rayResult then
        local hitPosition = rayResult.Position
        local previewPosition = Vector3.new(hitPosition.X, hitPosition.Y + previewPart.Size.Y / 2, hitPosition.Z)
        previewPart.CFrame = CFrame.new(previewPosition)
        local config = towerConfigs[placingTowerType]
        if previewRangeRing and previewRangeAdornment and config and config.Range then
            local ringY = hitPosition.Y + 0.05
            updateRangeRing(previewRangeRing, previewRangeAdornment, config.Range, Vector3.new(hitPosition.X, ringY, hitPosition.Z))
        end
        placementValid = computePlacementValidity(hitPosition, rayResult.Instance)
        local validColor = placementValid and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(255, 100, 100)
        previewPart.Color = validColor
        if previewRangeAdornment then
            if placementValid then
                previewRangeAdornment.Color3 = Color3.fromRGB(120, 220, 255)
                previewRangeAdornment.Transparency = 0.45
            else
                previewRangeAdornment.Color3 = Color3.fromRGB(255, 150, 150)
                previewRangeAdornment.Transparency = 0.6
            end
        end
    else
        placementValid = false
        previewPart.Color = Color3.fromRGB(255, 100, 100)
        if previewRangeAdornment then
            previewRangeAdornment.Color3 = Color3.fromRGB(255, 150, 150)
            previewRangeAdornment.Transparency = 0.6
        end
    end
end

local function updateEnemyHover()
    local target = mouse.Target
    local enemyModel = getEnemyModelFromInstance(target)
    if enemyModel then
        local billboard = ensureHoverBillboard()
        local adornee = enemyModel.PrimaryPart or enemyModel:FindFirstChild("HumanoidRootPart") or enemyModel:FindFirstChild("Head")
        if adornee then
            billboard.Adornee = adornee
            local healthValue = enemyModel:FindFirstChild("HealthValue")
            local maxHealth = enemyModel:GetAttribute("MaxHealth")
            local displayName = enemyModel:GetAttribute("DisplayName") or enemyModel.Name or "Enemy"
            local currentHealth = nil
            if healthValue then
                currentHealth = math.max(0, math.floor(healthValue.Value + 0.5))
            end

            if hoverNameLabel then
                hoverNameLabel.Text = displayName
            end

            if hoverHealthLabel then
                if currentHealth and typeof(maxHealth) == "number" then
                    hoverHealthLabel.Text = string.format("HP: %d / %d", currentHealth, maxHealth)
                elseif currentHealth then
                    hoverHealthLabel.Text = string.format("HP: %d", currentHealth)
                else
                    hoverHealthLabel.Text = "HP: ???"
                end
            elseif hoverCombinedLabel then
                if currentHealth and typeof(maxHealth) == "number" then
                    hoverCombinedLabel.Text = string.format("%s - HP: %d / %d", displayName, currentHealth, maxHealth)
                elseif currentHealth then
                    hoverCombinedLabel.Text = string.format("%s - HP: %d", displayName, currentHealth)
                else
                    hoverCombinedLabel.Text = string.format("%s - HP: ???", displayName)
                end
            end
            billboard.Enabled = true
        else
            billboard.Enabled = false
        end
    else
        if hoverBillboard then
            hoverBillboard.Enabled = false
        end
    end
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if placingTowerType then
            local unitRay = mouse.UnitRay
            local rayResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, createRaycastParams())
            if rayResult and computePlacementValidity(rayResult.Position, rayResult.Instance) then
                remotes.TowerPlaced:FireServer(placingTowerType, rayResult.Position)
                cancelPlacement()
            end
        else
            local towerModel = getTowerModelFromInstance(mouse.Target)
            if towerModel then
                selectTower(towerModel)
            else
                clearSelection()
            end
        end
    elseif input.KeyCode == Enum.KeyCode.X then
        if placingTowerType then
            cancelPlacement()
        elseif selectedTower and not placingTowerType then
            local ownerId = selectedTower:GetAttribute("OwnerUserId")
            if ownerId == player.UserId and not gameEnded then
                remotes.TowerSellRequested:FireServer(selectedTower)
            end
        end
    elseif input.KeyCode == Enum.KeyCode.E then
        if not placingTowerType and selectedTower then
            local ownerId = selectedTower:GetAttribute("OwnerUserId")
            if ownerId == player.UserId and not gameEnded then
                remotes.TowerUpgradeRequested:FireServer(selectedTower)
            end
        end
    end
end)

remotes.TowerUpgraded.OnClientEvent:Connect(function(towerModel)
    if selectedTower and towerModel == selectedTower then
        updateTowerDetails(towerModel)
    end
end)

if remotes:FindFirstChild("SplashFired") then
    remotes.SplashFired.OnClientEvent:Connect(function(position, radius, color)
        showExplosion(position, radius, color)
    end)
end

RunService.RenderStepped:Connect(function()
    updatePreview()
    updateEnemyHover()

    if selectedTower and (not selectedTower.Parent) then
        clearSelection()
    end
end)

