local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local towerConfigs = require(ReplicatedStorage.Modules.Config.TowerConfigs)

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
    MoneyChanged = getOrCreateRemote("MoneyChanged", "RemoteEvent"),
    LivesChanged = getOrCreateRemote("LivesChanged", "RemoteEvent"),
    WaveStarted = getOrCreateRemote("WaveStarted", "RemoteEvent"),
    GameEnded = getOrCreateRemote("GameEnded", "RemoteEvent"),
    RequestWaveStart = getOrCreateRemote("RequestWaveStart", "RemoteEvent"),
    TowerUpgraded = getOrCreateRemote("TowerUpgraded", "RemoteEvent"),
}

local mapModel = workspace:WaitForChild("Map")

local WaveService = require(script.Parent.Modules.WaveService)
local TowerService = require(script.Parent.Modules.TowerService)

local waveService = WaveService.new(mapModel, Remotes)
local towerService = TowerService.new(mapModel, waveService, Remotes)

Remotes.RequestWaveStart.OnServerEvent:Connect(function(player)
    if waveService.ActiveWave == 0 then
        waveService:BeginNextWave()
    end
end)

Remotes.TowerPlaced.OnServerEvent:Connect(function(player, towerType, position)
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
    towerService:UpgradeTower(player, towerModel)
end)

RunService.Heartbeat:Connect(function(dt)
    towerService:Tick(dt)
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        char:WaitForChild("HumanoidRootPart").CFrame = mapModel:WaitForChild("PlayerSpawn").CFrame + Vector3.new(0, 5, 0)
    end)
end)

