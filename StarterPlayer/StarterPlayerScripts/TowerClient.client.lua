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
local hoverGuiContainer
local hoverGui
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
local priceLabelContainer
local upgradePriceLabel
local sellPriceLabel

local upgradeButtonOriginalColor
local upgradeButtonOriginalTextColor
local upgradeButtonOriginalBackgroundTransparency
local upgradeButtonOriginalTextTransparency
local upgradeButtonOriginalAutoButtonColor
local sellButtonOriginalAutoButtonColor
local priceLabelsCanShow = false
local GREY_COLOR = Color3.new(0.5, 0.5, 0.5)

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
    priceLabelsCanShow = false
    if priceLabelContainer then
        priceLabelContainer.Visible = false
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
        if lastVictoryState == true then
            text = "Victory! Restart"
        elseif lastVictoryState == false then
            text = "Defeat! Restart"
        end

        if autoText ~= false then
            startButton.Text = text
        end
    else
        if autoText ~= false then
            startButton.Text = "Start"
        end
    end
end

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

local function ensureHoverGui()
    if hoverGui then
        return hoverGui
    end

    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    local uiFolder = assetsFolder and assetsFolder:FindFirstChild("UI")
    local template = uiFolder and uiFolder:FindFirstChild("EnemyHoverTemplate")

    if not template then
        warn("TowerClient: EnemyHoverTemplate was not found under ReplicatedStorage/Assets/UI.")
        return nil
    end

    if template:IsA("ScreenGui") then
        hoverGuiContainer = template:Clone()
        hoverGuiContainer.ResetOnSpawn = false
        hoverGuiContainer.IgnoreGuiInset = true
        hoverGuiContainer.Enabled = true
        hoverGuiContainer.Parent = playerGui
        hoverGui = hoverGuiContainer:FindFirstChildWhichIsA("GuiObject", true)
        if not hoverGui then
            warn("TowerClient: EnemyHoverTemplate ScreenGui does not contain any GuiObjects to display.")
            return nil
        end
    elseif template:IsA("GuiObject") then
        hoverGuiContainer = Instance.new("ScreenGui")
        hoverGuiContainer.Name = "EnemyHoverUI"
        hoverGuiContainer.ResetOnSpawn = false
        hoverGuiContainer.IgnoreGuiInset = true
        hoverGuiContainer.Parent = playerGui

        hoverGui = template:Clone()
        hoverGui.Parent = hoverGuiContainer
    else
        warn("TowerClient: EnemyHoverTemplate must be a GuiObject or ScreenGui.")
        return nil
    end

    if hoverGui:IsA("GuiObject") then
        hoverGui.Visible = false
    end

    hoverNameLabel = hoverGui:FindFirstChild("NameLabel", true)
    hoverHealthLabel = hoverGui:FindFirstChild("HealthLabel", true)
    hoverCombinedLabel = hoverGui:FindFirstChild("InfoLabel", true)

    if not hoverNameLabel and not hoverHealthLabel and not hoverCombinedLabel then
        warn("TowerClient: EnemyHoverTemplate is missing NameLabel/HealthLabel/InfoLabel text objects.")
    end

    return hoverGui
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

local function applyUpgradeButtonStyle(disabled)
    if not upgradeButton then
        return
    end

    if not upgradeButtonOriginalColor then
        upgradeButtonOriginalColor = upgradeButton.BackgroundColor3
    end
    if not upgradeButtonOriginalTextColor then
        upgradeButtonOriginalTextColor = upgradeButton.TextColor3
    end
    if upgradeButtonOriginalBackgroundTransparency == nil then
        upgradeButtonOriginalBackgroundTransparency = upgradeButton.BackgroundTransparency
    end
    if upgradeButtonOriginalTextTransparency == nil then
        upgradeButtonOriginalTextTransparency = upgradeButton.TextTransparency
    end

    if disabled then
        if upgradeButtonOriginalColor then
            upgradeButton.BackgroundColor3 = upgradeButtonOriginalColor:Lerp(GREY_COLOR, 0.2)
        end
        if upgradeButtonOriginalTextColor then
            upgradeButton.TextColor3 = upgradeButtonOriginalTextColor:Lerp(GREY_COLOR, 0.2)
        end
    else
        if upgradeButtonOriginalColor then
            upgradeButton.BackgroundColor3 = upgradeButtonOriginalColor
        end
        if upgradeButtonOriginalTextColor then
            upgradeButton.TextColor3 = upgradeButtonOriginalTextColor
        end
    end

    if upgradeButtonOriginalBackgroundTransparency ~= nil then
        upgradeButton.BackgroundTransparency = upgradeButtonOriginalBackgroundTransparency
    end
    if upgradeButtonOriginalTextTransparency ~= nil then
        upgradeButton.TextTransparency = upgradeButtonOriginalTextTransparency
    end
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
        upgradeButton.AutoButtonColor = false
        upgradeButton.Active = false
        applyUpgradeButtonStyle(true)
        upgradeButton.Visible = true
        return
    end

    if ownerUserId ~= player.UserId then
        upgradeButton.Text = "Not your tower"
        upgradeButton.AutoButtonColor = false
        upgradeButton.Active = false
        applyUpgradeButtonStyle(true)
        upgradeButton.Visible = true
        return
    end

    local affordable = currentMoney >= nextUpgrade.Cost
    if upgradeButtonOriginalAutoButtonColor == nil then
        upgradeButtonOriginalAutoButtonColor = upgradeButton.AutoButtonColor
    end
    upgradeButton.Text = string.format("Upgrade (E) - $%d", nextUpgrade.Cost)
    upgradeButton.Active = affordable
    upgradeButton.AutoButtonColor = affordable and upgradeButtonOriginalAutoButtonColor or false
    applyUpgradeButtonStyle(not affordable)
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
    if sellButtonOriginalAutoButtonColor == nil then
        sellButtonOriginalAutoButtonColor = sellButton.AutoButtonColor
    end
    sellButton.AutoButtonColor = active and sellButtonOriginalAutoButtonColor or false
    sellButton.Active = active
    sellButton.Selectable = active
end

local function updateTowerPriceLabels(towerModel, towerType, level, ownerUserId)
    if not priceLabelContainer then
        priceLabelsCanShow = false
        return
    end

    local isOwner = ownerUserId == player.UserId
    priceLabelsCanShow = isOwner
    if not isOwner then
        priceLabelContainer.Visible = false
        return
    end

    local nextUpgrade = getNextUpgrade(towerType, level)
    if upgradePriceLabel then
        if nextUpgrade then
            upgradePriceLabel.Text = string.format("Upgrade: $%d", nextUpgrade.Cost)
        else
            upgradePriceLabel.Text = "Upgrade: Max"
        end
    end

    if sellPriceLabel then
        local sellValue = towerModel and towerModel:GetAttribute("SellValue")
        if typeof(sellValue) == "number" and sellValue > 0 then
            sellPriceLabel.Text = string.format("Sell: +$%d", math.floor(sellValue + 0.5))
        else
            sellPriceLabel.Text = "Sell: N/A"
        end
    end
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
    updateTowerPriceLabels(towerModel, towerType, level, ownerUserId)
end

local function createGui()
    if screenGui then
        return screenGui
    end

    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    local uiFolder = assetsFolder and assetsFolder:FindFirstChild("UI")
    local template = uiFolder and uiFolder:FindFirstChild("TowerHUD")

    if not (template and template:IsA("ScreenGui")) then
        warn("TowerClient: Provide a ScreenGui named 'TowerHUD' under ReplicatedStorage/Assets/UI.")
        return nil
    end

    screenGui = template:Clone()
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = playerGui

    shopFrame = screenGui:FindFirstChild("Shop", true)
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

    statusFrame = screenGui:FindFirstChild("Status", true)
    if statusFrame then
        moneyLabel = statusFrame:FindFirstChild("MoneyLabel", true)
        if not moneyLabel then
            warn("TowerClient: MoneyLabel was not found inside the Status frame.")
        end

        livesLabel = statusFrame:FindFirstChild("LivesLabel", true)
        if not livesLabel then
            warn("TowerClient: LivesLabel was not found inside the Status frame.")
        end

        waveLabel = statusFrame:FindFirstChild("WaveLabel", true)
        if not waveLabel then
            warn("TowerClient: WaveLabel was not found inside the Status frame.")
        end

        startButton = statusFrame:FindFirstChild("StartButton", true)
        if startButton and startButton:IsA("TextButton") then
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
            if startButton then
                warn("TowerClient: StartButton must be a TextButton inside the Status frame.")
            else
                warn("TowerClient: StartButton was not found inside the Status frame.")
            end
            startButton = nil
        end
    else
        warn("TowerClient: Status frame named 'Status' was not found. Add one to show money, lives, and wave info.")
    end

    towerDetailsFrame = screenGui:FindFirstChild("TowerDetails", true)
    if towerDetailsFrame then
        towerNameLabel = towerDetailsFrame:FindFirstChild("TowerNameLabel", true)
        if not towerNameLabel then
            warn("TowerClient: TowerNameLabel was not found inside TowerDetails.")
        end

        towerLevelLabel = towerDetailsFrame:FindFirstChild("TowerLevelLabel", true)
        if not towerLevelLabel then
            warn("TowerClient: TowerLevelLabel was not found inside TowerDetails.")
        end

        towerStatsLabel = towerDetailsFrame:FindFirstChild("TowerStatsLabel", true)
        if not towerStatsLabel then
            warn("TowerClient: TowerStatsLabel was not found inside TowerDetails.")
        end

        ownershipLabel = towerDetailsFrame:FindFirstChild("OwnershipLabel", true)
        if not ownershipLabel then
            warn("TowerClient: OwnershipLabel was not found inside TowerDetails.")
        end

        upgradeDescriptionLabel = towerDetailsFrame:FindFirstChild("UpgradeDescriptionLabel", true)
        if not upgradeDescriptionLabel then
            warn("TowerClient: UpgradeDescriptionLabel was not found inside TowerDetails.")
        end

        upgradeButton = towerDetailsFrame:FindFirstChild("UpgradeButton", true)
        if upgradeButton and upgradeButton:IsA("TextButton") then
            upgradeButtonOriginalColor = upgradeButton.BackgroundColor3
            upgradeButtonOriginalTextColor = upgradeButton.TextColor3
            upgradeButtonOriginalBackgroundTransparency = upgradeButton.BackgroundTransparency
            upgradeButtonOriginalTextTransparency = upgradeButton.TextTransparency
            upgradeButtonOriginalAutoButtonColor = upgradeButton.AutoButtonColor
            if not upgradeButton:GetAttribute("TowerClientHooked") then
                upgradeButton.MouseButton1Click:Connect(function()
                    if selectedTower then
                        remotes.TowerUpgradeRequested:FireServer(selectedTower)
                    end
                end)
                upgradeButton:SetAttribute("TowerClientHooked", true)
            end
        else
            if upgradeButton then
                warn("TowerClient: UpgradeButton inside TowerDetails must be a TextButton.")
            else
                warn("TowerClient: UpgradeButton was not found inside TowerDetails.")
            end
            upgradeButton = nil
        end

        sellButton = towerDetailsFrame:FindFirstChild("SellButton", true)
        if sellButton and sellButton:IsA("TextButton") then
            sellButtonOriginalAutoButtonColor = sellButton.AutoButtonColor
            if not sellButton:GetAttribute("TowerClientHooked") then
                sellButton.MouseButton1Click:Connect(function()
                    if selectedTower then
                        remotes.TowerSoldRequested:FireServer(selectedTower)
                    end
                end)
                sellButton:SetAttribute("TowerClientHooked", true)
            end
        else
            if sellButton then
                warn("TowerClient: SellButton inside TowerDetails must be a TextButton.")
            else
                warn("TowerClient: SellButton was not found inside TowerDetails.")
            end
            sellButton = nil
        end
    else
        warn("TowerClient: TowerDetails frame was not found. Selection UI will be hidden.")
    end

    priceLabelContainer = screenGui:FindFirstChild("PlayerTowerPriceLabels", true)
    if priceLabelContainer and priceLabelContainer:IsA("GuiObject") then
        upgradePriceLabel = priceLabelContainer:FindFirstChild("UpgradePriceLabel", true)
        sellPriceLabel = priceLabelContainer:FindFirstChild("SellPriceLabel", true)
        priceLabelContainer.Visible = false
    elseif priceLabelContainer then
        warn("TowerClient: PlayerTowerPriceLabels must be a GuiObject to toggle visibility.")
        priceLabelContainer = nil
    else
        warn("TowerClient: PlayerTowerPriceLabels container not found. Hover price labels will be disabled.")
    end

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
        if hoverGui and hoverGui:IsA("GuiObject") then
            hoverGui.Visible = false
        end
        priceLabelsCanShow = false
        if priceLabelContainer then
            priceLabelContainer.Visible = false
        end
    end)

    return screenGui
end

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
    priceLabelsCanShow = false
    if priceLabelContainer then
        priceLabelContainer.Visible = false
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

local function updatePriceLabelHoverState()
    if not priceLabelContainer then
        return
    end

    if not priceLabelsCanShow or not selectedTower then
        if priceLabelContainer.Visible then
            priceLabelContainer.Visible = false
        end
        return
    end

    local target = mouse.Target
    if target and target:IsDescendantOf(selectedTower) then
        priceLabelContainer.Visible = true
    elseif priceLabelContainer.Visible then
        priceLabelContainer.Visible = false
    end
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
        local guiObject = ensureHoverGui()
        if not (guiObject and guiObject:IsA("GuiObject")) then
            return
        end

        local healthValue = enemyModel:FindFirstChild("HealthValue")
        local maxHealth = enemyModel:GetAttribute("MaxHealth")
        local displayName = enemyModel:GetAttribute("DisplayName") or enemyModel.Name or "Enemy"
        local currentHealth
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

        local mousePosition = Vector2.new(mouse.X, mouse.Y)
        local offsetX = guiObject:GetAttribute("OffsetX") or 16
        local offsetY = guiObject:GetAttribute("OffsetY") or 16
        guiObject.Position = UDim2.fromOffset(mousePosition.X + offsetX, mousePosition.Y + offsetY)
        guiObject.Visible = true
    else
        if hoverGui and hoverGui:IsA("GuiObject") then
            hoverGui.Visible = false
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
    updatePriceLabelHoverState()

    if selectedTower and (not selectedTower.Parent) then
        clearSelection()
    end
end)

