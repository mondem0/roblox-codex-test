local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local hoverLabel
local selectedTower
local rangeRing
local rangeRingAdornment
local previewRangeRing
local previewRangeAdornment
local selectedTowerConnections = {}
local currentMoney = 0
local showEnemyHP = true
local gameEnded = false
local hpToggleButton

local towerDetailsFrame
local towerNameLabel
local towerLevelLabel
local towerStatsLabel
local ownershipLabel
local upgradeDescriptionLabel
local upgradeButton
local sellButton

local PREVIEW_SIZE = Vector3.new(4, 1, 4)
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

local function cancelPlacement()
    placingTowerType = nil
    if previewPart then
        previewPart:Destroy()
        previewPart = nil
    end
    destroyPreviewRangeIndicator()
    placementValid = false
end

local function applyEnemyBillboardState(enemyModel)
    local display = enemyModel:FindFirstChild("HealthDisplay")
    if display and display:IsA("BillboardGui") then
        display.Enabled = showEnemyHP
    end
end

local function watchEnemy(enemyModel)
    if not enemyModel or not enemyModel:IsA("Model") then
        return
    end

    applyEnemyBillboardState(enemyModel)
    enemyModel.ChildAdded:Connect(function(child)
        if child.Name == "HealthDisplay" and child:IsA("BillboardGui") then
            child.Enabled = showEnemyHP
        end
    end)
end

local function updateAllEnemyBillboards()
    for _, enemy in ipairs(enemiesFolder:GetChildren()) do
        applyEnemyBillboardState(enemy)
    end
end

local function updateHPToggleVisual()
    if not hpToggleButton then
        return
    end

    hpToggleButton.Text = showEnemyHP and "Hide Enemy HP" or "Show Enemy HP"
    hpToggleButton.BackgroundColor3 = showEnemyHP and Color3.fromRGB(220, 120, 120) or Color3.fromRGB(80, 200, 120)
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

local function ensureHoverBillboard()
    if hoverBillboard then
        return hoverBillboard
    end

    hoverBillboard = Instance.new("BillboardGui")
    hoverBillboard.Name = "EnemyHoverInfo"
    hoverBillboard.Size = UDim2.new(0, 140, 0, 40)
    hoverBillboard.AlwaysOnTop = true
    hoverBillboard.Enabled = false
    hoverBillboard.ExtentsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
    hoverBillboard.Parent = playerGui

    hoverLabel = Instance.new("TextLabel")
    hoverLabel.BackgroundTransparency = 1
    hoverLabel.Size = UDim2.fromScale(1, 1)
    hoverLabel.Font = Enum.Font.GothamBold
    hoverLabel.TextScaled = true
    hoverLabel.TextColor3 = Color3.new(1, 1, 1)
    hoverLabel.TextStrokeTransparency = 0.3
    hoverLabel.Parent = hoverBillboard

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
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TowerDefenseUI"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Shop"
    frame.Size = UDim2.new(0, 250, 0, 200)
    frame.Position = UDim2.new(0, 20, 1, -210)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BackgroundTransparency = 0.2
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local uiList = Instance.new("UIListLayout")
    uiList.Padding = UDim.new(0, 6)
    uiList.FillDirection = Enum.FillDirection.Vertical
    uiList.SortOrder = Enum.SortOrder.LayoutOrder
    uiList.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 24)
    title.Text = "TOWERS"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = frame

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
        button.Parent = frame

        button.MouseButton1Click:Connect(function()
            placingTowerType = key
            if not previewPart then
                previewPart = Instance.new("Part")
                previewPart.Anchored = true
                previewPart.CanCollide = false
                previewPart.Transparency = 0.5
                previewPart.Color = Color3.fromRGB(255, 100, 100)
                previewPart.Size = PREVIEW_SIZE
                previewPart.Name = "PlacementPreview"
                previewPart.Parent = workspace
            end
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
        end)
    end

    local statusFrame = Instance.new("Frame")
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

    local moneyLabel = Instance.new("TextLabel")
    moneyLabel.Name = "MoneyLabel"
    moneyLabel.Size = UDim2.new(1, -10, 0, 24)
    moneyLabel.Position = UDim2.new(0, 5, 0, 0)
    moneyLabel.BackgroundTransparency = 1
    moneyLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
    moneyLabel.Font = Enum.Font.GothamBold
    moneyLabel.TextSize = 18
    moneyLabel.Text = "$0"
    moneyLabel.Parent = statusFrame

    local livesLabel = Instance.new("TextLabel")
    livesLabel.Name = "LivesLabel"
    livesLabel.Size = UDim2.new(1, -10, 0, 24)
    livesLabel.Position = UDim2.new(0, 5, 0, 30)
    livesLabel.BackgroundTransparency = 1
    livesLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
    livesLabel.Font = Enum.Font.GothamBold
    livesLabel.TextSize = 18
    livesLabel.Text = "Lives: 0"
    livesLabel.Parent = statusFrame

    local waveLabel = Instance.new("TextLabel")
    waveLabel.Name = "WaveLabel"
    waveLabel.Size = UDim2.new(1, -10, 0, 24)
    waveLabel.Position = UDim2.new(0, 5, 0, 56)
    waveLabel.BackgroundTransparency = 1
    waveLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
    waveLabel.Font = Enum.Font.GothamBold
    waveLabel.TextSize = 18
    waveLabel.Text = "Wave: 0"
    waveLabel.Parent = statusFrame

    local startButton = Instance.new("TextButton")
    startButton.Name = "StartButton"
    startButton.Size = UDim2.new(0, 180, 0, 36)
    startButton.Position = UDim2.new(0.5, -90, 0, 86)
    startButton.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
    startButton.TextColor3 = Color3.new(0, 0, 0)
    startButton.Font = Enum.Font.GothamBlack
    startButton.TextSize = 18
    startButton.Text = "Start"
    startButton.Parent = statusFrame

    local lastVictoryState

    local function updateStartButtonVisual()
        if not startButton or not startButton.Parent then
            return
        end

        if gameEnded then
            if lastVictoryState == true then
                startButton.Text = "Victory! Restart"
                startButton.BackgroundColor3 = Color3.fromRGB(120, 255, 120)
            elseif lastVictoryState == false then
                startButton.Text = "Defeat! Restart"
                startButton.BackgroundColor3 = Color3.fromRGB(255, 120, 120)
            else
                startButton.Text = "Restart"
                startButton.BackgroundColor3 = Color3.fromRGB(120, 120, 255)
            end
        else
            startButton.Text = "Start"
            startButton.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
        end
    end

    startButton.MouseButton1Click:Connect(function()
        if gameEnded then
            remotes.RequestRestart:FireServer()
        else
            remotes.RequestWaveStart:FireServer()
        end
    end)

    hpToggleButton = Instance.new("TextButton")
    hpToggleButton.Name = "HPToggleButton"
    hpToggleButton.Size = UDim2.new(0, 180, 0, 30)
    hpToggleButton.Position = UDim2.new(0.5, -90, 0, 128)
    hpToggleButton.BackgroundColor3 = Color3.fromRGB(220, 120, 120)
    hpToggleButton.TextColor3 = Color3.new(0, 0, 0)
    hpToggleButton.Font = Enum.Font.GothamBold
    hpToggleButton.TextSize = 16
    hpToggleButton.Text = "Hide Enemy HP"
    hpToggleButton.Parent = statusFrame

    hpToggleButton.MouseButton1Click:Connect(function()
        showEnemyHP = not showEnemyHP
        updateHPToggleVisual()
        updateAllEnemyBillboards()
    end)

    updateHPToggleVisual()
    updateAllEnemyBillboards()

    remotes.MoneyChanged.OnClientEvent:Connect(function(money)
        currentMoney = money
        moneyLabel.Text = string.format("$%d", money)
        if selectedTower then
            updateTowerDetails(selectedTower)
        end
    end)

    remotes.LivesChanged.OnClientEvent:Connect(function(lives)
        livesLabel.Text = string.format("Lives: %d", lives)
    end)

    remotes.WaveStarted.OnClientEvent:Connect(function(wave)
        waveLabel.Text = string.format("Wave: %d", wave)
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
        waveLabel.Text = "Wave: 0"
        if hoverBillboard then
            hoverBillboard.Enabled = false
        end
        updateAllEnemyBillboards()
    end)

    updateStartButtonVisual()

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
    towerNameLabel.BackgroundTransparency = 1
    towerNameLabel.Font = Enum.Font.GothamBold
    towerNameLabel.TextSize = 18
    towerNameLabel.TextColor3 = Color3.new(1, 1, 1)
    towerNameLabel.Text = ""
    towerNameLabel.Size = UDim2.new(1, -10, 0, 24)
    towerNameLabel.Position = UDim2.new(0, 5, 0, 0)
    towerNameLabel.Parent = towerDetailsFrame

    towerLevelLabel = Instance.new("TextLabel")
    towerLevelLabel.BackgroundTransparency = 1
    towerLevelLabel.Font = Enum.Font.Gotham
    towerLevelLabel.TextSize = 16
    towerLevelLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    towerLevelLabel.Text = ""
    towerLevelLabel.Size = UDim2.new(1, -10, 0, 20)
    towerLevelLabel.Position = UDim2.new(0, 5, 0, 28)
    towerLevelLabel.Parent = towerDetailsFrame

    towerStatsLabel = Instance.new("TextLabel")
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
    ownershipLabel.BackgroundTransparency = 1
    ownershipLabel.Font = Enum.Font.Gotham
    ownershipLabel.TextSize = 14
    ownershipLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
    ownershipLabel.Text = ""
    ownershipLabel.Size = UDim2.new(1, -10, 0, 20)
    ownershipLabel.Position = UDim2.new(0, 5, 0, 124)
    ownershipLabel.Parent = towerDetailsFrame

    upgradeDescriptionLabel = Instance.new("TextLabel")
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
    upgradeButton.MouseButton1Click:Connect(function()
        if selectedTower then
            remotes.TowerUpgradeRequested:FireServer(selectedTower)
        end
    end)

    sellButton = Instance.new("TextButton")
    sellButton.Name = "SellButton"
    sellButton.Size = UDim2.new(1, -10, 0, 32)
    sellButton.Position = UDim2.new(0, 5, 0, 226)
    sellButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    sellButton.TextColor3 = Color3.fromRGB(200, 200, 200)
    sellButton.Font = Enum.Font.GothamBold
    sellButton.TextSize = 16
    sellButton.Text = "Sell (X)"
    sellButton.AutoButtonColor = false
    sellButton.Visible = false
    sellButton.Parent = towerDetailsFrame
    sellButton.MouseButton1Click:Connect(function()
        if selectedTower then
            remotes.TowerSellRequested:FireServer(selectedTower)
        end
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
            local spacing = (primary.Size.X / 2) + (PREVIEW_SIZE.X / 2)
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
            if healthValue and hoverLabel then
                local currentHealth = math.max(0, math.floor(healthValue.Value + 0.5))
                if typeof(maxHealth) == "number" then
                    hoverLabel.Text = string.format("HP: %d / %d", currentHealth, maxHealth)
                else
                    hoverLabel.Text = string.format("HP: %d", currentHealth)
                end
            elseif hoverLabel then
                hoverLabel.Text = "HP: ???"
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

RunService.RenderStepped:Connect(function()
    updatePreview()
    updateEnemyHover()

    if selectedTower and (not selectedTower.Parent) then
        clearSelection()
    end
end)

