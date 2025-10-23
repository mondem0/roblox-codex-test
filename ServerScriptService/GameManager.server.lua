local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local towerConfigs = require(ReplicatedStorage.Modules.Config.TowerConfigs)
local GameConfig = require(ReplicatedStorage.Modules.Config.GameConfig)
local PathService = require(ReplicatedStorage.Modules.PathService)

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

local function getOrCreateRemote(name, className)
    local remote = remotesFolder:FindFirstChild(name)
    if not remote then
        remote = Instance.new(className)
        remote.Name = name
        remote.Parent = remotesFolder
    end
    return remote
end

local Remotes = {
    TowerPlaced = getOrCreateRemote("TowerPlaced", "RemoteEvent"),
    TowerUpgradeRequested = getOrCreateRemote("TowerUpgradeRequested", "RemoteEvent"),
    TowerSellRequested = getOrCreateRemote("TowerSellRequested", "RemoteEvent"),
    MoneyChanged = getOrCreateRemote("MoneyChanged", "RemoteEvent"),
    LivesChanged = getOrCreateRemote("LivesChanged", "RemoteEvent"),
    WaveStarted = getOrCreateRemote("WaveStarted", "RemoteEvent"),
    GameEnded = getOrCreateRemote("GameEnded", "RemoteEvent"),
    RequestWaveStart = getOrCreateRemote("RequestWaveStart", "RemoteEvent"),
    WaveSkipOfferUpdated = getOrCreateRemote("WaveSkipOfferUpdated", "RemoteEvent"),
    RequestWaveSkip = getOrCreateRemote("RequestWaveSkip", "RemoteEvent"),
    TowerUpgraded = getOrCreateRemote("TowerUpgraded", "RemoteEvent"),
    RequestRestart = getOrCreateRemote("RequestRestart", "RemoteEvent"),
    GameRestarted = getOrCreateRemote("GameRestarted", "RemoteEvent"),
    SplashFired = getOrCreateRemote("SplashFired", "RemoteEvent"),
    TowerStunPulse = getOrCreateRemote("TowerStunPulse", "RemoteEvent"),
    TowerCountsUpdated = getOrCreateRemote("TowerCountsUpdated", "RemoteEvent"),
    SubmitLoadout = getOrCreateRemote("SubmitLoadout", "RemoteEvent"),
    LobbyStateUpdated = getOrCreateRemote("LobbyStateUpdated", "RemoteEvent"),
    RequestJoinRound = getOrCreateRemote("RequestJoinRound", "RemoteEvent"),
    RequestLeaveRound = getOrCreateRemote("RequestLeaveRound", "RemoteEvent"),
    RequestReadyStatus = getOrCreateRemote("RequestReadyStatus", "RemoteEvent"),
    MapSelectionStarted = getOrCreateRemote("MapSelectionStarted", "RemoteEvent"),
    MapVoteSubmitted = getOrCreateRemote("MapVoteSubmitted", "RemoteEvent"),
    MapVoteUpdated = getOrCreateRemote("MapVoteUpdated", "RemoteEvent"),
    MapSelectionFinalized = getOrCreateRemote("MapSelectionFinalized", "RemoteEvent"),
    RoundCountdownUpdated = getOrCreateRemote("RoundCountdownUpdated", "RemoteEvent"),
    RoundSetupComplete = getOrCreateRemote("RoundSetupComplete", "RemoteEvent"),
}

local WaveService = require(script.Parent.Modules.WaveService)
local TowerService = require(script.Parent.Modules.TowerService)
local LobbyService = require(script.Parent.Modules.LobbyService)

local activeMap = workspace:FindFirstChild("Map")
if not activeMap then
    activeMap = Instance.new("Model")
    activeMap.Name = "Map"
    activeMap.Parent = workspace
end

local waveSettings
if GameConfig then
    waveSettings = {}
    if GameConfig.StartingMoney ~= nil then
        waveSettings.StartingMoney = GameConfig.StartingMoney
    end
    if not next(waveSettings) then
        waveSettings = nil
    end
end

local waveService = WaveService.new(activeMap, Remotes, waveSettings)
local towerService = TowerService.new(activeMap, waveService, Remotes)
local lobbyService = LobbyService.new(Remotes)

local activeRoundPlayers = {}
local currentCountdownTask
local COUNTDOWN_DURATION = 10

local function setActivePlayers(playersList)
    activeRoundPlayers = {}
    for _, player in ipairs(playersList) do
        activeRoundPlayers[player] = true
    end
end

local function clearActivePlayers()
    activeRoundPlayers = {}
    if waveService and waveService.SetActivePlayerCount then
        waveService:SetActivePlayerCount(1)
    end
end

local function isActivePlayer(player)
    return activeRoundPlayers[player] == true
end

local function ensureInvisiblePart(parent, name, position)
    local part = parent:FindFirstChild(name)
    if not (part and part:IsA("BasePart")) then
        part = Instance.new("Part")
        part.Name = name
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 1
        part.Size = Vector3.new(4, 1, 4)
        part.Parent = parent
    end

    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1

    return part
end

local function ensureFallbackPath(model)
    if model:FindFirstChild("Path") then
        return
    end

    local pathFolder = Instance.new("Folder")
    pathFolder.Name = "Path"
    pathFolder.Parent = model

    local startPosition = Vector3.new(0, 1000, 0)
    local endPosition = Vector3.new(0, 1000, 120)

    ensureInvisiblePart(pathFolder, "1", startPosition)
    ensureInvisiblePart(pathFolder, "2", endPosition)

    if not model:FindFirstChild("EnemySpawn") then
        ensureInvisiblePart(model, "EnemySpawn", startPosition)
    end

    if not model:FindFirstChild("Exit") then
        ensureInvisiblePart(model, "Exit", endPosition)
    end
end

local function cloneMap(option)
    local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
    local model

    if mapsFolder and option then
        if option.ModelName then
            local template = mapsFolder:FindFirstChild(option.ModelName)
            if template and template:IsA("Model") then
                model = template:Clone()
            end
        end

        if not model and option.Name then
            local fallback = mapsFolder:FindFirstChild(option.Name)
            if fallback and fallback:IsA("Model") then
                model = fallback:Clone()
            end
        end

        if not model then
            local defaultTemplate = mapsFolder:FindFirstChild("Default")
            if defaultTemplate and defaultTemplate:IsA("Model") then
                model = defaultTemplate:Clone()
            end
        end
    end

    if not model then
        model = Instance.new("Model")
        model.Name = option and (option.ModelName or option.Name) or "Map"
    end

    model.Name = "Map"
    model.Parent = workspace

    local success, err = pcall(function()
        local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        if primary then
            if model.PrimaryPart ~= primary then
                model.PrimaryPart = primary
            end
            model:PivotTo(CFrame.new(0, 1000, 0))
        else
            for _, descendant in ipairs(model:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    model.PrimaryPart = descendant
                    model:PivotTo(CFrame.new(0, 1000, 0))
                    return
                end
            end
        end
    end)

    if not success then
        model:MoveTo(Vector3.new(0, 1000, 0))
    end

    ensureFallbackPath(model)

    if not model:FindFirstChild("PlayerSpawn") then
        ensureInvisiblePart(model, "PlayerSpawn", Vector3.new(0, 1000, -12))
    end

    return model
end

local function teleportPlayersToMap(playersList, mapModel)
    local spawnPart = mapModel and mapModel:FindFirstChild("PlayerSpawn")
    local spawnCFrame = spawnPart and spawnPart.CFrame or CFrame.new(0, 1002, 0)

    for _, player in ipairs(playersList) do
        local character = player.Character
        if not character then
            character = player.CharacterAdded:Wait()
        end
        local root = character:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = spawnCFrame + Vector3.new(0, 5, 0)
        end
    end
end

local function broadcastCountdown(playersList, remaining, total)
    if not Remotes.RoundCountdownUpdated then
        return
    end

    local payload = {
        Remaining = remaining,
        Total = total,
    }

    for _, player in ipairs(playersList) do
        Remotes.RoundCountdownUpdated:FireClient(player, payload)
    end
end

local function notifyRoundSetup(playersList, option, roundKey)
    if not Remotes.RoundSetupComplete then
        return
    end

    local payload = {
        MapName = option and option.Name,
        RoundKey = roundKey,
    }

    for _, player in ipairs(playersList) do
        Remotes.RoundSetupComplete:FireClient(player, payload)
    end
end

local function cancelCountdown()
    if currentCountdownTask then
        task.cancel(currentCountdownTask)
        currentCountdownTask = nil
    end
end

if waveService.SetRoundFinishedCallback then
    waveService:SetRoundFinishedCallback(function()
        cancelCountdown()
        clearActivePlayers()
        lobbyService:RoundEnded()
    end)
end

local function beginRound(groupInfo)
    cancelCountdown()

    local participants = groupInfo.Participants or {}
    if #participants == 0 then
        lobbyService:RoundEnded()
        return
    end

    if waveService and waveService.SetActivePlayerCount then
        waveService:SetActivePlayerCount(#participants)
    end

    towerService:Reset()
    waveService:ResetGame()

    if activeMap and activeMap.Parent then
        activeMap:Destroy()
    end

    activeMap = cloneMap(groupInfo.SelectedOption)
    if type(WaveService.SetMapModel) == "function" then
        WaveService.SetMapModel(waveService, activeMap)
    elseif type(waveService.SetMapModel) == "function" then
        -- Some versions of the wave service expose SetMapModel on the instance itself.
        waveService:SetMapModel(activeMap)
    else
        waveService.MapModel = activeMap
        if PathService and type(PathService.CreatePathCache) == "function" then
            waveService.PathCache = PathService:CreatePathCache(activeMap)
        end
    end
    towerService.MapModel = activeMap

    setActivePlayers(participants)
    teleportPlayersToMap(participants, activeMap)
    notifyRoundSetup(participants, groupInfo.SelectedOption, groupInfo.RoundKey)

    local remaining = COUNTDOWN_DURATION
    broadcastCountdown(participants, remaining, COUNTDOWN_DURATION)

    currentCountdownTask = task.spawn(function()
        while remaining > 0 do
            task.wait(1)
            remaining -= 1
            broadcastCountdown(participants, remaining, COUNTDOWN_DURATION)
        end

        currentCountdownTask = nil
        broadcastCountdown(participants, 0, COUNTDOWN_DURATION)
        waveService:BeginNextWave()
    end)
end

lobbyService:SetGroupReadyCallback(function(groupInfo)
    beginRound(groupInfo)
end)

Remotes.SubmitLoadout.OnServerEvent:Connect(function(player, loadout)
    lobbyService:SetLoadout(player, loadout)
end)

Remotes.RequestJoinRound.OnServerEvent:Connect(function(player, roundKey)
    lobbyService:JoinRound(player, roundKey)
end)

Remotes.RequestLeaveRound.OnServerEvent:Connect(function(player)
    lobbyService:LeaveRound(player)
end)

Remotes.RequestReadyStatus.OnServerEvent:Connect(function(player, ready)
    lobbyService:SetReady(player, ready)
end)

Remotes.MapVoteSubmitted.OnServerEvent:Connect(function(player, optionIndex)
    lobbyService:SubmitVote(player, optionIndex)
end)

Remotes.RequestWaveStart.OnServerEvent:Connect(function() end)

Remotes.RequestWaveSkip.OnServerEvent:Connect(function(player)
    if not isActivePlayer(player) then
        return
    end

    waveService:RequestWaveSkip(player)
end)

Remotes.TowerPlaced.OnServerEvent:Connect(function(player, towerType, position)
    if not lobbyService:IsActivePlayer(player) then
        return
    end

    if not lobbyService:CanUseTower(player, towerType) then
        return
    end

    local config = towerConfigs[towerType]
    if not config then
        return
    end

    if not towerService:CanAfford(player, towerType) then
        Remotes.MoneyChanged:FireClient(player, waveService:GetPlayerStats(player).Money)
        return
    end

    local towerModel = towerService:AddTower(player, towerType, position)
    if towerModel then
        towerService:ChargePlayer(player, config.Cost)
    else
        Remotes.MoneyChanged:FireClient(player, waveService:GetPlayerStats(player).Money)
    end
end)

Remotes.TowerUpgradeRequested.OnServerEvent:Connect(function(player, towerModel)
    if not isActivePlayer(player) then
        return
    end
    towerService:UpgradeTower(player, towerModel)
end)

Remotes.TowerSellRequested.OnServerEvent:Connect(function(player, towerModel)
    if not isActivePlayer(player) then
        return
    end
    towerService:SellTower(player, towerModel)
end)

Remotes.RequestRestart.OnServerEvent:Connect(function(player)
    if waveService.IsSpawning then
        return
    end

    if next(waveService.Enemies) then
        return
    end

    cancelCountdown()
    clearActivePlayers()
    waveService:ResetGame()
    towerService:Reset()
    lobbyService:RoundEnded()
    Remotes.GameRestarted:FireAllClients()
end)

RunService.Heartbeat:Connect(function(dt)
    towerService:Tick(dt)
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        local root = character:WaitForChild("HumanoidRootPart")
        local spawnPart = activeMap and activeMap:FindFirstChild("PlayerSpawn")
        if spawnPart then
            root.CFrame = spawnPart.CFrame + Vector3.new(0, 5, 0)
        end
    end)

    lobbyService:BroadcastLobbyState()
end)

Players.PlayerRemoving:Connect(function(player)
    activeRoundPlayers[player] = nil
end)

lobbyService:BroadcastLobbyState()
