local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local towerConfigs = require(ReplicatedStorage.Modules.Config.TowerConfigs)

local placingTowerType
local previewPart

local function createRaycastParams()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.IgnoreWater = true

    local ignoreList = { player.Character }
    if previewPart then
        table.insert(ignoreList, previewPart)
    end

    params.FilterDescendantsInstances = ignoreList
    return params
end

local function createGui()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TowerDefenseUI"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = player:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Name = "Shop"
    frame.Size = UDim2.new(0, 250, 0, 140)
    frame.Position = UDim2.new(0, 20, 1, -160)
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
                previewPart.Color = Color3.fromRGB(0, 170, 255)
                previewPart.Size = Vector3.new(4, 1, 4)
                previewPart.Name = "PlacementPreview"
                previewPart.Parent = workspace
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

    startButton.MouseButton1Click:Connect(function()
        remotes.RequestWaveStart:FireServer()
    end)

    remotes.MoneyChanged.OnClientEvent:Connect(function(money)
        moneyLabel.Text = string.format("$%d", money)
    end)

    remotes.LivesChanged.OnClientEvent:Connect(function(lives)
        livesLabel.Text = string.format("Lives: %d", lives)
    end)

    remotes.WaveStarted.OnClientEvent:Connect(function(wave)
        waveLabel.Text = string.format("Wave: %d", wave)
    end)

    remotes.GameEnded.OnClientEvent:Connect(function(victory)
        startButton.Text = victory and "Victory!" or "Defeat"
        startButton.BackgroundColor3 = victory and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 120, 120)
    end)

    return screenGui
end

createGui()

local function cancelPlacement()
    placingTowerType = nil
    if previewPart then
        previewPart:Destroy()
        previewPart = nil
    end
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

local function updatePreview()
    if not placingTowerType or not previewPart then
        return
    end

    local unitRay = mouse.UnitRay
    local rayResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, createRaycastParams())
    if rayResult then
        local hitPosition = rayResult.Position
        previewPart.CFrame = CFrame.new(
            Vector3.new(hitPosition.X, hitPosition.Y + previewPart.Size.Y / 2, hitPosition.Z)
        )
    end
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 and placingTowerType then
        local unitRay = mouse.UnitRay
        local rayResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, createRaycastParams())
        if rayResult and isOnBuildableGround(rayResult.Instance) then
            remotes.TowerPlaced:FireServer(placingTowerType, rayResult.Position)
            cancelPlacement()
        end
    elseif input.KeyCode == Enum.KeyCode.R then
        cancelPlacement()
    end
end)

RunService.RenderStepped:Connect(updatePreview)

