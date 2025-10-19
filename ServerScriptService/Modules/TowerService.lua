local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TowerConfigs = require(ReplicatedStorage.Modules.Config.TowerConfigs)
local SoundEffects = require(script.Parent.SoundEffects)

local TowerService = {}
TowerService.__index = TowerService

local TOWER_BASE_HALF_SIZE = 2
local DEFAULT_BASE_SIZE = Vector3.new(TOWER_BASE_HALF_SIZE * 2, 1, TOWER_BASE_HALF_SIZE * 2)
local TowerFootprints = {}

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
    local invested = towerData.Invested or 0
    towerModel:SetAttribute("SellValue", math.floor(math.max(0, invested * 0.5)))
end

function TowerService.new(mapModel, waveService, remotes)
    local self = setmetatable({}, TowerService)
    self.MapModel = mapModel
    self.WaveService = waveService
    self.Remotes = remotes
    self.Towers = {}

    if waveService and typeof(waveService) == "table" and waveService.SetTowerService then
        waveService:SetTowerService(self)
    end

    if not workspace:FindFirstChild("Towers") then
        local towersFolder = Instance.new("Folder")
        towersFolder.Name = "Towers"
        towersFolder.Parent = workspace
    end

    return self
end

local function buildTowerModel(towerType)
    local towerConfig = TowerConfigs[towerType]
    if not towerConfig then
        return nil
    end

    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    local towersFolder = assetsFolder and assetsFolder:FindFirstChild("Towers")
    local modelName = towerConfig.ModelName or towerConfig.Name or towerType
    if towersFolder and modelName then
        local template = towersFolder:FindFirstChild(modelName)
        if template and template:IsA("Model") then
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
    local stats = self.WaveService:GetPlayerStats(player)
    return stats and stats.Money >= towerConfig.Cost
end

function TowerService:ChargePlayer(player, amount)
    self.WaveService:AdjustMoney(player, -amount)
end

function TowerService:IsPlacementValid(position, towerType)
    if not position then
        return false
    end

    local candidateSize = getTowerBaseSize(towerType)
    local candidateRadius = math.max(candidateSize.X, candidateSize.Z) / 2
    if candidateRadius <= 0 then
        candidateRadius = TOWER_BASE_HALF_SIZE
    end

    local map = workspace:FindFirstChild("Map")
    local ground = map and map:FindFirstChild("PathGround")
    if ground then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.IgnoreWater = true

        local ignoreList = {}
        local towersFolderInstance = workspace:FindFirstChild("Towers")
        if towersFolderInstance then
            table.insert(ignoreList, towersFolderInstance)
        end

        params.FilterDescendantsInstances = ignoreList

        local rayOrigin = Vector3.new(position.X, position.Y + 50, position.Z)
        local rayDirection = Vector3.new(0, -200, 0)
        local result = workspace:Raycast(rayOrigin, rayDirection, params)
        if not result or (result.Instance ~= ground and not result.Instance:IsDescendantOf(ground)) then
            return false
        end
    end

    local towersFolder = workspace:FindFirstChild("Towers")
    if not towersFolder then
        return true
    end

    for _, tower in ipairs(towersFolder:GetChildren()) do
        local primary = tower.PrimaryPart or tower:FindFirstChild("Base")
        if primary then
            local otherPos = primary.Position
            local horizontalDistance = (Vector3.new(otherPos.X, 0, otherPos.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
            local otherRadius = math.max(primary.Size.X, primary.Size.Z) / 2
            local spacing = otherRadius + candidateRadius
            if horizontalDistance < spacing then
                return false
            end
        end
    end

    return true
end

function TowerService:AddTower(player, towerType, position)
    local towerConfig = TowerConfigs[towerType]
    if not towerConfig then
        return
    end

    if not self:IsPlacementValid(position, towerType) then
        return
    end

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
        Invested = towerConfig.Cost
    }

    self.Towers[towerModel] = towerData
    ensureHeadGeometry(towerData)
    updateTowerAttributes(towerModel, towerData)
    return towerModel
end

local function getFarthestEnemyInRange(towerPosition, range, enemies)
    if not range or range <= 0 then
        return nil
    end

    local farthestEnemy
    local highestProgress = -math.huge
    local fallbackDistance = -math.huge

    for enemyModel, enemyData in pairs(enemies) do
        if enemyModel and enemyModel.PrimaryPart and enemyData.Health > 0 then
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

    for towerModel, towerData in pairs(self.Towers) do
        if not towerModel.Parent then
            self:ClearTowerStun(towerModel, towerData, true)
            self.Towers[towerModel] = nil
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
                            self.WaveService.Enemies
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
    updateTowerAttributes(towerModel, towerData)

    self.Remotes.TowerUpgraded:FireClient(player, towerModel, towerData.Level)
    return true
end

function TowerService:SellTower(player, towerModel)
    local towerData = self.Towers[towerModel]
    if not towerData or towerData.Player ~= player then
        return false, "You do not own this tower"
    end

    local refund = math.floor(math.max(0, (towerData.Invested or 0) * 0.5))

    self:ClearTowerStun(towerModel, towerData, true)
    self.Towers[towerModel] = nil

    if towerModel and towerModel.Parent then
        towerModel:Destroy()
    end

    if refund > 0 then
        self.WaveService:AdjustMoney(player, refund)
    end

    return true
end

function TowerService:Reset()
    local towersFolder = workspace:FindFirstChild("Towers")
    for towerModel, towerData in pairs(self.Towers) do
        self:ClearTowerStun(towerModel, towerData, true)
        if towerModel and towerModel.Parent then
            towerModel:Destroy()
        end
        self.Towers[towerModel] = nil
    end
    if towersFolder then
        towersFolder:ClearAllChildren()
    end
    self.Towers = {}
end

return TowerService
