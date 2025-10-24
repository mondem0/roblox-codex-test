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
local PlacementValidation = require(ReplicatedStorage.Modules.Client.TowerPlacementValidation)
local enemiesFolder = workspace:WaitForChild("Enemies")

local placingTowerType
local previewPart
local placementValid = false
local hoverUi = {
        container = nil,
        frame = nil,
        nameLabel = nil,
        healthLabel = nil,
        combinedLabel = nil,
}
local selectionState = {
        tower = nil,
        lastRemoved = nil,
        connections = {},
}
local hudRefs = {
        screenGui = nil,
        shopFrame = nil,
        statusFrame = nil,
        moneyLabel = nil,
        livesLabel = nil,
        waveLabel = nil,
        rangeRing = nil,
        rangeRingAdornment = nil,
        previewRangeRing = nil,
        previewRangeAdornment = nil,
        preRoundCountdownLabel = nil,
}
local towerBaseTracker = {
        enabled = false,
        states = {},
        trackedFolder = nil,
        folderConnections = {},
        workspaceConnection = nil,
}

local boostDisplayTracker = {
        displays = {},
        modelConnections = {},
}

local TOWER_BASE_PLACEMENT_TRANSPARENCY = 0.7
local BOOST_DISPLAY_NAME = "TowerBoostDisplay"
local BOOST_SOURCE_NAME = "BoostSource"
local BOOSTER_TOWER_TYPE = "Booster"
local currentMoney = 0
local gameEnded = false
local lastVictoryState
local shopButtonConnections = {}
local shopSlotButtons = {}
local shopSlotOriginalText = {}
local shopSlotPriceLabels = {}
local shopSlotCountLabels = {}
local beginPlacement

local towerDetailsUi = {
        frame = nil,
        nameLabel = nil,
        levelLabel = nil,
        statsLabel = nil,
        ownershipLabel = nil,
        upgradeDescriptionLabel = nil,
        upgradeButton = nil,
        sellButton = nil,
        upgradeButtonOriginalColor = nil,
        upgradeButtonOriginalTextColor = nil,
        upgradeButtonOriginalBackgroundTransparency = nil,
        upgradeButtonOriginalTextTransparency = nil,
        upgradeButtonOriginalAutoButtonColor = nil,
        sellButtonOriginalAutoButtonColor = nil,
}
local GREY_COLOR = Color3.new(0.5, 0.5, 0.5)
local READY_COLOR = Color3.fromRGB(120, 220, 160)
local NOT_READY_COLOR = Color3.fromRGB(220, 140, 120)

local towerTotalsUi = {
        playerLabel = nil,
        teamLabel = nil,
        snapshot = nil,
}

local LOADOUT_SLOT_COUNT = 5
local SLOT_KEY_CODES = {
        [Enum.KeyCode.One] = 1,
        [Enum.KeyCode.Two] = 2,
        [Enum.KeyCode.Three] = 3,
        [Enum.KeyCode.Four] = 4,
        [Enum.KeyCode.Five] = 5,
        [Enum.KeyCode.KeypadOne] = 1,
        [Enum.KeyCode.KeypadTwo] = 2,
        [Enum.KeyCode.KeypadThree] = 3,
        [Enum.KeyCode.KeypadFour] = 4,
        [Enum.KeyCode.KeypadFive] = 5,
}

local selectionUi = {
        screenGui = nil,
        frame = nil,
        towerList = nil,
        slotButtons = {},
        slotOriginalText = {},
        activeSlot = nil,
}
local loadoutSelection = {}
local lastSyncedLoadout

local lobbyUi = {
        countdownLabel = nil,
        readyButton = nil,
        leaveButton = nil,
        roundButtons = {},
        statusLabel = nil,
        phase = "lobby",
        stateSnapshot = nil,
        readyState = false,
        roundList = nil,
        loadoutLocked = false,
}

local mapSelectionState = {
        gui = nil,
        frame = nil,
        optionButtons = {},
        voteLabels = {},
        totalPlayers = 0,
        statusLabel = nil,
        optionsContainer = nil,
}

local refreshBoostDisplayVisibility
local clearBoostDisplayTracking

local waveSkipUi = {
        button = nil,
        tween = nil,
        tweenConnection = nil,
        offerActive = false,
        requestPending = false,
        hiddenPosition = UDim2.new(0.5, 0, -0.18, 0),
        visiblePosition = UDim2.new(0.5, 0, 0.065, 0),
        showTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        hideTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}

local DEFAULT_PREVIEW_SIZE = Vector3.new(4, 1, 4)
local previewFootprintSize = DEFAULT_PREVIEW_SIZE
local footprintCache = {}
local RANGE_RING_HEIGHT = 0.05
local MAX_GROUND_RAYCAST_ATTEMPTS = 8
local PLACEMENT_EDGE_EPSILON = 0.01
local DEFAULT_PLACEMENT_SURFACE = "ground"
local CLIFF_PLACEMENT_SURFACE = "cliff"

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
        if not towerType then
                return DEFAULT_PLACEMENT_SURFACE
        end

        local config = towerConfigs[towerType]
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

local placementPartCache = {}

local function getPlacementPartSet(towerType)
        if not towerType then
                return nil
        end

        local cached = placementPartCache[towerType]
        if cached ~= nil then
                if cached == false then
                        return nil
                end

                return cached
        end

        local config = towerConfigs[towerType]
        if not config then
                placementPartCache[towerType] = false
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
                placementPartCache[towerType] = partNames
                return partNames
        end

        placementPartCache[towerType] = false
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
                if ground and (instance == ground or (instance:IsDescendantOf(ground))) then
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

local placementValidation = PlacementValidation.new({
        player = player,
        getPreviewPart = function()
                return previewPart
        end,
        getPreviewRangeRing = function()
                return hudRefs.previewRangeRing
        end,
        getRangeRing = function()
                return hudRefs.rangeRing
        end,
        getPreviewFootprintSize = function()
                return previewFootprintSize
        end,
        getPlacementSurface = getPlacementSurface,
        getPlacementPartSet = getPlacementPartSet,
        isValidPlacementSurface = isValidPlacementSurface,
        CLIFF_PLACEMENT_SURFACE = CLIFF_PLACEMENT_SURFACE,
        MAX_GROUND_RAYCAST_ATTEMPTS = MAX_GROUND_RAYCAST_ATTEMPTS,
        PLACEMENT_EDGE_EPSILON = PLACEMENT_EDGE_EPSILON,
})

local function updateStartButtonVisual()
        -- The manual wave start button is no longer present in the HUD.
        -- This placeholder keeps legacy calls harmless while the lobby
        -- workflow drives round countdowns automatically.
end

local syncLoadoutWithServer = function() end

local function formatCountLimit(count, limit)
        local numericCount = tonumber(count) or 0
        local numericLimit = tonumber(limit)

        if numericLimit and numericLimit > 0 then
                return string.format("%d / %d", numericCount, numericLimit)
        end

        return string.format("%d / ∞", numericCount)
end

local function applyScaledText(guiObject, minTextSize, maxTextSize)
        if not guiObject then
                return
        end

        local className = guiObject.ClassName
        if className ~= "TextLabel" and className ~= "TextButton" and className ~= "TextBox" then
                return
        end

        guiObject.TextScaled = true

        local constraint = guiObject:FindFirstChild("TextSizeConstraint")
        if not constraint or not constraint:IsA("UITextSizeConstraint") then
                if constraint then
                        constraint:Destroy()
                end
                constraint = Instance.new("UITextSizeConstraint")
                constraint.Name = "TextSizeConstraint"
                constraint.Parent = guiObject
        end

        constraint.MinTextSize = minTextSize or 12
        constraint.MaxTextSize = maxTextSize or 48
end

local function cancelWaveSkipTween()
        if waveSkipUi.tween then
                waveSkipUi.tween:Cancel()
                waveSkipUi.tween = nil
        end

        if waveSkipUi.tweenConnection then
                waveSkipUi.tweenConnection:Disconnect()
                waveSkipUi.tweenConnection = nil
        end
end

local function resetWaveSkipButton()
        waveSkipUi.offerActive = false
        waveSkipUi.requestPending = false

        if not waveSkipUi.button then
                return
        end

        cancelWaveSkipTween()
        waveSkipUi.button.Visible = false
        waveSkipUi.button.Active = false
        waveSkipUi.button.AutoButtonColor = true
        waveSkipUi.button.Position = waveSkipUi.hiddenPosition
        waveSkipUi.button.Text = "Skip Wave"
end

local function showWaveSkipButton(payload)
        if not waveSkipUi.button then
                return
        end

        if lobbyUi.phase ~= "inRound" then
                return
        end

        cancelWaveSkipTween()
        waveSkipUi.offerActive = true
        waveSkipUi.requestPending = false

        local label = "Skip Wave"
        if payload then
                local nextWave = payload.NextWave
                if typeof(nextWave) == "number" then
                        label = string.format("Skip to Wave %d", nextWave)
                else
                        local waveNumber = payload.Wave
                        if typeof(waveNumber) == "number" then
                                label = string.format("Skip Wave %d", waveNumber)
                        end
                end
        end

        waveSkipUi.button.Text = label
        waveSkipUi.button.AutoButtonColor = true
        waveSkipUi.button.Active = true
        waveSkipUi.button.Visible = true
        waveSkipUi.button.Position = waveSkipUi.hiddenPosition

        waveSkipUi.tween = TweenService:Create(waveSkipUi.button, waveSkipUi.showTweenInfo, {
                Position = waveSkipUi.visiblePosition,
        })
        waveSkipUi.tween:Play()
end

local function hideWaveSkipButton(payload)
        waveSkipUi.offerActive = false
        waveSkipUi.requestPending = false

        if not waveSkipUi.button then
                return
        end

        if not waveSkipUi.button.Visible then
                resetWaveSkipButton()
                return
        end

        cancelWaveSkipTween()
        waveSkipUi.button.Active = false
        waveSkipUi.button.AutoButtonColor = false

        if payload and payload.Skipped then
                waveSkipUi.button.Text = "Skipping..."
        elseif payload and payload.Reason == "completed" then
                waveSkipUi.button.Text = "Wave Cleared"
        elseif payload and payload.Reason == "victory" then
                waveSkipUi.button.Text = "Round Complete"
        elseif payload and payload.Reason == "gameOver" then
                waveSkipUi.button.Text = "Defeat"
        elseif payload and payload.Reason == "advance" then
                waveSkipUi.button.Text = "Preparing..."
        else
                waveSkipUi.button.Text = "Skip Unavailable"
        end

        waveSkipUi.tween = TweenService:Create(waveSkipUi.button, waveSkipUi.hideTweenInfo, {
                Position = waveSkipUi.hiddenPosition,
        })

        waveSkipUi.tweenConnection = waveSkipUi.tween.Completed:Connect(function()
                if waveSkipUi.tweenConnection then
                        waveSkipUi.tweenConnection:Disconnect()
                        waveSkipUi.tweenConnection = nil
                end
                waveSkipUi.tween = nil
                waveSkipUi.button.Visible = false
                waveSkipUi.button.AutoButtonColor = true
                waveSkipUi.button.Text = "Skip Wave"
                waveSkipUi.button.Position = waveSkipUi.hiddenPosition
        end)

        waveSkipUi.tween:Play()
end

local function getTowerCountEntry(towerType)
        if not towerType then
                return nil
        end

        if not towerTotalsUi.snapshot or typeof(towerTotalsUi.snapshot) ~= "table" then
                return nil
        end

        local towers = towerTotalsUi.snapshot.Towers
        if not towers or typeof(towers) ~= "table" then
                return nil
        end

        return towers[towerType]
end

local function updateOverallTowerTotals()
        if not (towerTotalsUi.playerLabel or towerTotalsUi.teamLabel) then
                return
        end

        local totalInfo = towerTotalsUi.snapshot and towerTotalsUi.snapshot.Total

        local playerText = formatCountLimit(totalInfo and totalInfo.PlayerCount, totalInfo and totalInfo.PlayerLimit)
        if towerTotalsUi.playerLabel then
                towerTotalsUi.playerLabel.Text = string.format("Your Towers: %s", playerText)
        end

        if towerTotalsUi.teamLabel then
                local teamText = formatCountLimit(totalInfo and totalInfo.GlobalCount, totalInfo and totalInfo.GlobalLimit)
                towerTotalsUi.teamLabel.Text = string.format("Team Towers: %s", teamText)
        end
end

local function updateShopSlotCountDisplay(slotIndex)
        local label = shopSlotCountLabels[slotIndex]
        if not label then
                return
        end

        local towerType = loadoutSelection[slotIndex]
        if not (towerType and towerConfigs[towerType]) then
                label.Text = ""
                label.Visible = false
                return
        end

        local entry = getTowerCountEntry(towerType)
        local playerCount = entry and entry.PlayerCount
        local playerLimit = entry and entry.PlayerLimit
        local globalCount = entry and entry.GlobalCount
        local globalLimit = entry and entry.GlobalLimit

        local lines = {
                string.format("You: %s", formatCountLimit(playerCount, playerLimit)),
                string.format("Team: %s", formatCountLimit(globalCount, globalLimit)),
        }

        label.Text = table.concat(lines, "\n")
        label.Visible = true
end

local function updateAllShopSlotCounts()
        for slotIndex = 1, LOADOUT_SLOT_COUNT do
                updateShopSlotCountDisplay(slotIndex)
        end
end

local function disconnectSelectedConnections()
        for _, conn in ipairs(selectionState.connections) do
                conn:Disconnect()
        end
        selectionState.connections = {}
end

local function destroyRangeIndicator()
	if hudRefs.rangeRing then
		hudRefs.rangeRing:Destroy()
		hudRefs.rangeRing = nil
		hudRefs.rangeRingAdornment = nil
	end
end

local function destroyPreviewRangeIndicator()
	if hudRefs.previewRangeRing then
		hudRefs.previewRangeRing:Destroy()
		hudRefs.previewRangeRing = nil
		hudRefs.previewRangeAdornment = nil
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

local function disconnectTowerFolderConnections()
        for index, connection in ipairs(towerBaseTracker.folderConnections) do
                if connection and connection.Disconnect then
                        connection:Disconnect()
                end
                towerBaseTracker.folderConnections[index] = nil
        end

        clearBoostDisplayTracking()
end

local function cleanupTowerBaseState(basePart)
        local state = towerBaseTracker.states[basePart]
        if not state then
                return
        end

        if basePart and basePart.Parent then
                if state.OriginalTransparency ~= nil then
                        basePart.Transparency = state.OriginalTransparency
                end

                if state.OriginalLocalTransparency ~= nil then
                        basePart.LocalTransparencyModifier = state.OriginalLocalTransparency
                end
        end

        if state.Connection then
                state.Connection:Disconnect()
        end

        towerBaseTracker.states[basePart] = nil
end

local function disconnectBoostDisplay(display)
        local connections = boostDisplayTracker.displays[display]
        if not connections then
                return
        end

        for index, connection in ipairs(connections) do
                if connection and connection.Disconnect then
                        connection:Disconnect()
                end
                connections[index] = nil
        end

        boostDisplayTracker.displays[display] = nil
end

local function disconnectModelBoostConnections(model)
        local connections = boostDisplayTracker.modelConnections[model]
        if not connections then
                return
        end

        for index, connection in ipairs(connections) do
                if connection and connection.Disconnect then
                        connection:Disconnect()
                end
                connections[index] = nil
        end

        boostDisplayTracker.modelConnections[model] = nil
end

local function applyBoostDisplayVisibility(display)
        if not (display and display:IsA("BillboardGui")) then
                return
        end

        local boosterModel
        local selectedTower = selectionState.tower
        if selectedTower and selectedTower.Parent then
                local towerType = selectedTower:GetAttribute("TowerType")
                if towerType == BOOSTER_TOWER_TYPE then
                        boosterModel = selectedTower
                end
        end

        local shouldShow = false
        if boosterModel then
                local sourceValue = display:FindFirstChild(BOOST_SOURCE_NAME)
                if sourceValue and sourceValue:IsA("ObjectValue") and sourceValue.Value == boosterModel then
                        shouldShow = true
                end
        end

        display.Enabled = shouldShow
end

refreshBoostDisplayVisibility = function()
        for display in pairs(boostDisplayTracker.displays) do
                if display and display.Parent then
                        applyBoostDisplayVisibility(display)
                end
        end
end

clearBoostDisplayTracking = function()
        local trackedDisplays = {}
        for display in pairs(boostDisplayTracker.displays) do
                table.insert(trackedDisplays, display)
        end

        for _, display in ipairs(trackedDisplays) do
                disconnectBoostDisplay(display)
        end

        for model in pairs(boostDisplayTracker.modelConnections) do
                disconnectModelBoostConnections(model)
        end
end

local function trackBoostDisplay(display)
        if not (display and display:IsA("BillboardGui") and display.Name == BOOST_DISPLAY_NAME) then
                return
        end

        if boostDisplayTracker.displays[display] then
                applyBoostDisplayVisibility(display)
                return
        end

        local connections = {}

        local function updateVisibility()
                applyBoostDisplayVisibility(display)
        end

        table.insert(connections, display.AncestryChanged:Connect(function(_, parent)
                if not parent then
                        disconnectBoostDisplay(display)
                        return
                end

                updateVisibility()
        end))

        table.insert(connections, display.ChildAdded:Connect(function(child)
                if child and child:IsA("ObjectValue") and child.Name == BOOST_SOURCE_NAME then
                        table.insert(connections, child:GetPropertyChangedSignal("Value"):Connect(updateVisibility))
                        updateVisibility()
                end
        end))

        local sourceValue = display:FindFirstChild(BOOST_SOURCE_NAME)
        if sourceValue and sourceValue:IsA("ObjectValue") then
                table.insert(connections, sourceValue:GetPropertyChangedSignal("Value"):Connect(updateVisibility))
        end

        boostDisplayTracker.displays[display] = connections
        updateVisibility()
end

local function monitorTowerModelForBoostDisplays(model)
        if not (model and model:IsA("Model")) then
                return
        end

        if boostDisplayTracker.modelConnections[model] then
                return
        end

        local connections = {}

        local function onChildAdded(child)
                if child and child:IsA("BillboardGui") and child.Name == BOOST_DISPLAY_NAME then
                        trackBoostDisplay(child)
                end
        end

        table.insert(connections, model.ChildAdded:Connect(onChildAdded))
        table.insert(connections, model.AncestryChanged:Connect(function(_, parent)
                if not parent then
                        disconnectModelBoostConnections(model)
                end
        end))

        boostDisplayTracker.modelConnections[model] = connections

        for _, child in ipairs(model:GetChildren()) do
                onChildAdded(child)
        end
end

local function getTowerBasePart(towerModel)
        if not (towerModel and towerModel:IsA("Model")) then
                return nil
        end

        local basePart = towerModel.PrimaryPart
        if basePart and basePart:IsA("BasePart") then
                return basePart
        end

        basePart = towerModel:FindFirstChild("Base")
        if basePart and basePart:IsA("BasePart") then
                return basePart
        end

        return towerModel:FindFirstChildWhichIsA("BasePart")
end

local function ensureBaseState(basePart)
        if not (basePart and basePart:IsA("BasePart")) then
                return nil
        end

        local state = towerBaseTracker.states[basePart]
        if state then
                return state
        end

        local originalTransparency = basePart.Transparency or 0
        local originalLocalTransparency = basePart.LocalTransparencyModifier or 0

        state = {
                OriginalTransparency = originalTransparency,
                OriginalLocalTransparency = originalLocalTransparency,
                HiddenLocalTransparency = math.clamp(1 - originalTransparency, 0, 1),
        }

        state.Connection = basePart.AncestryChanged:Connect(function(_, parent)
                if parent then
                        return
                end

                cleanupTowerBaseState(basePart)
        end)

        towerBaseTracker.states[basePart] = state
        return state
end

local function applyBaseVisibilityToPart(basePart)
        local state = ensureBaseState(basePart)
        if not state then
                return
        end

        if towerBaseTracker.enabled then
                basePart.Transparency = TOWER_BASE_PLACEMENT_TRANSPARENCY
                basePart.LocalTransparencyModifier = 0
        else
                if state.OriginalTransparency ~= nil then
                        basePart.Transparency = state.OriginalTransparency
                end

                local hiddenModifier = state.HiddenLocalTransparency or 1
                basePart.LocalTransparencyModifier = hiddenModifier
        end
end

local function updateTowerBaseVisibilityForModel(towerModel)
        local basePart = getTowerBasePart(towerModel)
        if basePart then
                applyBaseVisibilityToPart(basePart)
        end
end

local function updateAllTowerBaseVisibility()
        local towersFolder = towerBaseTracker.trackedFolder or workspace:FindFirstChild("Towers")
        if not towersFolder then
                return
        end

        for _, child in ipairs(towersFolder:GetChildren()) do
                if child:IsA("Model") then
                        updateTowerBaseVisibilityForModel(child)
                end
        end
end

local function setTowerBaseVisibility(visible)
        towerBaseTracker.enabled = visible and true or false
        updateAllTowerBaseVisibility()
end

local function onTowerChildAdded(child)
        if not (child and child:IsA("Model")) then
                return
        end

        monitorTowerModelForBoostDisplays(child)

        task.defer(function()
                if child.Parent then
                        updateTowerBaseVisibilityForModel(child)
                        refreshBoostDisplayVisibility()
                end
        end)
end

local function attachToTowersFolder(folder)
        if towerBaseTracker.trackedFolder == folder then
                return
        end

        disconnectTowerFolderConnections()
        towerBaseTracker.trackedFolder = folder

        if not folder then
                return
        end

        for _, child in ipairs(folder:GetChildren()) do
                onTowerChildAdded(child)
        end

        table.insert(towerBaseTracker.folderConnections, folder.ChildAdded:Connect(onTowerChildAdded))
        table.insert(towerBaseTracker.folderConnections, folder.AncestryChanged:Connect(function(_, parent)
                if parent then
                        return
                end

                attachToTowersFolder(nil)
        end))

        updateAllTowerBaseVisibility()
        refreshBoostDisplayVisibility()
end

local function initializeTowerBaseTracking()
        attachToTowersFolder(workspace:FindFirstChild("Towers"))

        if not towerBaseTracker.workspaceConnection then
                towerBaseTracker.workspaceConnection = workspace.ChildAdded:Connect(function(child)
                        if child and child:IsA("Folder") and child.Name == "Towers" then
                                attachToTowersFolder(child)
                        end
                end)
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

local function cancelPlacement(skipBaseVisibilityReset)
	placingTowerType = nil
	if previewPart then
		previewPart:Destroy()
		previewPart = nil
	end
	destroyPreviewRangeIndicator()
	placementValid = false
	previewFootprintSize = DEFAULT_PREVIEW_SIZE

	if not skipBaseVisibilityReset then
		setTowerBaseVisibility(false)
	end
end
function beginPlacement(towerType)
	if not towerType or not towerConfigs[towerType] then
		return
	end

	cancelPlacement(true)
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
	previewPart.Size = previewFootprintSize

	local config = towerConfigs[placingTowerType]
	if config and config.Range then
		if not hudRefs.previewRangeRing then
			hudRefs.previewRangeRing, hudRefs.previewRangeAdornment = createRangeRing("PlacementRange", Color3.fromRGB(120, 220, 255), 0.55)
		end
		if hudRefs.previewRangeAdornment then
			hudRefs.previewRangeAdornment.Color3 = Color3.fromRGB(120, 220, 255)
			hudRefs.previewRangeAdornment.Transparency = 0.55
		end
	else
		destroyPreviewRangeIndicator()
	end

        placementValid = false
        selectionState.tower = nil
        disconnectSelectedConnections()
	destroyRangeIndicator()
	if towerDetailsUi.frame then
		towerDetailsUi.frame.Visible = false
	end
	if towerDetailsUi.upgradeDescriptionLabel then
		towerDetailsUi.upgradeDescriptionLabel.Text = ""
	end

	setTowerBaseVisibility(true)
end

local function createRaycastParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true

	local ignoreList = { player.Character }
	if previewPart then
		table.insert(ignoreList, previewPart)
	end
	if hudRefs.previewRangeRing then
		table.insert(ignoreList, hudRefs.previewRangeRing)
	end
	if hudRefs.rangeRing then
		table.insert(ignoreList, hudRefs.rangeRing)
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
	if not button or not button:IsA("GuiButton") then
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
	if button:IsA("TextButton") and button:GetAttribute("AutoText") ~= false then
		button.Text = config.Name or towerType
	end

	shopButtonConnections[button] = button.Activated:Connect(function()
		beginPlacement(towerType)
	end)

	button.AncestryChanged:Connect(function(_, parent)
		if not parent then
			disconnectShopButton(button)
		end
	end)
end

local function resolveSlotIndex(button)
	if not (button and button:IsA("GuiObject")) then
		return nil
	end

	local slotIndex = button:GetAttribute("SlotIndex")
	if typeof(slotIndex) == "number" then
		slotIndex = math.floor(slotIndex + 0.5)
		if slotIndex >= 1 then
			return slotIndex
		end
	end

	if typeof(slotIndex) == "string" then
		local numeric = tonumber(slotIndex)
		if numeric then
			return math.floor(numeric + 0.5)
		end
	end

	local match = string.match(button.Name, "Slot(%d+)")
	if match then
		return tonumber(match)
	end

	return nil
end

local function hasAnySelectedTowers()
        for i = 1, LOADOUT_SLOT_COUNT do
                if loadoutSelection[i] then
                        return true
                end
        end

        return false
end

local function applyLoadoutLockState()
        for _, button in pairs(selectionUi.slotButtons) do
                if button and button:IsA("GuiButton") then
                        button.AutoButtonColor = not lobbyUi.loadoutLocked
                end
        end

        if selectionUi.towerList then
                if selectionUi.towerList:IsA("ScrollingFrame") then
                        selectionUi.towerList.Active = not lobbyUi.loadoutLocked
                        selectionUi.towerList.ScrollingEnabled = not lobbyUi.loadoutLocked
                end

                for _, child in ipairs(selectionUi.towerList:GetChildren()) do
                        if child:IsA("GuiButton") then
                                child.Active = not lobbyUi.loadoutLocked
                                child.AutoButtonColor = not lobbyUi.loadoutLocked
                        end
                end
        end
end

local function setLoadoutLocked(locked)
        locked = locked and true or false

        lobbyUi.loadoutLocked = locked
        applyLoadoutLockState()
end

local function updateConfirmButtonState()
        syncLoadoutWithServer()

        local ready = hasAnySelectedTowers()

        if lobbyUi.readyButton then
                lobbyUi.readyButton.Active = ready
                lobbyUi.readyButton.AutoButtonColor = ready
                lobbyUi.readyButton.TextTransparency = ready and 0 or 0.35
        end

        if lobbyUi.statusLabel then
                if lobbyUi.loadoutLocked then
                        lobbyUi.statusLabel.Text = "Loadout locked while you are joined to a round."
                elseif ready then
                        lobbyUi.statusLabel.Text = ""
                else
                        lobbyUi.statusLabel.Text = "Select at least one tower to join a round."
                end
        end
end

local function updateSelectionSlotDisplay(slotIndex)
	local button = selectionUi.slotButtons[slotIndex]
	if not button then
		return
	end

	local towerType = loadoutSelection[slotIndex]
	if towerType and towerConfigs[towerType] then
		button:SetAttribute("TowerType", towerType)
		if button:IsA("TextButton") and button:GetAttribute("AutoText") ~= false then
			local config = towerConfigs[towerType]
			button.Text = config.Name or towerType
		end
	else
		button:SetAttribute("TowerType", nil)
		if button:IsA("TextButton") and button:GetAttribute("AutoText") ~= false then
			button.Text = selectionUi.slotOriginalText[slotIndex] or "Empty Slot"
		end
	end

	button:SetAttribute("ActiveSlot", selectionUi.activeSlot == slotIndex)
end

local function setActiveSelectionSlot(slotIndex)
	if selectionUi.activeSlot == slotIndex then
		return
	end

	selectionUi.activeSlot = slotIndex

	for index in pairs(selectionUi.slotButtons) do
		updateSelectionSlotDisplay(index)
	end
end

local function findFirstEmptySlot()
    for i = 1, LOADOUT_SLOT_COUNT do
        if not loadoutSelection[i] then
            return i
        end
    end
    return nil
end

local function buildLoadoutPayload()
    local payload = {}
    for i = 1, LOADOUT_SLOT_COUNT do
        local towerType = loadoutSelection[i]
        if towerType and towerConfigs[towerType] then
            table.insert(payload, towerType)
        end
    end
    return payload
end

local function payloadsMatch(a, b)
    if a == b then
        return true
    end
    if not a or not b then
        return false
    end
    if #a ~= #b then
        return false
    end
    for index = 1, #a do
        if a[index] ~= b[index] then
            return false
        end
    end
    return true
end

syncLoadoutWithServer = function()
    if not remotes.SubmitLoadout then
        return
    end

    local payload = buildLoadoutPayload()
    if payloadsMatch(payload, lastSyncedLoadout) then
        return
    end

    lastSyncedLoadout = payload
    remotes.SubmitLoadout:FireServer(payload)
end

local function assignTowerToSlot(slotIndex, towerType)
    if lobbyUi.loadoutLocked then
        return
    end

    if not (slotIndex and towerType and towerConfigs[towerType]) then
        return
    end

    -- Prevent duplicate towers in the loadout by clearing any other slot that already
    -- contains the requested tower before assigning it to the active slot.
    for i = 1, LOADOUT_SLOT_COUNT do
        if i ~= slotIndex and loadoutSelection[i] == towerType then
            loadoutSelection[i] = nil
            updateSelectionSlotDisplay(i)
        end
    end

    loadoutSelection[slotIndex] = towerType
    updateSelectionSlotDisplay(slotIndex)

    local nextEmpty = findFirstEmptySlot()
    if nextEmpty then
        setActiveSelectionSlot(nextEmpty)
    end

    updateConfirmButtonState()
end

local function clearSlot(slotIndex)
    if lobbyUi.loadoutLocked then
        return
    end

    if not slotIndex then
        return
    end

    loadoutSelection[slotIndex] = nil
    updateSelectionSlotDisplay(slotIndex)
    setActiveSelectionSlot(slotIndex)
    updateConfirmButtonState()
end

local function applyLoadoutToShop()
        for slotIndex = 1, LOADOUT_SLOT_COUNT do
                local button = shopSlotButtons[slotIndex]
                if button and button:IsA("GuiButton") then
                        local towerType = loadoutSelection[slotIndex]
                        local priceLabel = shopSlotPriceLabels[slotIndex]
                        local countLabel = shopSlotCountLabels[slotIndex]
                        if countLabel then
                                countLabel.Text = ""
                                countLabel.Visible = false
                        end
                        if towerType and towerConfigs[towerType] then
                                disconnectShopButton(button)
                                button:SetAttribute("TowerType", towerType)
                                local config = towerConfigs[towerType]
                                if button:IsA("TextButton") and button:GetAttribute("AutoText") ~= false then
					button.Text = config.Name or towerType
				end
				if priceLabel and priceLabel:IsA("TextLabel") then
					priceLabel.Text = string.format("$%d", config.Cost or 0)
					priceLabel.Visible = true
				end
				button.Active = true
				button.Visible = true
				connectShopButton(button)
			else
				disconnectShopButton(button)
				button:SetAttribute("TowerType", nil)
				if button:IsA("TextButton") and button:GetAttribute("AutoText") ~= false then
					local defaultText = shopSlotOriginalText[slotIndex]
					if defaultText then
						button.Text = defaultText
					end
				end
				if priceLabel and priceLabel:IsA("TextLabel") then
					priceLabel.Text = ""
					priceLabel.Visible = false
                                end
                                button.Active = false
                        end
                end
        end

        updateAllShopSlotCounts()
end

local function populateTowerSelectionButtons()
        if not selectionUi.towerList then
                return
        end

        for _, child in ipairs(selectionUi.towerList:GetChildren()) do
                if child:GetAttribute("TowerClientGenerated") then
                        child:Destroy()
                end
        end

        local keys = {}
        for towerType, config in pairs(towerConfigs) do
                if typeof(config) == "table" and config.Cost then
                        table.insert(keys, towerType)
                end
        end

        table.sort(keys, function(a, b)
                local configA = towerConfigs[a]
                local configB = towerConfigs[b]
                local costA = configA and configA.Cost or math.huge
                local costB = configB and configB.Cost or math.huge
                if costA ~= costB then
                        return costA < costB
                end
                local nameA = configA and configA.Name or a
                local nameB = configB and configB.Name or b
                return tostring(nameA) < tostring(nameB)
        end)

        for _, towerType in ipairs(keys) do
                local config = towerConfigs[towerType]
                if typeof(config) == "table" and config.Cost then
                        local button = Instance.new("TextButton")
                        button.Name = string.format("%sSelectButton", towerType)
                        button.Size = UDim2.new(1, 0, 1, 0)
                        button.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
                        button.BorderSizePixel = 0
                        button.TextColor3 = Color3.new(1, 1, 1)
                        button.Font = Enum.Font.Gotham
                        button.TextSize = 18
                        button.AutoButtonColor = true
                        button.TextWrapped = true
                        button.LayoutOrder = config.Cost or 0
                        button.Parent = selectionUi.towerList
                        button:SetAttribute("TowerType", towerType)
                        button:SetAttribute("TowerClientGenerated", true)
                        local cost = tonumber(config.Cost) or 0
                        local displayName = config.Name or towerType
                        button.Text = string.format("%s\n$%d", displayName, cost)
                        applyScaledText(button, 12, 32)

                        button.MouseButton1Click:Connect(function()
                                local slotIndex = selectionUi.activeSlot or findFirstEmptySlot() or 1
                                assignTowerToSlot(slotIndex, towerType)
                        end)
                end
        end

        local layout = selectionUi.towerList:FindFirstChildWhichIsA("UIGridLayout")
        if layout then
                layout.CellSize = UDim2.new(0.48, 0, 0.22, 0)
        end

        applyLoadoutLockState()
end

local function createSelectionGui()
        if selectionUi.screenGui then
                return selectionUi.screenGui
        end

        selectionUi.screenGui = Instance.new("ScreenGui")
        selectionUi.screenGui.Name = "TowerLobbyUI"
        selectionUi.screenGui.ResetOnSpawn = false
        selectionUi.screenGui.IgnoreGuiInset = true
        selectionUi.screenGui.DisplayOrder = 5
        selectionUi.screenGui.Enabled = true
        selectionUi.screenGui.Parent = playerGui

        selectionUi.frame = Instance.new("Frame")
        selectionUi.frame.Name = "LobbyFrame"
        selectionUi.frame.AnchorPoint = Vector2.new(0.5, 0.5)
        selectionUi.frame.Size = UDim2.fromScale(0.9, 0.85)
        selectionUi.frame.Position = UDim2.fromScale(0.5, 0.5)
        selectionUi.frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        selectionUi.frame.BackgroundTransparency = 0.15
        selectionUi.frame.BorderSizePixel = 0
        selectionUi.frame.Parent = selectionUi.screenGui

        local frameCorner = Instance.new("UICorner")
        frameCorner.CornerRadius = UDim.new(0.03, 0)
        frameCorner.Parent = selectionUi.frame

        local frameConstraint = Instance.new("UIAspectRatioConstraint")
        frameConstraint.AspectRatio = 1140 / 520
        frameConstraint.DominantAxis = Enum.DominantAxis.Width
        frameConstraint.Parent = selectionUi.frame

        local frameSizeConstraint = Instance.new("UISizeConstraint")
        frameSizeConstraint.MinSize = Vector2.new(720, 420)
        frameSizeConstraint.Parent = selectionUi.frame

        local shopPanel = Instance.new("Frame")
        shopPanel.Name = "TowerShopPanel"
        shopPanel.AnchorPoint = Vector2.new(0, 0.5)
        shopPanel.Size = UDim2.new(0.6, 0, 0.78, 0)
        shopPanel.Position = UDim2.new(0.03, 0, 0.5, 0)
        shopPanel.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
        shopPanel.BackgroundTransparency = 0.05
        shopPanel.BorderSizePixel = 0
        shopPanel.Parent = selectionUi.frame

        local shopCorner = Instance.new("UICorner")
        shopCorner.CornerRadius = UDim.new(0.03, 0)
        shopCorner.Parent = shopPanel

        local shopTitle = Instance.new("TextLabel")
        shopTitle.Name = "ShopTitle"
        shopTitle.AnchorPoint = Vector2.new(0, 0)
        shopTitle.Size = UDim2.new(0.94, 0, 0.12, 0)
        shopTitle.Position = UDim2.new(0.03, 0, 0.03, 0)
        shopTitle.BackgroundTransparency = 1
        shopTitle.Font = Enum.Font.GothamBold
        shopTitle.TextSize = 26
        shopTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        shopTitle.TextXAlignment = Enum.TextXAlignment.Left
        shopTitle.Text = "Tower Shop"
        shopTitle.Parent = shopPanel
        applyScaledText(shopTitle, 16, 42)

        selectionUi.towerList = Instance.new("ScrollingFrame")
        selectionUi.towerList.Name = "TowerList"
        selectionUi.towerList.BackgroundTransparency = 1
        selectionUi.towerList.BorderSizePixel = 0
        selectionUi.towerList.AnchorPoint = Vector2.new(0, 0)
        selectionUi.towerList.Size = UDim2.new(0.94, 0, 0.76, 0)
        selectionUi.towerList.Position = UDim2.new(0.03, 0, 0.18, 0)
        selectionUi.towerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        selectionUi.towerList.ScrollBarThickness = 8
        selectionUi.towerList.Parent = shopPanel

        local shopGrid = Instance.new("UIGridLayout")
        shopGrid.CellSize = UDim2.new(0.48, 0, 0.22, 0)
        shopGrid.CellPadding = UDim2.new(0.04, 0, 0.04, 0)
        shopGrid.FillDirection = Enum.FillDirection.Horizontal
        shopGrid.SortOrder = Enum.SortOrder.LayoutOrder
        shopGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
        shopGrid.Parent = selectionUi.towerList

        lobbyUi.statusLabel = Instance.new("TextLabel")
        lobbyUi.statusLabel.Name = "LobbyStatus"
        lobbyUi.statusLabel.AnchorPoint = Vector2.new(0, 1)
        lobbyUi.statusLabel.Size = UDim2.new(0.94, 0, 0.1, 0)
        lobbyUi.statusLabel.Position = UDim2.new(0.03, 0, 0.97, 0)
        lobbyUi.statusLabel.BackgroundTransparency = 1
        lobbyUi.statusLabel.Font = Enum.Font.Gotham
        lobbyUi.statusLabel.TextSize = 18
        lobbyUi.statusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        lobbyUi.statusLabel.TextXAlignment = Enum.TextXAlignment.Left
        lobbyUi.statusLabel.Text = ""
        lobbyUi.statusLabel.Parent = shopPanel
        applyScaledText(lobbyUi.statusLabel, 14, 30)

        local roundPanel = Instance.new("Frame")
        roundPanel.Name = "RoundPanel"
        roundPanel.AnchorPoint = Vector2.new(1, 0)
        roundPanel.Size = UDim2.new(0.34, 0, 0.55, 0)
        roundPanel.Position = UDim2.new(0.99, 0, 0.05, 0)
        roundPanel.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
        roundPanel.BackgroundTransparency = 0.05
        roundPanel.BorderSizePixel = 0
        roundPanel.Parent = selectionUi.frame

        local roundCorner = Instance.new("UICorner")
        roundCorner.CornerRadius = UDim.new(0.04, 0)
        roundCorner.Parent = roundPanel

        local roundTitle = Instance.new("TextLabel")
        roundTitle.Name = "RoundTitle"
        roundTitle.AnchorPoint = Vector2.new(0, 0)
        roundTitle.Size = UDim2.new(0.94, 0, 0.16, 0)
        roundTitle.Position = UDim2.new(0.03, 0, 0.05, 0)
        roundTitle.BackgroundTransparency = 1
        roundTitle.Font = Enum.Font.GothamBold
        roundTitle.TextSize = 22
        roundTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        roundTitle.TextXAlignment = Enum.TextXAlignment.Left
        roundTitle.Text = "Select Round Type"
        roundTitle.Parent = roundPanel
        applyScaledText(roundTitle, 16, 38)

        lobbyUi.countdownLabel = Instance.new("TextLabel")
        lobbyUi.countdownLabel.Name = "CountdownLabel"
        lobbyUi.countdownLabel.AnchorPoint = Vector2.new(0, 0)
        lobbyUi.countdownLabel.Size = UDim2.new(0.94, 0, 0.12, 0)
        lobbyUi.countdownLabel.Position = UDim2.new(0.03, 0, 0.24, 0)
        lobbyUi.countdownLabel.BackgroundTransparency = 1
        lobbyUi.countdownLabel.Font = Enum.Font.Gotham
        lobbyUi.countdownLabel.TextSize = 18
        lobbyUi.countdownLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
        lobbyUi.countdownLabel.TextXAlignment = Enum.TextXAlignment.Left
        lobbyUi.countdownLabel.TextYAlignment = Enum.TextYAlignment.Center
        lobbyUi.countdownLabel.Text = ""
        lobbyUi.countdownLabel.Parent = roundPanel
        applyScaledText(lobbyUi.countdownLabel, 14, 32)

        lobbyUi.roundList = Instance.new("ScrollingFrame")
        lobbyUi.roundList.Name = "RoundList"
        lobbyUi.roundList.AnchorPoint = Vector2.new(0, 0)
        lobbyUi.roundList.Size = UDim2.new(0.94, 0, 0.6, 0)
        lobbyUi.roundList.Position = UDim2.new(0.03, 0, 0.36, 0)
        lobbyUi.roundList.BackgroundTransparency = 1
        lobbyUi.roundList.BorderSizePixel = 0
        lobbyUi.roundList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        lobbyUi.roundList.ScrollBarThickness = 8
        lobbyUi.roundList.ScrollingDirection = Enum.ScrollingDirection.Y
        lobbyUi.roundList.Parent = roundPanel

        local roundLayout = Instance.new("UIListLayout")
        roundLayout.FillDirection = Enum.FillDirection.Vertical
        roundLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        roundLayout.VerticalAlignment = Enum.VerticalAlignment.Top
        roundLayout.SortOrder = Enum.SortOrder.LayoutOrder
        roundLayout.Padding = UDim.new(0.02, 0)
        roundLayout.Parent = lobbyUi.roundList

        local loadoutPanel = Instance.new("Frame")
        loadoutPanel.Name = "LoadoutPanel"
        loadoutPanel.AnchorPoint = Vector2.new(1, 0.5)
        loadoutPanel.Size = UDim2.new(0.34, 0, 0.3, 0)
        loadoutPanel.Position = UDim2.new(0.99, 0, 0.82, 0)
        loadoutPanel.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
        loadoutPanel.BackgroundTransparency = 0.05
        loadoutPanel.BorderSizePixel = 0
        loadoutPanel.Parent = selectionUi.frame

        local loadoutCorner = Instance.new("UICorner")
        loadoutCorner.CornerRadius = UDim.new(0.04, 0)
        loadoutCorner.Parent = loadoutPanel

        local loadoutTitle = Instance.new("TextLabel")
        loadoutTitle.Name = "LoadoutTitle"
        loadoutTitle.AnchorPoint = Vector2.new(0, 0)
        loadoutTitle.Size = UDim2.new(0.94, 0, 0.22, 0)
        loadoutTitle.Position = UDim2.new(0.03, 0, 0.05, 0)
        loadoutTitle.BackgroundTransparency = 1
        loadoutTitle.Font = Enum.Font.GothamBold
        loadoutTitle.TextSize = 20
        loadoutTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        loadoutTitle.TextXAlignment = Enum.TextXAlignment.Left
        loadoutTitle.Text = string.format("Your Towers (%d slots)", LOADOUT_SLOT_COUNT)
        loadoutTitle.Parent = loadoutPanel
        applyScaledText(loadoutTitle, 16, 36)

        local slotsFrame = Instance.new("Frame")
        slotsFrame.Name = "SlotsFrame"
        slotsFrame.AnchorPoint = Vector2.new(0, 0)
        slotsFrame.Size = UDim2.new(0.94, 0, 0.36, 0)
        slotsFrame.Position = UDim2.new(0.03, 0, 0.32, 0)
        slotsFrame.BackgroundTransparency = 1
        slotsFrame.Parent = loadoutPanel

        local slotsLayout = Instance.new("UIListLayout")
        slotsLayout.FillDirection = Enum.FillDirection.Horizontal
        slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        slotsLayout.Padding = UDim.new(0.02, 0)
        slotsLayout.Parent = slotsFrame

        selectionUi.slotButtons = {}
        selectionUi.slotOriginalText = {}
        for i = 1, LOADOUT_SLOT_COUNT do
                local button = Instance.new("TextButton")
                button.Name = string.format("Slot%d", i)
                button.Size = UDim2.new(0.16, 0, 1, 0)
                button.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
                button.BorderSizePixel = 0
                button.AutoButtonColor = true
                button.Font = Enum.Font.Gotham
                button.TextSize = 16
                button.TextWrapped = true
                button.TextColor3 = Color3.new(1, 1, 1)
                button.Text = string.format("Slot %d", i)
                button.Parent = slotsFrame
                button:SetAttribute("SlotIndex", i)
                selectionUi.slotButtons[i] = button
                selectionUi.slotOriginalText[i] = button.Text
                applyScaledText(button, 12, 28)

                button.MouseButton1Click:Connect(function()
                        if loadoutSelection[i] then
                                if lobbyUi.loadoutLocked then
                                        setActiveSelectionSlot(i)
                                else
                                        clearSlot(i)
                                end
                        else
                                setActiveSelectionSlot(i)
                        end
                end)
                button.MouseButton2Click:Connect(function()
                        clearSlot(i)
                end)
        end

        lobbyUi.readyButton = Instance.new("TextButton")
        lobbyUi.readyButton.Name = "ReadyButton"
        lobbyUi.readyButton.AnchorPoint = Vector2.new(0, 1)
        lobbyUi.readyButton.Size = UDim2.new(0.47, 0, 0.26, 0)
        lobbyUi.readyButton.Position = UDim2.new(0.03, 0, 0.97, 0)
        lobbyUi.readyButton.BackgroundColor3 = Color3.fromRGB(70, 130, 90)
        lobbyUi.readyButton.BorderSizePixel = 0
        lobbyUi.readyButton.Font = Enum.Font.GothamBold
        lobbyUi.readyButton.TextSize = 20
        lobbyUi.readyButton.TextColor3 = Color3.new(1, 1, 1)
        lobbyUi.readyButton.Text = "Ready Up"
        lobbyUi.readyButton.AutoButtonColor = true
        lobbyUi.readyButton.Parent = loadoutPanel
        applyScaledText(lobbyUi.readyButton, 16, 36)

        lobbyUi.readyButton.MouseButton1Click:Connect(function()
                if not remotes.RequestReadyStatus then
                        return
                end
                remotes.RequestReadyStatus:FireServer(not lobbyUi.readyState)
        end)

        lobbyUi.leaveButton = Instance.new("TextButton")
        lobbyUi.leaveButton.Name = "LeaveButton"
        lobbyUi.leaveButton.AnchorPoint = Vector2.new(1, 1)
        lobbyUi.leaveButton.Size = UDim2.new(0.47, 0, 0.26, 0)
        lobbyUi.leaveButton.Position = UDim2.new(0.97, 0, 0.97, 0)
        lobbyUi.leaveButton.BackgroundColor3 = Color3.fromRGB(150, 80, 80)
        lobbyUi.leaveButton.BorderSizePixel = 0
        lobbyUi.leaveButton.Font = Enum.Font.GothamBold
        lobbyUi.leaveButton.TextSize = 20
        lobbyUi.leaveButton.TextColor3 = Color3.new(1, 1, 1)
        lobbyUi.leaveButton.Text = "Leave Round"
        lobbyUi.leaveButton.AutoButtonColor = true
        lobbyUi.leaveButton.Visible = false
        lobbyUi.leaveButton.Parent = loadoutPanel
        applyScaledText(lobbyUi.leaveButton, 16, 36)

        lobbyUi.leaveButton.MouseButton1Click:Connect(function()
                if remotes.RequestLeaveRound then
                        remotes.RequestLeaveRound:FireServer()
                end
        end)

        populateTowerSelectionButtons()
        for index in pairs(selectionUi.slotButtons) do
                updateSelectionSlotDisplay(index)
        end
        setActiveSelectionSlot(findFirstEmptySlot() or 1)
        updateConfirmButtonState()
        applyLoadoutLockState()

        return selectionUi.screenGui
end

local function updateInterfaceVisibility()
        if selectionUi.screenGui then
                selectionUi.screenGui.Enabled = lobbyUi.phase == "lobby"
        end

        if mapSelectionState.gui then
                mapSelectionState.gui.Enabled = lobbyUi.phase == "mapSelection"
        end

        if hudRefs.screenGui then
                local inRound = lobbyUi.phase == "inRound"
                hudRefs.screenGui.Enabled = inRound
                if not inRound then
                        resetWaveSkipButton()
                        if placingTowerType then
                                cancelPlacement()
                        else
                                setTowerBaseVisibility(false)
                        end
                end
        end
end

local PLAYER_SLOT_PADDING = 0.02

local function ensurePlayerSlots(entry, slotCount)
        slotCount = math.max(slotCount or 0, 1)

        entry.PlayerSlots = entry.PlayerSlots or {}
        local container = entry.PlayerContainer
        if not container then
                return
        end

        local layout = container:FindFirstChildOfClass("UIListLayout")
        if layout then
                layout.Padding = UDim.new(PLAYER_SLOT_PADDING, 0)
        end

        local currentCount = entry.PlayerSlotCount or 0

        if currentCount > slotCount then
                for index = slotCount + 1, currentCount do
                        local slot = entry.PlayerSlots[index]
                        if slot and slot.Frame then
                                slot.Frame:Destroy()
                        end
                        entry.PlayerSlots[index] = nil
                end
        end

        if currentCount < slotCount then
                for index = currentCount + 1, slotCount do
                        local slotFrame = Instance.new("Frame")
                        slotFrame.Name = string.format("PlayerSlot%d", index)
                        slotFrame.AnchorPoint = Vector2.new(0, 0)
                        slotFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
                        slotFrame.BackgroundTransparency = 0.05
                        slotFrame.BorderSizePixel = 0
                        slotFrame.Parent = container

                        local slotCorner = Instance.new("UICorner")
                        slotCorner.CornerRadius = UDim.new(0.18, 0)
                        slotCorner.Parent = slotFrame

                        local slotPadding = Instance.new("UIPadding")
                        slotPadding.PaddingLeft = UDim.new(0.02, 0)
                        slotPadding.PaddingRight = UDim.new(0.02, 0)
                        slotPadding.Parent = slotFrame

                        local slotLayout = Instance.new("UIListLayout")
                        slotLayout.FillDirection = Enum.FillDirection.Horizontal
                        slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
                        slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                        slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
                        slotLayout.Padding = UDim.new(0, 0)
                        slotLayout.Parent = slotFrame

                        local nameLabel = Instance.new("TextLabel")
                        nameLabel.Name = "NameLabel"
                        nameLabel.BackgroundTransparency = 1
                        nameLabel.Size = UDim2.new(0.66, 0, 1, 0)
                        nameLabel.Font = Enum.Font.GothamMedium
                        nameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
                        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                        nameLabel.TextYAlignment = Enum.TextYAlignment.Center
                        nameLabel.TextWrapped = true
                        nameLabel.Parent = slotFrame
                        applyScaledText(nameLabel, 14, 32)

                        local readyFrame = Instance.new("Frame")
                        readyFrame.Name = "ReadyFrame"
                        readyFrame.AnchorPoint = Vector2.new(0, 0)
                        readyFrame.Size = UDim2.new(0.34, 0, 1, 0)
                        readyFrame.BackgroundColor3 = NOT_READY_COLOR
                        readyFrame.BackgroundTransparency = 0.15
                        readyFrame.BorderSizePixel = 0
                        readyFrame.Parent = slotFrame

                        local readyCorner = Instance.new("UICorner")
                        readyCorner.CornerRadius = UDim.new(0.18, 0)
                        readyCorner.Parent = readyFrame

                        local readyLabel = Instance.new("TextLabel")
                        readyLabel.Name = "ReadyLabel"
                        readyLabel.BackgroundTransparency = 1
                        readyLabel.Size = UDim2.new(1, 0, 1, 0)
                        readyLabel.Font = Enum.Font.GothamBold
                        readyLabel.TextColor3 = Color3.new(1, 1, 1)
                        readyLabel.TextXAlignment = Enum.TextXAlignment.Center
                        readyLabel.TextYAlignment = Enum.TextYAlignment.Center
                        readyLabel.TextWrapped = true
                        readyLabel.Parent = readyFrame
                        applyScaledText(readyLabel, 13, 30)

                        entry.PlayerSlots[index] = {
                                Frame = slotFrame,
                                NameLabel = nameLabel,
                                ReadyFrame = readyFrame,
                                ReadyLabel = readyLabel,
                        }
                end
        end

        local totalPadding = PLAYER_SLOT_PADDING * math.max(slotCount - 1, 0)
        local rowHeight = (1 - totalPadding) / slotCount
        for index = 1, slotCount do
                        local slot = entry.PlayerSlots[index]
                        if slot and slot.Frame then
                                slot.Frame.LayoutOrder = index
                                slot.Frame.Size = UDim2.new(1, 0, rowHeight, 0)
                        end
        end

        entry.PlayerSlotCount = slotCount
end

local function updateRoundButtons(rounds, playerRound, hasLoadout)
        if not selectionUi.screenGui then
                createSelectionGui()
        end

        if not lobbyUi.roundList then
                return
        end

        local existing = {}
        for index, round in ipairs(rounds or {}) do
                local roundKey = round.Key or tostring(index)
                existing[roundKey] = true

                local entry = lobbyUi.roundButtons[roundKey]
                if not entry then
                        local frame = Instance.new("Frame")
                        frame.Name = string.format("Round%sEntry", roundKey)
                        frame.AnchorPoint = Vector2.new(0, 0)
                        frame.Size = UDim2.new(1, 0, 0.56, 0)
                        frame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
                        frame.BackgroundTransparency = 0.05
                        frame.BorderSizePixel = 0
                        frame.Parent = lobbyUi.roundList

                        local frameCorner = Instance.new("UICorner")
                        frameCorner.CornerRadius = UDim.new(0.04, 0)
                        frameCorner.Parent = frame

                        local titleLabel = Instance.new("TextLabel")
                        titleLabel.Name = "RoundName"
                        titleLabel.AnchorPoint = Vector2.new(0, 0)
                        titleLabel.Position = UDim2.new(0.03, 0, 0.05, 0)
                        titleLabel.Size = UDim2.new(0.94, 0, 0.18, 0)
                        titleLabel.BackgroundTransparency = 1
                        titleLabel.Font = Enum.Font.GothamBold
                        titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
                        titleLabel.TextYAlignment = Enum.TextYAlignment.Center
                        titleLabel.Text = ""
                        titleLabel.Parent = frame
                        applyScaledText(titleLabel, 14, 34)

                        local joinButton = Instance.new("TextButton")
                        joinButton.Name = "JoinButton"
                        joinButton.AnchorPoint = Vector2.new(0, 0)
                        joinButton.Position = UDim2.new(0.03, 0, 0.22, 0)
                        joinButton.Size = UDim2.new(0.44, 0, 0.2, 0)
                        joinButton.BackgroundColor3 = Color3.fromRGB(70, 130, 90)
                        joinButton.BorderSizePixel = 0
                        joinButton.Font = Enum.Font.GothamBold
                        joinButton.TextColor3 = Color3.new(1, 1, 1)
                        joinButton.TextWrapped = true
                        joinButton.TextXAlignment = Enum.TextXAlignment.Center
                        joinButton.TextYAlignment = Enum.TextYAlignment.Center
                        joinButton.Text = "Join"
                        joinButton.AutoButtonColor = true
                        joinButton.Parent = frame
                        applyScaledText(joinButton, 14, 32)
                        joinButton.MouseButton1Click:Connect(function()
                                local key = joinButton:GetAttribute("RoundKey")
                                if key and remotes.RequestJoinRound then
                                        remotes.RequestJoinRound:FireServer(key)
                                end
                        end)

                        local countdownLabel = Instance.new("TextLabel")
                        countdownLabel.Name = "CountdownLabel"
                        countdownLabel.AnchorPoint = Vector2.new(0, 0)
                        countdownLabel.Position = UDim2.new(0.5, 0, 0.22, 0)
                        countdownLabel.Size = UDim2.new(0.47, 0, 0.2, 0)
                        countdownLabel.BackgroundTransparency = 1
                        countdownLabel.Font = Enum.Font.Gotham
                        countdownLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
                        countdownLabel.TextXAlignment = Enum.TextXAlignment.Left
                        countdownLabel.TextYAlignment = Enum.TextYAlignment.Top
                        countdownLabel.TextWrapped = true
                        countdownLabel.Text = ""
                        countdownLabel.Parent = frame
                        applyScaledText(countdownLabel, 13, 30)

                        local playerContainer = Instance.new("Frame")
                        playerContainer.Name = "PlayerContainer"
                        playerContainer.AnchorPoint = Vector2.new(0, 0)
                        playerContainer.Position = UDim2.new(0.03, 0, 0.46, 0)
                        playerContainer.Size = UDim2.new(0.94, 0, 0.46, 0)
                        playerContainer.BackgroundTransparency = 1
                        playerContainer.Parent = frame

                        local playerLayout = Instance.new("UIListLayout")
                        playerLayout.FillDirection = Enum.FillDirection.Vertical
                        playerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
                        playerLayout.SortOrder = Enum.SortOrder.LayoutOrder
                        playerLayout.Padding = UDim.new(PLAYER_SLOT_PADDING, 0)
                        playerLayout.Parent = playerContainer

                        entry = {
                                Frame = frame,
                                TitleLabel = titleLabel,
                                JoinButton = joinButton,
                                CountdownLabel = countdownLabel,
                                PlayerContainer = playerContainer,
                                PlayerSlots = {},
                                PlayerSlotCount = 0,
                        }
                        lobbyUi.roundButtons[roundKey] = entry
                end

                local players = round.Players or {}
                local occupantCount = #players
                local requiredPlayers = tonumber(round.RequiredPlayers) or 0
                local slotCount = requiredPlayers > 0 and requiredPlayers or math.max(occupantCount, 1)
                ensurePlayerSlots(entry, slotCount)

                local baseSlotHeight = 0.14
                local containerTop = 0.46
                local containerBottomBuffer = 0.04
                local slotAreaHeight = math.clamp(
                        baseSlotHeight * slotCount + (PLAYER_SLOT_PADDING * math.max(slotCount - 1, 0)) + 0.06,
                        0.26,
                        0.68
                )
                slotAreaHeight = math.min(slotAreaHeight, 1 - containerTop - containerBottomBuffer)
                entry.PlayerContainer.Position = UDim2.new(0.03, 0, containerTop, 0)
                entry.PlayerContainer.Size = UDim2.new(0.94, 0, slotAreaHeight, 0)

                local frameHeight = math.clamp(containerTop + slotAreaHeight + containerBottomBuffer, 0.52, 1)
                entry.Frame.Size = UDim2.new(1, 0, frameHeight, 0)
                entry.Frame.LayoutOrder = round.RequiredPlayers or index
                entry.TitleLabel.Text = round.DisplayName or roundKey

                local requiredText = requiredPlayers > 0 and tostring(requiredPlayers) or "∞"
                entry.JoinButton:SetAttribute("RoundKey", roundKey)
                entry.JoinButton.Active = hasLoadout
                entry.JoinButton.AutoButtonColor = hasLoadout
                entry.JoinButton.TextTransparency = hasLoadout and 0 or 0.35
                entry.JoinButton.Text = "Join"

                local occupancyText = string.format("%d/%s Players", occupantCount, requiredText)
                entry.CountdownLabel.TextTransparency = hasLoadout and 0 or 0.35
                entry.CountdownLabel.Text = occupancyText

                for slotIndex = 1, slotCount do
                        local slot = entry.PlayerSlots[slotIndex]
                        local occupant = players[slotIndex]
                        if slot then
                                if occupant then
                                        slot.Frame.BackgroundTransparency = 0.05
                                        slot.NameLabel.Text = occupant.Name or "Player"
                                        slot.NameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
                                        slot.NameLabel.TextTransparency = 0

                                        local isReady = occupant.Ready == true
                                        slot.ReadyLabel.Text = isReady and "Ready" or "Not Ready"
                                        slot.ReadyLabel.TextColor3 = Color3.new(1, 1, 1)
                                        slot.ReadyLabel.TextTransparency = 0
                                        slot.ReadyFrame.BackgroundColor3 = isReady and READY_COLOR or NOT_READY_COLOR
                                        slot.ReadyFrame.BackgroundTransparency = isReady and 0.05 or 0.15
                                else
                                        slot.Frame.BackgroundTransparency = 0.25
                                        slot.NameLabel.Text = "Empty Slot"
                                        slot.NameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
                                        slot.NameLabel.TextTransparency = 0.35
                                        slot.ReadyLabel.Text = "Waiting"
                                        slot.ReadyLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
                                        slot.ReadyLabel.TextTransparency = 0.35
                                        slot.ReadyFrame.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                                        slot.ReadyFrame.BackgroundTransparency = 0.5
                                end
                        end
                end

                if playerRound == roundKey then
                        entry.Frame.BackgroundColor3 = Color3.fromRGB(90, 110, 160)
                else
                        entry.Frame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
                end
        end

        for key, entry in pairs(lobbyUi.roundButtons) do
                if not existing[key] then
                        if entry.Frame then
                                entry.Frame:Destroy()
                        end
                        lobbyUi.roundButtons[key] = nil
                end
        end
end

local function applyLobbyState(state)
        lobbyUi.stateSnapshot = state
        lobbyUi.phase = state and state.Phase or lobbyUi.phase
        lobbyUi.readyState = state and state.Player and state.Player.Ready or false

        local playerInfo = state and state.Player or {}
        local playerRound = playerInfo.CurrentRound
        local hasLoadout = playerInfo.HasLoadout ~= false
        local countdownActive = false
        local countdownRemaining = 0

        if playerRound then
                for _, round in ipairs(state and state.Rounds or {}) do
                        if round.Key == playerRound then
                                local remaining = tonumber(round.Countdown) or 0
                                if remaining > 0 then
                                        countdownActive = true
                                        countdownRemaining = remaining
                                end
                                break
                        end
                end
        end

        local shouldLockLoadout = countdownActive or playerRound ~= nil
        setLoadoutLocked(shouldLockLoadout)

        updateInterfaceVisibility()

        if lobbyUi.phase ~= "lobby" then
                return
        end

        createSelectionGui()

        updateRoundButtons(state and state.Rounds or {}, playerRound, hasLoadout)

        if lobbyUi.countdownLabel then
                local countdownText = ""
                if countdownActive then
                        countdownText = string.format("Countdown: %ds", countdownRemaining)
                else
                        for _, round in ipairs(state and state.Rounds or {}) do
                                if round.Key == playerRound and round.Countdown and round.Countdown > 0 then
                                        countdownText = string.format("Countdown: %ds", round.Countdown)
                                        break
                                end
                        end
                end
                lobbyUi.countdownLabel.Text = countdownText
        end

        if lobbyUi.readyButton then
                lobbyUi.readyButton.Text = lobbyUi.readyState and "Unready" or "Ready Up"
                lobbyUi.readyButton.BackgroundColor3 = lobbyUi.readyState and Color3.fromRGB(110, 90, 160) or Color3.fromRGB(70, 130, 90)
                local inLobbyRoom = playerRound ~= nil
                local canReady = hasLoadout and inLobbyRoom
                lobbyUi.readyButton.Visible = inLobbyRoom
                lobbyUi.readyButton.Active = canReady
                lobbyUi.readyButton.AutoButtonColor = canReady
                lobbyUi.readyButton.TextTransparency = canReady and 0 or 0.35
        end

        if lobbyUi.leaveButton then
                local canLeave = playerRound ~= nil
                lobbyUi.leaveButton.Visible = canLeave
                lobbyUi.leaveButton.Active = canLeave
                lobbyUi.leaveButton.AutoButtonColor = canLeave
        end

        if lobbyUi.statusLabel then
                if lobbyUi.loadoutLocked then
                        lobbyUi.statusLabel.Text = "Loadout locked while the countdown is active."
                elseif not hasLoadout or not hasAnySelectedTowers() then
                        lobbyUi.statusLabel.Text = "Select at least one tower to join a round."
                elseif not playerRound then
                        lobbyUi.statusLabel.Text = "Choose a round to enter the waiting room."
                else
                        lobbyUi.statusLabel.Text = ""
                end
        end
end

local function createMapSelectionGui()
        if mapSelectionState.gui then
                return mapSelectionState.gui
        end

        mapSelectionState.gui = Instance.new("ScreenGui")
        mapSelectionState.gui.Name = "MapSelectionUI"
        mapSelectionState.gui.ResetOnSpawn = false
        mapSelectionState.gui.IgnoreGuiInset = true
        mapSelectionState.gui.DisplayOrder = 6
        mapSelectionState.gui.Enabled = false
        mapSelectionState.gui.Parent = playerGui

        mapSelectionState.frame = Instance.new("Frame")
        mapSelectionState.frame.Name = "MapSelectionFrame"
        mapSelectionState.frame.AnchorPoint = Vector2.new(0.5, 0.5)
        mapSelectionState.frame.Size = UDim2.fromScale(0.8, 0.7)
        mapSelectionState.frame.Position = UDim2.fromScale(0.5, 0.5)
        mapSelectionState.frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        mapSelectionState.frame.BackgroundTransparency = 0.1
        mapSelectionState.frame.BorderSizePixel = 0
        mapSelectionState.frame.Parent = mapSelectionState.gui

        local frameCorner = Instance.new("UICorner")
        frameCorner.CornerRadius = UDim.new(0.03, 0)
        frameCorner.Parent = mapSelectionState.frame

        local mapFrameConstraint = Instance.new("UIAspectRatioConstraint")
        mapFrameConstraint.AspectRatio = 720 / 420
        mapFrameConstraint.DominantAxis = Enum.DominantAxis.Width
        mapFrameConstraint.Parent = mapSelectionState.frame

        local mapSizeConstraint = Instance.new("UISizeConstraint")
        mapSizeConstraint.MinSize = Vector2.new(600, 360)
        mapSizeConstraint.Parent = mapSelectionState.frame

        local title = Instance.new("TextLabel")
        title.Name = "MapSelectionTitle"
        title.AnchorPoint = Vector2.new(0, 0)
        title.Size = UDim2.new(0.94, 0, 0.14, 0)
        title.Position = UDim2.new(0.03, 0, 0.05, 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 28
        title.TextColor3 = Color3.new(1, 1, 1)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = "Vote for a Map"
        title.Parent = mapSelectionState.frame
        applyScaledText(title, 18, 42)

        mapSelectionState.statusLabel = Instance.new("TextLabel")
        mapSelectionState.statusLabel.Name = "StatusLabel"
        mapSelectionState.statusLabel.AnchorPoint = Vector2.new(0, 0)
        mapSelectionState.statusLabel.Size = UDim2.new(0.94, 0, 0.1, 0)
        mapSelectionState.statusLabel.Position = UDim2.new(0.03, 0, 0.22, 0)
        mapSelectionState.statusLabel.BackgroundTransparency = 1
        mapSelectionState.statusLabel.Font = Enum.Font.Gotham
        mapSelectionState.statusLabel.TextSize = 18
        mapSelectionState.statusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        mapSelectionState.statusLabel.TextXAlignment = Enum.TextXAlignment.Left
        mapSelectionState.statusLabel.Text = "Choose one of the available battlegrounds."
        mapSelectionState.statusLabel.Parent = mapSelectionState.frame
        applyScaledText(mapSelectionState.statusLabel, 14, 30)

        mapSelectionState.optionsContainer = Instance.new("Frame")
        mapSelectionState.optionsContainer.Name = "OptionsContainer"
        mapSelectionState.optionsContainer.AnchorPoint = Vector2.new(0, 0)
        mapSelectionState.optionsContainer.Size = UDim2.new(0.94, 0, 0.68, 0)
        mapSelectionState.optionsContainer.Position = UDim2.new(0.03, 0, 0.32, 0)
        mapSelectionState.optionsContainer.BackgroundTransparency = 1
        mapSelectionState.optionsContainer.Parent = mapSelectionState.frame

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.Padding = UDim.new(0.04, 0)
        layout.Parent = mapSelectionState.optionsContainer

        return mapSelectionState.gui
end

local function clearMapOptions()
        for _, button in ipairs(mapSelectionState.optionButtons) do
                if button then
                        button:Destroy()
                end
        end
        mapSelectionState.optionButtons = {}
        mapSelectionState.voteLabels = {}
end

local function showMapSelection(options, totalPlayers)
        createMapSelectionGui()
        clearMapOptions()

        mapSelectionState.totalPlayers = totalPlayers or 0

        for index, option in ipairs(options or {}) do
                local container = Instance.new("Frame")
                container.Name = string.format("Option%d", index)
                container.Size = UDim2.new(0.3, 0, 1, 0)
                container.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
                container.BackgroundTransparency = 0.05
                container.BorderSizePixel = 0
                container.Parent = mapSelectionState.optionsContainer

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0.05, 0)
                corner.Parent = container

                local nameLabel = Instance.new("TextLabel")
                nameLabel.Name = "NameLabel"
                nameLabel.AnchorPoint = Vector2.new(0, 0)
                nameLabel.Size = UDim2.new(0.9, 0, 0.24, 0)
                nameLabel.Position = UDim2.new(0.05, 0, 0.05, 0)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Font = Enum.Font.GothamBold
                nameLabel.TextSize = 20
                nameLabel.TextColor3 = Color3.new(1, 1, 1)
                nameLabel.TextWrapped = true
                nameLabel.Text = option.Name or string.format("Map %d", index)
                nameLabel.Parent = container
                applyScaledText(nameLabel, 16, 36)

                local descriptionLabel = Instance.new("TextLabel")
                descriptionLabel.Name = "DescriptionLabel"
                descriptionLabel.AnchorPoint = Vector2.new(0, 0)
                descriptionLabel.Size = UDim2.new(0.9, 0, 0.24, 0)
                descriptionLabel.Position = UDim2.new(0.05, 0, 0.35, 0)
                descriptionLabel.BackgroundTransparency = 1
                descriptionLabel.Font = Enum.Font.Gotham
                descriptionLabel.TextSize = 16
                descriptionLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
                descriptionLabel.TextWrapped = true
                descriptionLabel.Text = option.Description or ""
                descriptionLabel.Parent = container
                applyScaledText(descriptionLabel, 12, 28)

                local voteButton = Instance.new("TextButton")
                voteButton.Name = "VoteButton"
                voteButton.AnchorPoint = Vector2.new(0, 0)
                voteButton.Size = UDim2.new(0.9, 0, 0.18, 0)
                voteButton.Position = UDim2.new(0.05, 0, 0.62, 0)
                voteButton.BackgroundColor3 = Color3.fromRGB(70, 130, 90)
                voteButton.BorderSizePixel = 0
                voteButton.Font = Enum.Font.GothamBold
                voteButton.TextSize = 18
                voteButton.TextColor3 = Color3.new(1, 1, 1)
                voteButton.Text = "Vote"
                voteButton.AutoButtonColor = true
                voteButton.Parent = container
                applyScaledText(voteButton, 16, 34)

                local voteLabel = Instance.new("TextLabel")
                voteLabel.Name = "VoteLabel"
                voteLabel.AnchorPoint = Vector2.new(0, 0)
                voteLabel.Size = UDim2.new(0.9, 0, 0.12, 0)
                voteLabel.Position = UDim2.new(0.05, 0, 0.84, 0)
                voteLabel.BackgroundTransparency = 1
                voteLabel.Font = Enum.Font.Gotham
                voteLabel.TextSize = 16
                voteLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
                if mapSelectionState.totalPlayers > 0 then
                        voteLabel.Text = string.format("0 / %d votes", mapSelectionState.totalPlayers)
                else
                        voteLabel.Text = "0 votes"
                end
                voteLabel.Parent = container
                applyScaledText(voteLabel, 12, 26)

                voteButton.MouseButton1Click:Connect(function()
                        if remotes.MapVoteSubmitted then
                                remotes.MapVoteSubmitted:FireServer(index)
                        end
                end)

                mapSelectionState.optionButtons[index] = {
                        Container = container,
                        Button = voteButton,
                        Option = option,
                }
                mapSelectionState.voteLabels[index] = voteLabel
        end

        if mapSelectionState.statusLabel then
                if totalPlayers and totalPlayers > 0 then
                        mapSelectionState.statusLabel.Text = string.format("Vote for a map (%d players)", totalPlayers)
                else
                        mapSelectionState.statusLabel.Text = "Vote for a map"
                end
        end

        mapSelectionState.gui.Enabled = true
end

local function updateMapVoteCounts(counts, totalPlayers)
        if totalPlayers then
                mapSelectionState.totalPlayers = totalPlayers
        end

        local displayTotal = mapSelectionState.totalPlayers or 0

        for index, label in pairs(mapSelectionState.voteLabels) do
                local votes = counts and counts[index] or 0
                if label then
                        if displayTotal > 0 then
                                label.Text = string.format("%d / %d votes", votes, displayTotal)
                        else
                                label.Text = string.format("%d votes", votes)
                        end
                end
        end
end

local function finalizeMapSelection(selectedIndex, option)
        for index, entry in ipairs(mapSelectionState.optionButtons) do
                if entry.Button then
                        entry.Button.Active = false
                        entry.Button.AutoButtonColor = false
                        if index == selectedIndex then
                                entry.Button.Text = "Selected"
                                entry.Button.BackgroundColor3 = Color3.fromRGB(110, 90, 160)
                        else
                                entry.Button.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
                        end
                end
        end

        if mapSelectionState.statusLabel then
                if option and option.Name then
                        mapSelectionState.statusLabel.Text = string.format("%s will be loaded.", option.Name)
                else
                        mapSelectionState.statusLabel.Text = "Map selected."
                end
        end
end

local function ensureHoverGui()
        if hoverUi.frame then
                return hoverUi.frame
        end

	hoverUi.container = Instance.new("ScreenGui")
	hoverUi.container.Name = "EnemyHoverUI"
	hoverUi.container.ResetOnSpawn = false
	hoverUi.container.IgnoreGuiInset = true
	hoverUi.container.DisplayOrder = 6
	hoverUi.container.Enabled = true
	hoverUi.container.Parent = playerGui

        hoverUi.frame = Instance.new("Frame")
        hoverUi.frame.Name = "EnemyHoverFrame"
        hoverUi.frame.AnchorPoint = Vector2.new(0, 1)
        hoverUi.frame.Size = UDim2.new(0.18, 0, 0.08, 0)
        hoverUi.frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        hoverUi.frame.BackgroundTransparency = 0.2
        hoverUi.frame.BorderSizePixel = 0
        hoverUi.frame.Visible = false
        hoverUi.frame.Parent = hoverUi.container

        local hoverCorner = Instance.new("UICorner")
        hoverCorner.CornerRadius = UDim.new(0.25, 0)
        hoverCorner.Parent = hoverUi.frame

        hoverUi.nameLabel = Instance.new("TextLabel")
        hoverUi.nameLabel.Name = "NameLabel"
        hoverUi.nameLabel.BackgroundTransparency = 1
        hoverUi.nameLabel.AnchorPoint = Vector2.new(0, 0)
        hoverUi.nameLabel.Position = UDim2.new(0.04, 0, 0.12, 0)
        hoverUi.nameLabel.Size = UDim2.new(0.92, 0, 0.46, 0)
        hoverUi.nameLabel.Font = Enum.Font.GothamBold
        hoverUi.nameLabel.TextColor3 = Color3.new(1, 1, 1)
        hoverUi.nameLabel.TextSize = 18
        hoverUi.nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        hoverUi.nameLabel.Text = "Enemy"
        hoverUi.nameLabel.Parent = hoverUi.frame
        applyScaledText(hoverUi.nameLabel, 12, 28)

        hoverUi.healthLabel = Instance.new("TextLabel")
        hoverUi.healthLabel.Name = "HealthLabel"
        hoverUi.healthLabel.BackgroundTransparency = 1
        hoverUi.healthLabel.AnchorPoint = Vector2.new(0, 0)
        hoverUi.healthLabel.Position = UDim2.new(0.04, 0, 0.58, 0)
        hoverUi.healthLabel.Size = UDim2.new(0.92, 0, 0.32, 0)
	hoverUi.healthLabel.Font = Enum.Font.Gotham
        hoverUi.healthLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        hoverUi.healthLabel.TextSize = 16
        hoverUi.healthLabel.TextXAlignment = Enum.TextXAlignment.Left
        hoverUi.healthLabel.Text = "HP: 0"
        hoverUi.healthLabel.Parent = hoverUi.frame
        applyScaledText(hoverUi.healthLabel, 12, 24)

	hoverUi.combinedLabel = nil

	return hoverUi.frame
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

local function formatCurrency(amount)
        local numeric = tonumber(amount) or 0
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
                if typeof(config) == "table" and config.Cost and config.Name == towerModel.Name then
                        return key
                end
        end

	return nil
end

local function resolveRangeRingPosition(sourcePosition)
        if not sourcePosition then
                return nil
        end

        local map = workspace:FindFirstChild("Map")
        if not map then
                return sourcePosition
        end

        local pathGround = map:FindFirstChild("PathGround")
        if not pathGround then
                return sourcePosition
        end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = { pathGround }
        params.IgnoreWater = true

        local origin = sourcePosition + Vector3.new(0, 500, 0)
        local result = workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
        if result then
                return result.Position
        end

        return sourcePosition
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

        local towerType = resolveTowerType(towerModel)
        local storedPlacement = towerModel:GetAttribute("PlacementPosition")

        local groundPosition
        if typeof(storedPlacement) == "Vector3" then
                groundPosition = storedPlacement
        else
                local surfaceResult = placementValidation:findPlacementSurface(base.Position, towerType)
                if surfaceResult then
                        groundPosition = surfaceResult.Position
                else
                        groundPosition = Vector3.new(base.Position.X, base.Position.Y - (base.Size.Y / 2), base.Position.Z)
                end
        end

        groundPosition = resolveRangeRingPosition(groundPosition)

        hudRefs.rangeRing, hudRefs.rangeRingAdornment = createRangeRing("TowerRangeRing", Color3.fromRGB(80, 200, 255), 0.35)
        updateRangeRing(
                hudRefs.rangeRing,
                hudRefs.rangeRingAdornment,
                range,
                Vector3.new(groundPosition.X, groundPosition.Y + 0.05, groundPosition.Z)
        )
end

local function applyUpgradeButtonStyle(disabled)
	if not towerDetailsUi.upgradeButton then
		return
	end

	if not towerDetailsUi.upgradeButtonOriginalColor then
		towerDetailsUi.upgradeButtonOriginalColor = towerDetailsUi.upgradeButton.BackgroundColor3
	end
	if not towerDetailsUi.upgradeButtonOriginalTextColor then
		towerDetailsUi.upgradeButtonOriginalTextColor = towerDetailsUi.upgradeButton.TextColor3
	end
	if towerDetailsUi.upgradeButtonOriginalBackgroundTransparency == nil then
		towerDetailsUi.upgradeButtonOriginalBackgroundTransparency = towerDetailsUi.upgradeButton.BackgroundTransparency
	end
	if towerDetailsUi.upgradeButtonOriginalTextTransparency == nil then
		towerDetailsUi.upgradeButtonOriginalTextTransparency = towerDetailsUi.upgradeButton.TextTransparency
	end

	if disabled then
		if towerDetailsUi.upgradeButtonOriginalColor then
			towerDetailsUi.upgradeButton.BackgroundColor3 = towerDetailsUi.upgradeButtonOriginalColor:Lerp(GREY_COLOR, 0.2)
		end
		if towerDetailsUi.upgradeButtonOriginalTextColor then
			towerDetailsUi.upgradeButton.TextColor3 = towerDetailsUi.upgradeButtonOriginalTextColor:Lerp(GREY_COLOR, 0.2)
		end
	else
		if towerDetailsUi.upgradeButtonOriginalColor then
			towerDetailsUi.upgradeButton.BackgroundColor3 = towerDetailsUi.upgradeButtonOriginalColor
		end
		if towerDetailsUi.upgradeButtonOriginalTextColor then
			towerDetailsUi.upgradeButton.TextColor3 = towerDetailsUi.upgradeButtonOriginalTextColor
		end
	end

	if towerDetailsUi.upgradeButtonOriginalBackgroundTransparency ~= nil then
		towerDetailsUi.upgradeButton.BackgroundTransparency = towerDetailsUi.upgradeButtonOriginalBackgroundTransparency
	end
	if towerDetailsUi.upgradeButtonOriginalTextTransparency ~= nil then
		towerDetailsUi.upgradeButton.TextTransparency = towerDetailsUi.upgradeButtonOriginalTextTransparency
	end
end

local function updateUpgradeButton(towerType, level, ownerUserId)
	if not towerDetailsUi.upgradeButton then
		return
	end

	local nextUpgrade = getNextUpgrade(towerType, level)

	if towerDetailsUi.upgradeDescriptionLabel then
		if nextUpgrade and nextUpgrade.Description then
			if ownerUserId == player.UserId then
				towerDetailsUi.upgradeDescriptionLabel.Text = string.format("%s\nPress E to upgrade.", nextUpgrade.Description)
			else
				towerDetailsUi.upgradeDescriptionLabel.Text = nextUpgrade.Description
			end
		else
			if ownerUserId == player.UserId then
				towerDetailsUi.upgradeDescriptionLabel.Text = "Fully upgraded\nPress X to sell if you need the space."
			else
				towerDetailsUi.upgradeDescriptionLabel.Text = "Fully upgraded"
			end
		end
	end

	if not nextUpgrade then
		towerDetailsUi.upgradeButton.Text = "Max Level"
		towerDetailsUi.upgradeButton.AutoButtonColor = false
		towerDetailsUi.upgradeButton.Active = false
		applyUpgradeButtonStyle(true)
		towerDetailsUi.upgradeButton.Visible = true
		return
	end

	if ownerUserId ~= player.UserId then
		towerDetailsUi.upgradeButton.Text = "Not your tower"
		towerDetailsUi.upgradeButton.AutoButtonColor = false
		towerDetailsUi.upgradeButton.Active = false
		applyUpgradeButtonStyle(true)
		towerDetailsUi.upgradeButton.Visible = true
		return
	end

	local affordable = currentMoney >= nextUpgrade.Cost
	if towerDetailsUi.upgradeButtonOriginalAutoButtonColor == nil then
		towerDetailsUi.upgradeButtonOriginalAutoButtonColor = towerDetailsUi.upgradeButton.AutoButtonColor
	end
	towerDetailsUi.upgradeButton.Text = string.format("Upgrade (E) - $%d", nextUpgrade.Cost)
	towerDetailsUi.upgradeButton.Active = affordable
	towerDetailsUi.upgradeButton.AutoButtonColor = affordable and towerDetailsUi.upgradeButtonOriginalAutoButtonColor or false
	applyUpgradeButtonStyle(not affordable)
	towerDetailsUi.upgradeButton.Visible = true
end

local function updateSellButton(towerModel, ownerUserId)
	if not towerDetailsUi.sellButton then
		return
	end

	if not towerModel then
		towerDetailsUi.sellButton.Visible = false
		return
	end

	local sellValue = towerModel:GetAttribute("SellValue")
	if typeof(sellValue) ~= "number" or sellValue <= 0 then
		towerDetailsUi.sellButton.Visible = false
		return
	end

	local refund = math.floor(sellValue + 0.5)
	towerDetailsUi.sellButton.Text = string.format("Sell (X) +$%d", refund)
	towerDetailsUi.sellButton.Visible = true

	local isOwner = ownerUserId == player.UserId
	local active = isOwner and not gameEnded
	if towerDetailsUi.sellButtonOriginalAutoButtonColor == nil then
		towerDetailsUi.sellButtonOriginalAutoButtonColor = towerDetailsUi.sellButton.AutoButtonColor
	end
	towerDetailsUi.sellButton.AutoButtonColor = active and towerDetailsUi.sellButtonOriginalAutoButtonColor or false
	towerDetailsUi.sellButton.Active = active
	towerDetailsUi.sellButton.Selectable = active
end

local function updateTowerDetails(towerModel)
	if not towerDetailsUi.frame or not towerModel then
		return
	end

	local towerType = resolveTowerType(towerModel)
	if not towerType then
		towerDetailsUi.frame.Visible = false
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
	if towerDetailsUi.nameLabel then
		local displayName = config and config.Name or towerModel.Name
		towerDetailsUi.nameLabel.Text = displayName
	end
	if towerDetailsUi.levelLabel then
		towerDetailsUi.levelLabel.Text = string.format("Level: %d", level)
	end

	local stats = getTowerStatsForLevel(towerType, level)
	if stats and towerDetailsUi.statsLabel then
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
                if stats.IncomePerWave and stats.IncomePerWave > 0 then
                        table.insert(lines, string.format("Income: %s per wave", formatCurrency(stats.IncomePerWave)))
                end
                if stats.BoostRadius and stats.BoostRadius > 0 then
                        table.insert(lines, string.format("Boost Radius: %.1f", stats.BoostRadius))
                end
                local buffs = stats.Buffs
                if buffs then
                        local rangeMultiplier = tonumber(buffs.RangeMultiplier)
                        if rangeMultiplier and math.abs(rangeMultiplier - 1) > 0.001 then
                                table.insert(lines, string.format("Buff Range: +%d%%", math.floor((rangeMultiplier - 1) * 100 + 0.5)))
                        end
                        local fireRateMultiplier = tonumber(buffs.FireRateMultiplier)
                        if fireRateMultiplier and math.abs(fireRateMultiplier - 1) > 0.001 then
                                local cooldownReduction = (1 - fireRateMultiplier) * 100
                                table.insert(lines, string.format("Buff Cooldown: -%d%%", math.floor(cooldownReduction + 0.5)))
                        end
                end
                towerDetailsUi.statsLabel.Text = table.concat(lines, "\n")
        elseif towerDetailsUi.statsLabel then
                towerDetailsUi.statsLabel.Text = ""
        end

	if towerDetailsUi.ownershipLabel then
		if ownerUserId == player.UserId then
			towerDetailsUi.ownershipLabel.Text = "Owner: You (E to upgrade, X to sell)"
		else
			towerDetailsUi.ownershipLabel.Text = string.format("Owner: %s", ownerText)
		end
	end

	towerDetailsUi.frame.Visible = true
	showRangeIndicator(towerModel, stats and stats.Range)
	updateUpgradeButton(towerType, level, ownerUserId)
	updateSellButton(towerModel, ownerUserId)
end

local function createGui()
	if hudRefs.screenGui then
		return hudRefs.screenGui
	end

	hudRefs.screenGui = Instance.new("ScreenGui")
	hudRefs.screenGui.Name = "TowerHUD"
	hudRefs.screenGui.ResetOnSpawn = false
	hudRefs.screenGui.IgnoreGuiInset = true
	hudRefs.screenGui.DisplayOrder = 4
	hudRefs.screenGui.Parent = playerGui

        hudRefs.shopFrame = Instance.new("Frame")
        hudRefs.shopFrame.Name = "Shop"
        hudRefs.shopFrame.Size = UDim2.new(0.7, 0, 0.22, 0)
        hudRefs.shopFrame.AnchorPoint = Vector2.new(0.5, 1)
        hudRefs.shopFrame.Position = UDim2.new(0.5, 0, 0.98, 0)
        hudRefs.shopFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        hudRefs.shopFrame.BackgroundTransparency = 0.1
        hudRefs.shopFrame.BorderSizePixel = 0
        hudRefs.shopFrame.Parent = hudRefs.screenGui

        local shopCorner = Instance.new("UICorner")
        shopCorner.CornerRadius = UDim.new(0.05, 0)
        shopCorner.Parent = hudRefs.shopFrame

        local slotLayout = Instance.new("UIListLayout")
        slotLayout.FillDirection = Enum.FillDirection.Horizontal
        slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
        slotLayout.Padding = UDim.new(0.02, 0)
        slotLayout.Parent = hudRefs.shopFrame

        shopSlotButtons = {}
        shopSlotOriginalText = {}
        shopSlotCountLabels = {}
        for i = 1, LOADOUT_SLOT_COUNT do
                local slotContainer = Instance.new("Frame")
                slotContainer.Name = string.format("ShopSlotContainer%d", i)
                slotContainer.Size = UDim2.new(0.18, 0, 1, 0)
                slotContainer.BackgroundTransparency = 1
                slotContainer.BorderSizePixel = 0
                slotContainer.LayoutOrder = i
                slotContainer.Parent = hudRefs.shopFrame

                local priceLabel = Instance.new("TextLabel")
                priceLabel.Name = "PriceLabel"
                priceLabel.BackgroundTransparency = 1
                priceLabel.AnchorPoint = Vector2.new(0.5, 0)
                priceLabel.Size = UDim2.new(0.9, 0, 0.18, 0)
                priceLabel.Position = UDim2.new(0.5, 0, 0.02, 0)
                priceLabel.Font = Enum.Font.Gotham
                priceLabel.TextSize = 18
                priceLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
                priceLabel.Text = ""
                priceLabel.TextXAlignment = Enum.TextXAlignment.Center
                priceLabel.TextYAlignment = Enum.TextYAlignment.Center
                priceLabel.TextWrapped = true
                priceLabel.Visible = false
                priceLabel.Parent = slotContainer
                shopSlotPriceLabels[i] = priceLabel
                applyScaledText(priceLabel, 12, 26)

                local button = Instance.new("TextButton")
                button.Name = string.format("ShopSlot%d", i)
                button.AnchorPoint = Vector2.new(0.5, 0)
                button.Size = UDim2.new(0.9, 0, 0.52, 0)
                button.Position = UDim2.new(0.5, 0, 0.24, 0)
                button.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
                button.BorderSizePixel = 0
                button.Font = Enum.Font.Gotham
                button.TextSize = 18
                button.TextColor3 = Color3.new(1, 1, 1)
                button.Text = string.format("Slot %d", i)
                button.AutoButtonColor = true
                button.Parent = slotContainer
                button:SetAttribute("SlotIndex", i)
                shopSlotButtons[i] = button
                shopSlotOriginalText[i] = button.Text
                applyScaledText(button, 14, 32)

                local countLabel = Instance.new("TextLabel")
                countLabel.Name = "CountLabel"
                countLabel.BackgroundTransparency = 1
                countLabel.AnchorPoint = Vector2.new(0.5, 1)
                countLabel.Size = UDim2.new(0.9, 0, 0.22, 0)
                countLabel.Position = UDim2.new(0.5, 0, 0.98, 0)
                countLabel.Font = Enum.Font.Gotham
                countLabel.TextSize = 14
                countLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
                countLabel.TextXAlignment = Enum.TextXAlignment.Center
                countLabel.TextYAlignment = Enum.TextYAlignment.Center
                countLabel.TextWrapped = true
                countLabel.Text = ""
                countLabel.Visible = false
                countLabel.Parent = slotContainer
                shopSlotCountLabels[i] = countLabel
                applyScaledText(countLabel, 12, 24)
        end

        hudRefs.statusFrame = Instance.new("Frame")
        hudRefs.statusFrame.Name = "Status"
        hudRefs.statusFrame.AnchorPoint = Vector2.new(0, 1)
        hudRefs.statusFrame.Size = UDim2.new(0.22, 0, 0.34, 0)
        hudRefs.statusFrame.Position = UDim2.new(0.02, 0, 0.98, 0)
        hudRefs.statusFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        hudRefs.statusFrame.BackgroundTransparency = 0.1
        hudRefs.statusFrame.BorderSizePixel = 0
        hudRefs.statusFrame.Parent = hudRefs.screenGui

        local statusCorner = Instance.new("UICorner")
        statusCorner.CornerRadius = UDim.new(0.05, 0)
        statusCorner.Parent = hudRefs.statusFrame

        local statusConstraint = Instance.new("UISizeConstraint")
        statusConstraint.MinSize = Vector2.new(280, 200)
        statusConstraint.Parent = hudRefs.statusFrame

        hudRefs.moneyLabel = Instance.new("TextLabel")
        hudRefs.moneyLabel.Name = "MoneyLabel"
        hudRefs.moneyLabel.BackgroundTransparency = 1
        hudRefs.moneyLabel.AnchorPoint = Vector2.new(0, 0)
        hudRefs.moneyLabel.Position = UDim2.new(0.04, 0, 0.05, 0)
        hudRefs.moneyLabel.Size = UDim2.new(0.92, 0, 0.12, 0)
	hudRefs.moneyLabel.Font = Enum.Font.GothamBold
        hudRefs.moneyLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
        hudRefs.moneyLabel.TextSize = 20
        hudRefs.moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
        hudRefs.moneyLabel.Text = "$0"
        hudRefs.moneyLabel.Parent = hudRefs.statusFrame
        applyScaledText(hudRefs.moneyLabel, 16, 36)

        hudRefs.livesLabel = Instance.new("TextLabel")
        hudRefs.livesLabel.Name = "LivesLabel"
        hudRefs.livesLabel.BackgroundTransparency = 1
        hudRefs.livesLabel.AnchorPoint = Vector2.new(0, 0)
        hudRefs.livesLabel.Position = UDim2.new(0.04, 0, 0.24, 0)
        hudRefs.livesLabel.Size = UDim2.new(0.92, 0, 0.12, 0)
	hudRefs.livesLabel.Font = Enum.Font.Gotham
        hudRefs.livesLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
        hudRefs.livesLabel.TextSize = 18
        hudRefs.livesLabel.TextXAlignment = Enum.TextXAlignment.Left
        hudRefs.livesLabel.Text = "Lives: 0"
        hudRefs.livesLabel.Parent = hudRefs.statusFrame
        applyScaledText(hudRefs.livesLabel, 14, 32)

        hudRefs.waveLabel = Instance.new("TextLabel")
        hudRefs.waveLabel.Name = "WaveLabel"
        hudRefs.waveLabel.BackgroundTransparency = 1
        hudRefs.waveLabel.AnchorPoint = Vector2.new(0, 0)
        hudRefs.waveLabel.Position = UDim2.new(0.04, 0, 0.43, 0)
        hudRefs.waveLabel.Size = UDim2.new(0.92, 0, 0.12, 0)
	hudRefs.waveLabel.Font = Enum.Font.Gotham
        hudRefs.waveLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
        hudRefs.waveLabel.TextSize = 18
        hudRefs.waveLabel.TextXAlignment = Enum.TextXAlignment.Left
        hudRefs.waveLabel.Text = "Wave: 1"
        hudRefs.waveLabel.Parent = hudRefs.statusFrame
        applyScaledText(hudRefs.waveLabel, 14, 32)

        towerTotalsUi.playerLabel = Instance.new("TextLabel")
        towerTotalsUi.playerLabel.Name = "PlayerTowerTotal"
        towerTotalsUi.playerLabel.BackgroundTransparency = 1
        towerTotalsUi.playerLabel.AnchorPoint = Vector2.new(0, 0)
        towerTotalsUi.playerLabel.Position = UDim2.new(0.04, 0, 0.62, 0)
        towerTotalsUi.playerLabel.Size = UDim2.new(0.92, 0, 0.1, 0)
        towerTotalsUi.playerLabel.Font = Enum.Font.Gotham
        towerTotalsUi.playerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerTotalsUi.playerLabel.TextSize = 18
        towerTotalsUi.playerLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerTotalsUi.playerLabel.Text = "Your Towers: 0 / ∞"
        towerTotalsUi.playerLabel.Parent = hudRefs.statusFrame
        applyScaledText(towerTotalsUi.playerLabel, 12, 28)

        towerTotalsUi.teamLabel = Instance.new("TextLabel")
        towerTotalsUi.teamLabel.Name = "TeamTowerTotal"
        towerTotalsUi.teamLabel.BackgroundTransparency = 1
        towerTotalsUi.teamLabel.AnchorPoint = Vector2.new(0, 0)
        towerTotalsUi.teamLabel.Position = UDim2.new(0.04, 0, 0.76, 0)
        towerTotalsUi.teamLabel.Size = UDim2.new(0.92, 0, 0.1, 0)
        towerTotalsUi.teamLabel.Font = Enum.Font.Gotham
        towerTotalsUi.teamLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerTotalsUi.teamLabel.TextSize = 18
        towerTotalsUi.teamLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerTotalsUi.teamLabel.Text = "Team Towers: 0 / ∞"
        towerTotalsUi.teamLabel.Parent = hudRefs.statusFrame
        applyScaledText(towerTotalsUi.teamLabel, 12, 28)

        hudRefs.preRoundCountdownLabel = Instance.new("TextLabel")
        hudRefs.preRoundCountdownLabel.Name = "CountdownLabel"
        hudRefs.preRoundCountdownLabel.BackgroundTransparency = 1
        hudRefs.preRoundCountdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        hudRefs.preRoundCountdownLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
        hudRefs.preRoundCountdownLabel.Size = UDim2.new(0.5, 0, 0.12, 0)
        hudRefs.preRoundCountdownLabel.Font = Enum.Font.GothamBold
        hudRefs.preRoundCountdownLabel.TextSize = 18
        hudRefs.preRoundCountdownLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
        hudRefs.preRoundCountdownLabel.TextXAlignment = Enum.TextXAlignment.Center
        hudRefs.preRoundCountdownLabel.TextYAlignment = Enum.TextYAlignment.Center
        hudRefs.preRoundCountdownLabel.Text = ""
        hudRefs.preRoundCountdownLabel.Visible = false
        hudRefs.preRoundCountdownLabel.ZIndex = 10
        hudRefs.preRoundCountdownLabel.Parent = hudRefs.screenGui
        applyScaledText(hudRefs.preRoundCountdownLabel, 18, 48)

        if not waveSkipUi.button then
                waveSkipUi.button = Instance.new("TextButton")
                waveSkipUi.button.Name = "SkipWaveButton"
                waveSkipUi.button.AnchorPoint = Vector2.new(0.5, 0)
                waveSkipUi.button.Position = waveSkipUi.hiddenPosition
                waveSkipUi.button.Size = UDim2.new(0.26, 0, 0.085, 0)
                waveSkipUi.button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                waveSkipUi.button.BackgroundTransparency = 0.08
                waveSkipUi.button.BorderSizePixel = 0
                waveSkipUi.button.Text = "Skip Wave"
                waveSkipUi.button.Font = Enum.Font.GothamBold
                waveSkipUi.button.TextColor3 = Color3.new(1, 1, 1)
                waveSkipUi.button.TextXAlignment = Enum.TextXAlignment.Center
                waveSkipUi.button.TextYAlignment = Enum.TextYAlignment.Center
                waveSkipUi.button.Visible = false
                waveSkipUi.button.AutoButtonColor = true
                waveSkipUi.button.ZIndex = 12
                waveSkipUi.button.Parent = hudRefs.screenGui
                applyScaledText(waveSkipUi.button, 18, 44)

                local skipCorner = Instance.new("UICorner")
                skipCorner.CornerRadius = UDim.new(0.06, 0)
                skipCorner.Parent = waveSkipUi.button

                waveSkipUi.button.MouseButton1Click:Connect(function()
                        if waveSkipUi.requestPending then
                                return
                        end
                        if not waveSkipUi.offerActive then
                                return
                        end
                        if not remotes.RequestWaveSkip then
                                return
                        end

                        waveSkipUi.requestPending = true
                        waveSkipUi.button.Active = false
                        waveSkipUi.button.AutoButtonColor = false
                        waveSkipUi.button.Text = "Requesting..."
                        remotes.RequestWaveSkip:FireServer()
                end)
        end

        towerDetailsUi.frame = Instance.new("Frame")
        towerDetailsUi.frame.Name = "TowerDetails"
        towerDetailsUi.frame.AnchorPoint = Vector2.new(1, 0.5)
        towerDetailsUi.frame.Size = UDim2.new(0.26, 0, 0.34, 0)
        towerDetailsUi.frame.Position = UDim2.new(0.98, 0, 0.5, 0)
        towerDetailsUi.frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        towerDetailsUi.frame.BackgroundTransparency = 0.1
        towerDetailsUi.frame.BorderSizePixel = 0
        towerDetailsUi.frame.Visible = false
        towerDetailsUi.frame.Parent = hudRefs.screenGui

        local detailsCorner = Instance.new("UICorner")
        detailsCorner.CornerRadius = UDim.new(0.05, 0)
	detailsCorner.Parent = towerDetailsUi.frame

        towerDetailsUi.nameLabel = Instance.new("TextLabel")
        towerDetailsUi.nameLabel.Name = "TowerNameLabel"
        towerDetailsUi.nameLabel.BackgroundTransparency = 1
        towerDetailsUi.nameLabel.AnchorPoint = Vector2.new(0, 0)
        towerDetailsUi.nameLabel.Position = UDim2.new(0.05, 0, 0.08, 0)
        towerDetailsUi.nameLabel.Size = UDim2.new(0.9, 0, 0.16, 0)
        towerDetailsUi.nameLabel.Font = Enum.Font.GothamBold
        towerDetailsUi.nameLabel.TextColor3 = Color3.new(1, 1, 1)
        towerDetailsUi.nameLabel.TextSize = 20
        towerDetailsUi.nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerDetailsUi.nameLabel.Text = "Tower"
        towerDetailsUi.nameLabel.Parent = towerDetailsUi.frame
        applyScaledText(towerDetailsUi.nameLabel, 16, 36)

        towerDetailsUi.levelLabel = Instance.new("TextLabel")
        towerDetailsUi.levelLabel.Name = "TowerLevelLabel"
        towerDetailsUi.levelLabel.BackgroundTransparency = 1
        towerDetailsUi.levelLabel.AnchorPoint = Vector2.new(0, 0)
        towerDetailsUi.levelLabel.Position = UDim2.new(0.05, 0, 0.26, 0)
        towerDetailsUi.levelLabel.Size = UDim2.new(0.9, 0, 0.12, 0)
        towerDetailsUi.levelLabel.Font = Enum.Font.Gotham
        towerDetailsUi.levelLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerDetailsUi.levelLabel.TextSize = 16
        towerDetailsUi.levelLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerDetailsUi.levelLabel.Text = "Level: 1"
        towerDetailsUi.levelLabel.Parent = towerDetailsUi.frame
        applyScaledText(towerDetailsUi.levelLabel, 14, 30)

        towerDetailsUi.statsLabel = Instance.new("TextLabel")
        towerDetailsUi.statsLabel.Name = "TowerStatsLabel"
        towerDetailsUi.statsLabel.BackgroundTransparency = 1
        towerDetailsUi.statsLabel.AnchorPoint = Vector2.new(0, 0)
        towerDetailsUi.statsLabel.Position = UDim2.new(0.05, 0, 0.4, 0)
        towerDetailsUi.statsLabel.Size = UDim2.new(0.9, 0, 0.24, 0)
        towerDetailsUi.statsLabel.Font = Enum.Font.Gotham
        towerDetailsUi.statsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerDetailsUi.statsLabel.TextSize = 16
        towerDetailsUi.statsLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerDetailsUi.statsLabel.TextYAlignment = Enum.TextYAlignment.Top
        towerDetailsUi.statsLabel.TextWrapped = true
        towerDetailsUi.statsLabel.Text = ""
        towerDetailsUi.statsLabel.Parent = towerDetailsUi.frame
        applyScaledText(towerDetailsUi.statsLabel, 12, 26)

        towerDetailsUi.ownershipLabel = Instance.new("TextLabel")
        towerDetailsUi.ownershipLabel.Name = "OwnershipLabel"
        towerDetailsUi.ownershipLabel.BackgroundTransparency = 1
        towerDetailsUi.ownershipLabel.AnchorPoint = Vector2.new(0, 0)
        towerDetailsUi.ownershipLabel.Position = UDim2.new(0.05, 0, 0.64, 0)
        towerDetailsUi.ownershipLabel.Size = UDim2.new(0.9, 0, 0.08, 0)
        towerDetailsUi.ownershipLabel.Font = Enum.Font.Gotham
        towerDetailsUi.ownershipLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerDetailsUi.ownershipLabel.TextSize = 16
        towerDetailsUi.ownershipLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerDetailsUi.ownershipLabel.Text = "Owner"
        towerDetailsUi.ownershipLabel.Parent = towerDetailsUi.frame
        applyScaledText(towerDetailsUi.ownershipLabel, 12, 26)

        towerDetailsUi.upgradeDescriptionLabel = Instance.new("TextLabel")
        towerDetailsUi.upgradeDescriptionLabel.Name = "UpgradeDescriptionLabel"
        towerDetailsUi.upgradeDescriptionLabel.BackgroundTransparency = 1
        towerDetailsUi.upgradeDescriptionLabel.AnchorPoint = Vector2.new(0, 0)
        towerDetailsUi.upgradeDescriptionLabel.Position = UDim2.new(0.05, 0, 0.72, 0)
        towerDetailsUi.upgradeDescriptionLabel.Size = UDim2.new(0.9, 0, 0.12, 0)
        towerDetailsUi.upgradeDescriptionLabel.Font = Enum.Font.Gotham
        towerDetailsUi.upgradeDescriptionLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerDetailsUi.upgradeDescriptionLabel.TextSize = 14
        towerDetailsUi.upgradeDescriptionLabel.TextWrapped = true
        towerDetailsUi.upgradeDescriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerDetailsUi.upgradeDescriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
        towerDetailsUi.upgradeDescriptionLabel.Text = ""
        towerDetailsUi.upgradeDescriptionLabel.Parent = towerDetailsUi.frame
        applyScaledText(towerDetailsUi.upgradeDescriptionLabel, 12, 24)

        towerDetailsUi.upgradeButton = Instance.new("TextButton")
        towerDetailsUi.upgradeButton.Name = "UpgradeButton"
        towerDetailsUi.upgradeButton.Size = UDim2.new(0.44, 0, 0.14, 0)
        towerDetailsUi.upgradeButton.AnchorPoint = Vector2.new(0, 1)
        towerDetailsUi.upgradeButton.Position = UDim2.new(0.05, 0, 0.98, 0)
        towerDetailsUi.upgradeButton.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
        towerDetailsUi.upgradeButton.BorderSizePixel = 0
        towerDetailsUi.upgradeButton.Font = Enum.Font.GothamBold
        towerDetailsUi.upgradeButton.TextSize = 16
        towerDetailsUi.upgradeButton.TextColor3 = Color3.new(1, 1, 1)
        towerDetailsUi.upgradeButton.Text = "Upgrade"
        towerDetailsUi.upgradeButton.AutoButtonColor = true
        towerDetailsUi.upgradeButton.Visible = false
        towerDetailsUi.upgradeButton.Parent = towerDetailsUi.frame
        applyScaledText(towerDetailsUi.upgradeButton, 14, 30)

	towerDetailsUi.upgradeButtonOriginalColor = towerDetailsUi.upgradeButton.BackgroundColor3
	towerDetailsUi.upgradeButtonOriginalTextColor = towerDetailsUi.upgradeButton.TextColor3
	towerDetailsUi.upgradeButtonOriginalBackgroundTransparency = towerDetailsUi.upgradeButton.BackgroundTransparency
	towerDetailsUi.upgradeButtonOriginalTextTransparency = towerDetailsUi.upgradeButton.TextTransparency
	towerDetailsUi.upgradeButtonOriginalAutoButtonColor = towerDetailsUi.upgradeButton.AutoButtonColor

        towerDetailsUi.upgradeButton.MouseButton1Click:Connect(function()
                local tower = selectionState.tower
                if tower then
                        remotes.TowerUpgradeRequested:FireServer(tower)
                end
        end)

        towerDetailsUi.sellButton = Instance.new("TextButton")
        towerDetailsUi.sellButton.Name = "SellButton"
        towerDetailsUi.sellButton.Size = UDim2.new(0.44, 0, 0.14, 0)
        towerDetailsUi.sellButton.AnchorPoint = Vector2.new(1, 1)
        towerDetailsUi.sellButton.Position = UDim2.new(0.95, 0, 0.98, 0)
        towerDetailsUi.sellButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
        towerDetailsUi.sellButton.BorderSizePixel = 0
        towerDetailsUi.sellButton.Font = Enum.Font.GothamBold
        towerDetailsUi.sellButton.TextSize = 16
        towerDetailsUi.sellButton.TextColor3 = Color3.new(1, 1, 1)
        towerDetailsUi.sellButton.Text = "Sell"
        towerDetailsUi.sellButton.AutoButtonColor = true
        towerDetailsUi.sellButton.Visible = false
        towerDetailsUi.sellButton.Parent = towerDetailsUi.frame
        applyScaledText(towerDetailsUi.sellButton, 14, 30)

	towerDetailsUi.sellButtonOriginalAutoButtonColor = towerDetailsUi.sellButton.AutoButtonColor

        towerDetailsUi.sellButton.MouseButton1Click:Connect(function()
                local tower = selectionState.tower
                if tower then
                        remotes.TowerSellRequested:FireServer(tower)
                end
        end)

        local function applyHudConstraints()
                if not hudRefs.screenGui then
                        return
                end

                local screenSize = hudRefs.screenGui.AbsoluteSize
                local screenWidth = screenSize.X > 0 and screenSize.X or 1920
                local screenHeight = screenSize.Y > 0 and screenSize.Y or 1080

                if hudRefs.shopFrame then
                        local aspect = hudRefs.shopFrame:FindFirstChild("AspectConstraint")
                        if not aspect then
                                aspect = Instance.new("UIAspectRatioConstraint")
                                aspect.Name = "AspectConstraint"
                                aspect.Parent = hudRefs.shopFrame
                        end
                        local widthScale = math.clamp(0.55 + (screenWidth / 1920) * 0.25, 0.6, 0.85)
                        local heightScale = math.clamp(0.18 + (screenHeight / 1080) * 0.05, 0.18, 0.28)
                        hudRefs.shopFrame.Size = UDim2.new(widthScale, 0, heightScale, 0)
                        aspect.AspectRatio = widthScale / math.max(heightScale, 0.01)
                        aspect.DominantAxis = Enum.DominantAxis.Width

                        local sizeConstraint = hudRefs.shopFrame:FindFirstChild("SizeConstraint")
                        if not sizeConstraint then
                                sizeConstraint = Instance.new("UISizeConstraint")
                                sizeConstraint.Name = "SizeConstraint"
                                sizeConstraint.Parent = hudRefs.shopFrame
                        end
                        sizeConstraint.MinSize = Vector2.new(math.max(screenSize.X * 0.35, 420), math.max(screenSize.Y * 0.1, 120))
                end

                if towerDetailsUi.frame then
                        local aspect = towerDetailsUi.frame:FindFirstChild("AspectConstraint")
                        if not aspect then
                                aspect = Instance.new("UIAspectRatioConstraint")
                                aspect.Name = "AspectConstraint"
                                aspect.Parent = towerDetailsUi.frame
                        end
                        local towerWidthScale = math.clamp(0.22 + (screenWidth / 3840) * 0.04, 0.22, 0.26)
                        towerDetailsUi.frame.Size = UDim2.new(towerWidthScale, 0, 0.34, 0)
                        aspect.AspectRatio = 0.76
                        aspect.DominantAxis = Enum.DominantAxis.Height

                        local sizeConstraint = towerDetailsUi.frame:FindFirstChild("SizeConstraint")
                        if not sizeConstraint then
                                sizeConstraint = Instance.new("UISizeConstraint")
                                sizeConstraint.Name = "SizeConstraint"
                                sizeConstraint.Parent = towerDetailsUi.frame
                        end
                        sizeConstraint.MinSize = Vector2.new(math.max(screenSize.X * 0.16, 280), math.max(screenSize.Y * 0.16, 220))
                end
        end

        applyHudConstraints()
        task.defer(applyHudConstraints)
        hudRefs.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyHudConstraints)

	for _, button in pairs(shopSlotButtons) do
		connectShopButton(button)
	end

        applyLoadoutToShop()
        updateOverallTowerTotals()

        return hudRefs.screenGui
end

local function showTowerSelection()
	local gui = createSelectionGui()
	if not gui then
		return
	end

        for i = 1, LOADOUT_SLOT_COUNT do
                loadoutSelection[i] = nil
                if selectionUi.slotButtons[i] then
                        selectionUi.slotButtons[i]:SetAttribute("TowerType", nil)
                end
        end

        populateTowerSelectionButtons()
        for index = 1, LOADOUT_SLOT_COUNT do
                updateSelectionSlotDisplay(index)
        end

	setActiveSelectionSlot(findFirstEmptySlot() or 1)
	updateConfirmButtonState()
	gui.Enabled = true
	applyLoadoutToShop()
end

local function clearSelection(reason)
        local current = selectionState.tower
        if current then
                if reason == "destroyed" then
                        selectionState.lastRemoved = current
                else
                        selectionState.lastRemoved = nil
                end
        else
                selectionState.lastRemoved = nil
        end

        selectionState.tower = nil
        disconnectSelectedConnections()
        destroyRangeIndicator()
        if towerDetailsUi.frame then
                towerDetailsUi.frame.Visible = false
        end
	if towerDetailsUi.upgradeDescriptionLabel then
		towerDetailsUi.upgradeDescriptionLabel.Text = ""
	end
        if towerDetailsUi.sellButton then
                towerDetailsUi.sellButton.Visible = false
        end

        refreshBoostDisplayVisibility()
end

local function selectTower(towerModel)
        if not towerModel then
                clearSelection()
                return
        end

        if selectionState.tower == towerModel then
                updateTowerDetails(towerModel)
                refreshBoostDisplayVisibility()
                return
        end

        clearSelection()
        selectionState.tower = towerModel
        selectionState.lastRemoved = nil
        updateTowerDetails(towerModel)
        refreshBoostDisplayVisibility()

        selectionState.connections = {
                towerModel.AncestryChanged:Connect(function(_, parent)
                        if not parent then
                                clearSelection("destroyed")
                        end
                end),
                towerModel:GetAttributeChangedSignal("Level"):Connect(function()
                        if selectionState.tower == towerModel then
                                updateTowerDetails(towerModel)
                        end
                end),
                towerModel:GetAttributeChangedSignal("Range"):Connect(function()
                        if selectionState.tower == towerModel then
                                updateTowerDetails(towerModel)
                        end
                end),
                towerModel:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
                        if selectionState.tower == towerModel then
                                updateTowerDetails(towerModel)
                        end
                end),
                towerModel:GetAttributeChangedSignal("SellValue"):Connect(function()
                        if selectionState.tower == towerModel then
                                updateTowerDetails(towerModel)
                        end
                end)
        }
end

local function evaluatePlacement(rayResult)
        if not placingTowerType or not rayResult then
                return false
        end

        return placementValidation:evaluatePlacement(placingTowerType, rayResult)
end

local function updatePreview()
	if not placingTowerType or not previewPart then
		placementValid = false
		return
	end

	local unitRay = mouse.UnitRay
        local rayResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, createRaycastParams())

        if rayResult then
                local valid, resolvedPosition = evaluatePlacement(rayResult)
                placementValid = valid and true or false

                local targetPosition = resolvedPosition or rayResult.Position
                if targetPosition then
                        previewPart.CFrame = CFrame.new(
                                Vector3.new(
                                        targetPosition.X,
                                        targetPosition.Y + previewPart.Size.Y / 2,
                                        targetPosition.Z
                                )
                        )
                end

                local config = towerConfigs[placingTowerType]
                if hudRefs.previewRangeRing and hudRefs.previewRangeAdornment and config and config.Range then
                        local ringBase
                        if resolvedPosition then
                                ringBase = resolvedPosition
                        else
                                local surfaceResult = placementValidation:findPlacementSurface(rayResult.Position, placingTowerType)
                                if surfaceResult then
                                        ringBase = surfaceResult.Position
                                else
                                        ringBase = rayResult.Position
                                end
                        end

                        if ringBase then
                                ringBase = resolveRangeRingPosition(ringBase)
                                updateRangeRing(
                                        hudRefs.previewRangeRing,
                                        hudRefs.previewRangeAdornment,
                                        config.Range,
                                        Vector3.new(ringBase.X, ringBase.Y + 0.05, ringBase.Z)
                                )
                        end
                end

                local validColor = placementValid and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(255, 100, 100)
                previewPart.Color = validColor
                if hudRefs.previewRangeAdornment then
                        if placementValid then
                                hudRefs.previewRangeAdornment.Color3 = Color3.fromRGB(120, 220, 255)
                                hudRefs.previewRangeAdornment.Transparency = 0.45
                        else
                                hudRefs.previewRangeAdornment.Color3 = Color3.fromRGB(255, 150, 150)
                                hudRefs.previewRangeAdornment.Transparency = 0.6
                        end
                end
        else
                placementValid = false
                previewPart.Color = Color3.fromRGB(255, 100, 100)
                if hudRefs.previewRangeAdornment then
                        hudRefs.previewRangeAdornment.Color3 = Color3.fromRGB(255, 150, 150)
                        hudRefs.previewRangeAdornment.Transparency = 0.6
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

		if hoverUi.nameLabel then
			hoverUi.nameLabel.Text = displayName
		end

		if hoverUi.healthLabel then
			if currentHealth and typeof(maxHealth) == "number" then
				hoverUi.healthLabel.Text = string.format("HP: %d / %d", currentHealth, maxHealth)
			elseif currentHealth then
				hoverUi.healthLabel.Text = string.format("HP: %d", currentHealth)
			else
				hoverUi.healthLabel.Text = "HP: ???"
			end
		elseif hoverUi.combinedLabel then
			if currentHealth and typeof(maxHealth) == "number" then
				hoverUi.combinedLabel.Text = string.format("%s - HP: %d / %d", displayName, currentHealth, maxHealth)
			elseif currentHealth then
				hoverUi.combinedLabel.Text = string.format("%s - HP: %d", displayName, currentHealth)
			else
				hoverUi.combinedLabel.Text = string.format("%s - HP: ???", displayName)
			end
		end

                local mousePosition = Vector2.new(mouse.X, mouse.Y)
                local offsetX = guiObject:GetAttribute("OffsetX") or 16
                local offsetY = guiObject:GetAttribute("OffsetY") or 16
                local camera = workspace.CurrentCamera
                local viewport = camera and camera.ViewportSize or playerGui.AbsoluteSize
                local relativeX = 0
                local relativeY = 0
                if viewport.X > 0 and viewport.Y > 0 then
                        relativeX = math.clamp((mousePosition.X + offsetX) / viewport.X, 0, 1)
                        relativeY = math.clamp((mousePosition.Y + offsetY) / viewport.Y, 0, 1)
                end
                guiObject.Position = UDim2.new(relativeX, 0, relativeY, 0)
                guiObject.Visible = true
	else
		if hoverUi.frame and hoverUi.frame:IsA("GuiObject") then
			hoverUi.frame.Visible = false
		end
        end
end

local towerCountsEvent = remotes:FindFirstChild("TowerCountsUpdated")
if towerCountsEvent and towerCountsEvent:IsA("RemoteEvent") then
        towerCountsEvent.OnClientEvent:Connect(function(payload)
                if typeof(payload) == "table" then
                        towerTotalsUi.snapshot = payload
                else
                        towerTotalsUi.snapshot = nil
                end

                updateOverallTowerTotals()
                updateAllShopSlotCounts()
        end)
end

if remotes:FindFirstChild("MoneyChanged") then
        remotes.MoneyChanged.OnClientEvent:Connect(function(amount)
                currentMoney = math.max(0, math.floor((amount or 0) + 0.5))
                if hudRefs.moneyLabel then
                        hudRefs.moneyLabel.Text = string.format("$%d", currentMoney)
                end
                local tower = selectionState.tower
                if tower then
                        updateTowerDetails(tower)
                end
                updateStartButtonVisual()
        end)
end

if remotes:FindFirstChild("LivesChanged") then
	remotes.LivesChanged.OnClientEvent:Connect(function(lives)
		if hudRefs.livesLabel then
			hudRefs.livesLabel.Text = string.format("Lives: %d", math.floor(lives or 0))
		end
	end)
end

if remotes:FindFirstChild("WaveStarted") then
        remotes.WaveStarted.OnClientEvent:Connect(function(waveNumber)
                if hudRefs.waveLabel then
                        hudRefs.waveLabel.Text = string.format("Wave: %d", waveNumber or 1)
                end
                gameEnded = false
                if hudRefs.preRoundCountdownLabel then
                        hudRefs.preRoundCountdownLabel.Visible = false
                        hudRefs.preRoundCountdownLabel.Text = ""
                end
                hideWaveSkipButton({ Reason = "advance" })
        end)
end

if remotes:FindFirstChild("WaveSkipOfferUpdated") then
        remotes.WaveSkipOfferUpdated.OnClientEvent:Connect(function(payload)
                if lobbyUi.phase ~= "inRound" then
                        resetWaveSkipButton()
                        return
                end

                if typeof(payload) ~= "table" then
                        resetWaveSkipButton()
                        return
                end

                if payload.Active then
                        showWaveSkipButton(payload)
                else
                        hideWaveSkipButton(payload)
                end
        end)
end

if remotes:FindFirstChild("GameEnded") then
        remotes.GameEnded.OnClientEvent:Connect(function(victory)
                gameEnded = true
                lastVictoryState = victory
                cancelPlacement()
                if hudRefs.preRoundCountdownLabel then
                        hudRefs.preRoundCountdownLabel.Visible = false
                        hudRefs.preRoundCountdownLabel.Text = ""
                end
                if victory ~= nil then
                        hideWaveSkipButton({ Reason = victory and "victory" or "gameOver" })
                else
                        hideWaveSkipButton({ Reason = "gameOver" })
                end
        end)
end

if remotes:FindFirstChild("GameRestarted") then
        remotes.GameRestarted.OnClientEvent:Connect(function()
                gameEnded = false
                lastVictoryState = nil
                lobbyUi.phase = "lobby"
                updateInterfaceVisibility()
                clearSelection()
                showTowerSelection()
        end)
end

if remotes:FindFirstChild("LobbyStateUpdated") then
        remotes.LobbyStateUpdated.OnClientEvent:Connect(function(state)
                applyLobbyState(state)
        end)
end

if remotes:FindFirstChild("MapSelectionStarted") then
        remotes.MapSelectionStarted.OnClientEvent:Connect(function(payload)
                lobbyUi.phase = "mapSelection"
                updateInterfaceVisibility()
                showMapSelection(payload and payload.Options or {}, payload and payload.TotalPlayers)
        end)
end

if remotes:FindFirstChild("MapVoteUpdated") then
        remotes.MapVoteUpdated.OnClientEvent:Connect(function(payload)
                updateMapVoteCounts(payload and payload.Counts, payload and payload.TotalPlayers)
        end)
end

if remotes:FindFirstChild("MapSelectionFinalized") then
        remotes.MapSelectionFinalized.OnClientEvent:Connect(function(payload)
                finalizeMapSelection(payload and payload.SelectedIndex, payload and payload.Option)
        end)
end

initializeTowerBaseTracking()
setTowerBaseVisibility(false)

if remotes:FindFirstChild("RoundSetupComplete") then
        remotes.RoundSetupComplete.OnClientEvent:Connect(function(payload)
                lobbyUi.phase = "inRound"
                updateInterfaceVisibility()
                if mapSelectionState.gui then
                        mapSelectionState.gui.Enabled = false
                end
                createGui()
                applyLoadoutToShop()
                resetWaveSkipButton()
                if payload and payload.MapName and hudRefs.preRoundCountdownLabel then
                        hudRefs.preRoundCountdownLabel.Text = string.format("%s selected", payload.MapName)
                        hudRefs.preRoundCountdownLabel.Visible = true
                end
        end)
end

if remotes:FindFirstChild("RoundCountdownUpdated") then
        remotes.RoundCountdownUpdated.OnClientEvent:Connect(function(payload)
                if not hudRefs.preRoundCountdownLabel then
                        return
                end

                local remaining = payload and payload.Remaining or 0
                if remaining and remaining > 0 then
                        hudRefs.preRoundCountdownLabel.Text = string.format("Round starts in %ds", remaining)
                        hudRefs.preRoundCountdownLabel.Visible = true
                else
                        hudRefs.preRoundCountdownLabel.Visible = false
                        hudRefs.preRoundCountdownLabel.Text = ""
                end
        end)
end

createGui()
updateInterfaceVisibility()
showTowerSelection()

UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
                return
        end

        local slotIndex = SLOT_KEY_CODES[input.KeyCode]
        if slotIndex then
                if selectionUi.screenGui and selectionUi.screenGui.Enabled then
                        setActiveSelectionSlot(math.clamp(slotIndex, 1, LOADOUT_SLOT_COUNT))
                elseif lobbyUi.phase == "inRound" then
                        local button = shopSlotButtons[slotIndex]
                        if button and button.Active then
                                local towerType = getTowerTypeForButton(button)
                                if towerType then
                                        beginPlacement(towerType)
                                end
                        end
                end
                return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                if lobbyUi.phase ~= "inRound" then
                        return
                end
		if placingTowerType then
			local unitRay = mouse.UnitRay
			local rayResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, createRaycastParams())
                        if rayResult then
                                local valid, placementPosition = evaluatePlacement(rayResult)
                                if valid and placementPosition then
                                        remotes.TowerPlaced:FireServer(placingTowerType, placementPosition)
                                        cancelPlacement()
                                end
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
                if lobbyUi.phase ~= "inRound" then
                        return
                end
                if placingTowerType then
                        cancelPlacement()
                else
                        local tower = selectionState.tower
                        if tower and not placingTowerType then
                                local ownerId = tower:GetAttribute("OwnerUserId")
                                if ownerId == player.UserId and not gameEnded then
                                        remotes.TowerSellRequested:FireServer(tower)
                                end
                        end
                end
        elseif input.KeyCode == Enum.KeyCode.E then
                if lobbyUi.phase ~= "inRound" then
                        return
                end
                if not placingTowerType then
                        local tower = selectionState.tower
                        if tower then
                                local ownerId = tower:GetAttribute("OwnerUserId")
                                if ownerId == player.UserId and not gameEnded then
                                        remotes.TowerUpgradeRequested:FireServer(tower)
                                end
                        end
                end
        end
end)

remotes.TowerUpgraded.OnClientEvent:Connect(function(towerModel, _, previousModel)
        if not towerModel then
                return
        end

        local currentTower = selectionState.tower
        if currentTower == towerModel or currentTower == previousModel then
                selectTower(towerModel)
                return
        end

        local lastRemoved = selectionState.lastRemoved
        if lastRemoved and (lastRemoved == previousModel or lastRemoved == towerModel) then
                selectTower(towerModel)
        end
end)

if remotes:FindFirstChild("SplashFired") then
        remotes.SplashFired.OnClientEvent:Connect(function(position, radius, color)
                showExplosion(position, radius, color)
        end)
end

if remotes:FindFirstChild("TowerStunPulse") then
        remotes.TowerStunPulse.OnClientEvent:Connect(function(position, radius, color)
                showExplosion(position, radius, color or Color3.fromRGB(140, 225, 255))
        end)
end

RunService.RenderStepped:Connect(function()
        updatePreview()
        updateEnemyHover()
        local tower = selectionState.tower
        if tower and (not tower.Parent) then
                clearSelection("destroyed")
        end
end)
