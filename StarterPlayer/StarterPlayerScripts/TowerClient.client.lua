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
local rangeRing
local rangeRingAdornment
local previewRangeRing
local previewRangeAdornment
local selectedTowerConnections = {}
local currentMoney = 0
local gameEnded = false
local lastVictoryState
local shopButtonConnections = {}
local shopSlotButtons = {}
local shopSlotOriginalText = {}
local shopSlotPriceLabels = {}
local shopSlotCountLabels = {}
local beginPlacement

local towerDetailsFrame
local towerNameLabel
local towerLevelLabel
local towerStatsLabel
local ownershipLabel
local upgradeDescriptionLabel
local upgradeButton
local sellButton
local upgradeButtonOriginalColor
local upgradeButtonOriginalTextColor
local upgradeButtonOriginalBackgroundTransparency
local upgradeButtonOriginalTextTransparency
local upgradeButtonOriginalAutoButtonColor
local sellButtonOriginalAutoButtonColor
local GREY_COLOR = Color3.new(0.5, 0.5, 0.5)
local READY_COLOR = Color3.fromRGB(120, 220, 160)
local NOT_READY_COLOR = Color3.fromRGB(220, 140, 120)

local playerTowerTotalLabel
local teamTowerTotalLabel
local towerCountSnapshot

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

local selectionScreenGui
local selectionFrame
local selectionTowerList
local selectionSlotButtons = {}
local selectionSlotOriginalText = {}
local selectionActiveSlot
local loadoutSelection = {}
local lastSyncedLoadout

local lobbyCountdownLabel
local readyButton
local leaveButton
local roundButtons = {}
local lobbyStatusLabel
local lobbyPhase = "lobby"
local lobbyStateSnapshot
local lobbyReadyState = false
local lobbyRoundList
local loadoutLocked = false

local mapSelectionGui
local mapSelectionFrame
local mapOptionButtons = {}
local mapVoteLabels = {}
local mapVoteTotalPlayers = 0
local mapSelectionStatusLabel
local mapOptionsContainer

local preRoundCountdownLabel

local DEFAULT_PREVIEW_SIZE = Vector3.new(4, 1, 4)
local previewFootprintSize = DEFAULT_PREVIEW_SIZE
local footprintCache = {}
local RANGE_RING_HEIGHT = 0.05
local MAX_GROUND_RAYCAST_ATTEMPTS = 8
local PLACEMENT_EDGE_EPSILON = 0.01

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

local function getTowerCountEntry(towerType)
        if not towerType then
                return nil
        end

        if not towerCountSnapshot or typeof(towerCountSnapshot) ~= "table" then
                return nil
        end

        local towers = towerCountSnapshot.Towers
        if not towers or typeof(towers) ~= "table" then
                return nil
        end

        return towers[towerType]
end

local function updateOverallTowerTotals()
        if not (playerTowerTotalLabel or teamTowerTotalLabel) then
                return
        end

        local totalInfo = towerCountSnapshot and towerCountSnapshot.Total

        local playerText = formatCountLimit(totalInfo and totalInfo.PlayerCount, totalInfo and totalInfo.PlayerLimit)
        if playerTowerTotalLabel then
                playerTowerTotalLabel.Text = string.format("Your Towers: %s", playerText)
        end

        if teamTowerTotalLabel then
                local teamText = formatCountLimit(totalInfo and totalInfo.GlobalCount, totalInfo and totalInfo.GlobalLimit)
                teamTowerTotalLabel.Text = string.format("Team Towers: %s", teamText)
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
        for _, button in pairs(selectionSlotButtons) do
                if button and button:IsA("GuiButton") then
                        button.AutoButtonColor = not loadoutLocked
                end
        end

        if selectionTowerList then
                if selectionTowerList:IsA("ScrollingFrame") then
                        selectionTowerList.Active = not loadoutLocked
                        selectionTowerList.ScrollingEnabled = not loadoutLocked
                end

                for _, child in ipairs(selectionTowerList:GetChildren()) do
                        if child:IsA("GuiButton") then
                                child.Active = not loadoutLocked
                                child.AutoButtonColor = not loadoutLocked
                        end
                end
        end
end

local function setLoadoutLocked(locked)
        locked = locked and true or false

        loadoutLocked = locked
        applyLoadoutLockState()
end

local function updateConfirmButtonState()
        syncLoadoutWithServer()

        local ready = hasAnySelectedTowers()

        if readyButton then
                readyButton.Active = ready
                readyButton.AutoButtonColor = ready
                readyButton.TextTransparency = ready and 0 or 0.35
        end

        if lobbyStatusLabel then
                if loadoutLocked then
                        lobbyStatusLabel.Text = "Loadout locked while you are joined to a round."
                elseif ready then
                        lobbyStatusLabel.Text = ""
                else
                        lobbyStatusLabel.Text = "Select at least one tower to join a round."
                end
        end
end

local function updateSelectionSlotDisplay(slotIndex)
	local button = selectionSlotButtons[slotIndex]
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
			button.Text = selectionSlotOriginalText[slotIndex] or "Empty Slot"
		end
	end

	button:SetAttribute("ActiveSlot", selectionActiveSlot == slotIndex)
end

local function setActiveSelectionSlot(slotIndex)
	if selectionActiveSlot == slotIndex then
		return
	end

	selectionActiveSlot = slotIndex

	for index in pairs(selectionSlotButtons) do
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
    if loadoutLocked then
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
    if loadoutLocked then
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
        if not selectionTowerList then
                return
        end

        for _, child in ipairs(selectionTowerList:GetChildren()) do
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
                        button.Parent = selectionTowerList
                        button:SetAttribute("TowerType", towerType)
                        button:SetAttribute("TowerClientGenerated", true)
                        local cost = tonumber(config.Cost) or 0
                        local displayName = config.Name or towerType
                        button.Text = string.format("%s\n$%d", displayName, cost)
                        applyScaledText(button, 12, 32)

                        button.MouseButton1Click:Connect(function()
                                local slotIndex = selectionActiveSlot or findFirstEmptySlot() or 1
                                assignTowerToSlot(slotIndex, towerType)
                        end)
                end
        end

        local layout = selectionTowerList:FindFirstChildWhichIsA("UIGridLayout")
        if layout then
                layout.CellSize = UDim2.new(0.48, 0, 0.22, 0)
        end

        applyLoadoutLockState()
end

local function createSelectionGui()
        if selectionScreenGui then
                return selectionScreenGui
        end

        selectionScreenGui = Instance.new("ScreenGui")
        selectionScreenGui.Name = "TowerLobbyUI"
        selectionScreenGui.ResetOnSpawn = false
        selectionScreenGui.IgnoreGuiInset = true
        selectionScreenGui.DisplayOrder = 5
        selectionScreenGui.Enabled = true
        selectionScreenGui.Parent = playerGui

        selectionFrame = Instance.new("Frame")
        selectionFrame.Name = "LobbyFrame"
        selectionFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        selectionFrame.Size = UDim2.fromScale(0.9, 0.85)
        selectionFrame.Position = UDim2.fromScale(0.5, 0.5)
        selectionFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        selectionFrame.BackgroundTransparency = 0.15
        selectionFrame.BorderSizePixel = 0
        selectionFrame.Parent = selectionScreenGui

        local frameCorner = Instance.new("UICorner")
        frameCorner.CornerRadius = UDim.new(0.03, 0)
        frameCorner.Parent = selectionFrame

        local frameConstraint = Instance.new("UIAspectRatioConstraint")
        frameConstraint.AspectRatio = 1140 / 520
        frameConstraint.DominantAxis = Enum.DominantAxis.Width
        frameConstraint.Parent = selectionFrame

        local frameSizeConstraint = Instance.new("UISizeConstraint")
        frameSizeConstraint.MinSize = Vector2.new(720, 420)
        frameSizeConstraint.Parent = selectionFrame

        local shopPanel = Instance.new("Frame")
        shopPanel.Name = "TowerShopPanel"
        shopPanel.AnchorPoint = Vector2.new(0, 0.5)
        shopPanel.Size = UDim2.new(0.6, 0, 0.78, 0)
        shopPanel.Position = UDim2.new(0.03, 0, 0.5, 0)
        shopPanel.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
        shopPanel.BackgroundTransparency = 0.05
        shopPanel.BorderSizePixel = 0
        shopPanel.Parent = selectionFrame

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

        selectionTowerList = Instance.new("ScrollingFrame")
        selectionTowerList.Name = "TowerList"
        selectionTowerList.BackgroundTransparency = 1
        selectionTowerList.BorderSizePixel = 0
        selectionTowerList.AnchorPoint = Vector2.new(0, 0)
        selectionTowerList.Size = UDim2.new(0.94, 0, 0.76, 0)
        selectionTowerList.Position = UDim2.new(0.03, 0, 0.18, 0)
        selectionTowerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        selectionTowerList.ScrollBarThickness = 8
        selectionTowerList.Parent = shopPanel

        local shopGrid = Instance.new("UIGridLayout")
        shopGrid.CellSize = UDim2.new(0.48, 0, 0.22, 0)
        shopGrid.CellPadding = UDim2.new(0.04, 0, 0.04, 0)
        shopGrid.FillDirection = Enum.FillDirection.Horizontal
        shopGrid.SortOrder = Enum.SortOrder.LayoutOrder
        shopGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
        shopGrid.Parent = selectionTowerList

        lobbyStatusLabel = Instance.new("TextLabel")
        lobbyStatusLabel.Name = "LobbyStatus"
        lobbyStatusLabel.AnchorPoint = Vector2.new(0, 1)
        lobbyStatusLabel.Size = UDim2.new(0.94, 0, 0.1, 0)
        lobbyStatusLabel.Position = UDim2.new(0.03, 0, 0.97, 0)
        lobbyStatusLabel.BackgroundTransparency = 1
        lobbyStatusLabel.Font = Enum.Font.Gotham
        lobbyStatusLabel.TextSize = 18
        lobbyStatusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        lobbyStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
        lobbyStatusLabel.Text = ""
        lobbyStatusLabel.Parent = shopPanel
        applyScaledText(lobbyStatusLabel, 14, 30)

        local roundPanel = Instance.new("Frame")
        roundPanel.Name = "RoundPanel"
        roundPanel.AnchorPoint = Vector2.new(1, 0)
        roundPanel.Size = UDim2.new(0.34, 0, 0.55, 0)
        roundPanel.Position = UDim2.new(0.99, 0, 0.05, 0)
        roundPanel.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
        roundPanel.BackgroundTransparency = 0.05
        roundPanel.BorderSizePixel = 0
        roundPanel.Parent = selectionFrame

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

        lobbyCountdownLabel = Instance.new("TextLabel")
        lobbyCountdownLabel.Name = "CountdownLabel"
        lobbyCountdownLabel.AnchorPoint = Vector2.new(0, 0)
        lobbyCountdownLabel.Size = UDim2.new(0.94, 0, 0.12, 0)
        lobbyCountdownLabel.Position = UDim2.new(0.03, 0, 0.24, 0)
        lobbyCountdownLabel.BackgroundTransparency = 1
        lobbyCountdownLabel.Font = Enum.Font.Gotham
        lobbyCountdownLabel.TextSize = 18
        lobbyCountdownLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
        lobbyCountdownLabel.TextXAlignment = Enum.TextXAlignment.Left
        lobbyCountdownLabel.TextYAlignment = Enum.TextYAlignment.Center
        lobbyCountdownLabel.Text = ""
        lobbyCountdownLabel.Parent = roundPanel
        applyScaledText(lobbyCountdownLabel, 14, 32)

        lobbyRoundList = Instance.new("ScrollingFrame")
        lobbyRoundList.Name = "RoundList"
        lobbyRoundList.AnchorPoint = Vector2.new(0, 0)
        lobbyRoundList.Size = UDim2.new(0.94, 0, 0.6, 0)
        lobbyRoundList.Position = UDim2.new(0.03, 0, 0.36, 0)
        lobbyRoundList.BackgroundTransparency = 1
        lobbyRoundList.BorderSizePixel = 0
        lobbyRoundList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        lobbyRoundList.ScrollBarThickness = 8
        lobbyRoundList.ScrollingDirection = Enum.ScrollingDirection.Y
        lobbyRoundList.Parent = roundPanel

        local roundLayout = Instance.new("UIListLayout")
        roundLayout.FillDirection = Enum.FillDirection.Vertical
        roundLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        roundLayout.VerticalAlignment = Enum.VerticalAlignment.Top
        roundLayout.SortOrder = Enum.SortOrder.LayoutOrder
        roundLayout.Padding = UDim.new(0.02, 0)
        roundLayout.Parent = lobbyRoundList

        local loadoutPanel = Instance.new("Frame")
        loadoutPanel.Name = "LoadoutPanel"
        loadoutPanel.AnchorPoint = Vector2.new(1, 0.5)
        loadoutPanel.Size = UDim2.new(0.34, 0, 0.3, 0)
        loadoutPanel.Position = UDim2.new(0.99, 0, 0.82, 0)
        loadoutPanel.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
        loadoutPanel.BackgroundTransparency = 0.05
        loadoutPanel.BorderSizePixel = 0
        loadoutPanel.Parent = selectionFrame

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

        selectionSlotButtons = {}
        selectionSlotOriginalText = {}
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
                selectionSlotButtons[i] = button
                selectionSlotOriginalText[i] = button.Text
                applyScaledText(button, 12, 28)

                button.MouseButton1Click:Connect(function()
                        if loadoutSelection[i] then
                                if loadoutLocked then
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

        readyButton = Instance.new("TextButton")
        readyButton.Name = "ReadyButton"
        readyButton.AnchorPoint = Vector2.new(0, 1)
        readyButton.Size = UDim2.new(0.47, 0, 0.26, 0)
        readyButton.Position = UDim2.new(0.03, 0, 0.97, 0)
        readyButton.BackgroundColor3 = Color3.fromRGB(70, 130, 90)
        readyButton.BorderSizePixel = 0
        readyButton.Font = Enum.Font.GothamBold
        readyButton.TextSize = 20
        readyButton.TextColor3 = Color3.new(1, 1, 1)
        readyButton.Text = "Ready Up"
        readyButton.AutoButtonColor = true
        readyButton.Parent = loadoutPanel
        applyScaledText(readyButton, 16, 36)

        readyButton.MouseButton1Click:Connect(function()
                if not remotes.RequestReadyStatus then
                        return
                end
                remotes.RequestReadyStatus:FireServer(not lobbyReadyState)
        end)

        leaveButton = Instance.new("TextButton")
        leaveButton.Name = "LeaveButton"
        leaveButton.AnchorPoint = Vector2.new(1, 1)
        leaveButton.Size = UDim2.new(0.47, 0, 0.26, 0)
        leaveButton.Position = UDim2.new(0.97, 0, 0.97, 0)
        leaveButton.BackgroundColor3 = Color3.fromRGB(150, 80, 80)
        leaveButton.BorderSizePixel = 0
        leaveButton.Font = Enum.Font.GothamBold
        leaveButton.TextSize = 20
        leaveButton.TextColor3 = Color3.new(1, 1, 1)
        leaveButton.Text = "Leave Round"
        leaveButton.AutoButtonColor = true
        leaveButton.Visible = false
        leaveButton.Parent = loadoutPanel
        applyScaledText(leaveButton, 16, 36)

        leaveButton.MouseButton1Click:Connect(function()
                if remotes.RequestLeaveRound then
                        remotes.RequestLeaveRound:FireServer()
                end
        end)

        populateTowerSelectionButtons()
        for index in pairs(selectionSlotButtons) do
                updateSelectionSlotDisplay(index)
        end
        setActiveSelectionSlot(findFirstEmptySlot() or 1)
        updateConfirmButtonState()
        applyLoadoutLockState()

        return selectionScreenGui
end

local function updateInterfaceVisibility()
        if selectionScreenGui then
                selectionScreenGui.Enabled = lobbyPhase == "lobby"
        end

        if mapSelectionGui then
                mapSelectionGui.Enabled = lobbyPhase == "mapSelection"
        end

        if screenGui then
                screenGui.Enabled = lobbyPhase == "inRound"
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
        if not selectionScreenGui then
                createSelectionGui()
        end

        if not lobbyRoundList then
                return
        end

        local existing = {}
        for index, round in ipairs(rounds or {}) do
                local roundKey = round.Key or tostring(index)
                existing[roundKey] = true

                local entry = roundButtons[roundKey]
                if not entry then
                        local frame = Instance.new("Frame")
                        frame.Name = string.format("Round%sEntry", roundKey)
                        frame.AnchorPoint = Vector2.new(0, 0)
                        frame.Size = UDim2.new(1, 0, 0.56, 0)
                        frame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
                        frame.BackgroundTransparency = 0.05
                        frame.BorderSizePixel = 0
                        frame.Parent = lobbyRoundList

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
                        roundButtons[roundKey] = entry
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

        for key, entry in pairs(roundButtons) do
                if not existing[key] then
                        if entry.Frame then
                                entry.Frame:Destroy()
                        end
                        roundButtons[key] = nil
                end
        end
end

local function applyLobbyState(state)
        lobbyStateSnapshot = state
        lobbyPhase = state and state.Phase or lobbyPhase
        lobbyReadyState = state and state.Player and state.Player.Ready or false

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

        if lobbyPhase ~= "lobby" then
                return
        end

        createSelectionGui()

        updateRoundButtons(state and state.Rounds or {}, playerRound, hasLoadout)

        if lobbyCountdownLabel then
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
                lobbyCountdownLabel.Text = countdownText
        end

        if readyButton then
                readyButton.Text = lobbyReadyState and "Unready" or "Ready Up"
                readyButton.BackgroundColor3 = lobbyReadyState and Color3.fromRGB(110, 90, 160) or Color3.fromRGB(70, 130, 90)
                local inLobbyRoom = playerRound ~= nil
                local canReady = hasLoadout and inLobbyRoom
                readyButton.Visible = inLobbyRoom
                readyButton.Active = canReady
                readyButton.AutoButtonColor = canReady
                readyButton.TextTransparency = canReady and 0 or 0.35
        end

        if leaveButton then
                local canLeave = playerRound ~= nil
                leaveButton.Visible = canLeave
                leaveButton.Active = canLeave
                leaveButton.AutoButtonColor = canLeave
        end

        if lobbyStatusLabel then
                if loadoutLocked then
                        lobbyStatusLabel.Text = "Loadout locked while the countdown is active."
                elseif not hasLoadout or not hasAnySelectedTowers() then
                        lobbyStatusLabel.Text = "Select at least one tower to join a round."
                elseif not playerRound then
                        lobbyStatusLabel.Text = "Choose a round to enter the waiting room."
                else
                        lobbyStatusLabel.Text = ""
                end
        end
end

local function createMapSelectionGui()
        if mapSelectionGui then
                return mapSelectionGui
        end

        mapSelectionGui = Instance.new("ScreenGui")
        mapSelectionGui.Name = "MapSelectionUI"
        mapSelectionGui.ResetOnSpawn = false
        mapSelectionGui.IgnoreGuiInset = true
        mapSelectionGui.DisplayOrder = 6
        mapSelectionGui.Enabled = false
        mapSelectionGui.Parent = playerGui

        mapSelectionFrame = Instance.new("Frame")
        mapSelectionFrame.Name = "MapSelectionFrame"
        mapSelectionFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        mapSelectionFrame.Size = UDim2.fromScale(0.8, 0.7)
        mapSelectionFrame.Position = UDim2.fromScale(0.5, 0.5)
        mapSelectionFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        mapSelectionFrame.BackgroundTransparency = 0.1
        mapSelectionFrame.BorderSizePixel = 0
        mapSelectionFrame.Parent = mapSelectionGui

        local frameCorner = Instance.new("UICorner")
        frameCorner.CornerRadius = UDim.new(0.03, 0)
        frameCorner.Parent = mapSelectionFrame

        local mapFrameConstraint = Instance.new("UIAspectRatioConstraint")
        mapFrameConstraint.AspectRatio = 720 / 420
        mapFrameConstraint.DominantAxis = Enum.DominantAxis.Width
        mapFrameConstraint.Parent = mapSelectionFrame

        local mapSizeConstraint = Instance.new("UISizeConstraint")
        mapSizeConstraint.MinSize = Vector2.new(600, 360)
        mapSizeConstraint.Parent = mapSelectionFrame

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
        title.Parent = mapSelectionFrame
        applyScaledText(title, 18, 42)

        mapSelectionStatusLabel = Instance.new("TextLabel")
        mapSelectionStatusLabel.Name = "StatusLabel"
        mapSelectionStatusLabel.AnchorPoint = Vector2.new(0, 0)
        mapSelectionStatusLabel.Size = UDim2.new(0.94, 0, 0.1, 0)
        mapSelectionStatusLabel.Position = UDim2.new(0.03, 0, 0.22, 0)
        mapSelectionStatusLabel.BackgroundTransparency = 1
        mapSelectionStatusLabel.Font = Enum.Font.Gotham
        mapSelectionStatusLabel.TextSize = 18
        mapSelectionStatusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        mapSelectionStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
        mapSelectionStatusLabel.Text = "Choose one of the available battlegrounds."
        mapSelectionStatusLabel.Parent = mapSelectionFrame
        applyScaledText(mapSelectionStatusLabel, 14, 30)

        mapOptionsContainer = Instance.new("Frame")
        mapOptionsContainer.Name = "OptionsContainer"
        mapOptionsContainer.AnchorPoint = Vector2.new(0, 0)
        mapOptionsContainer.Size = UDim2.new(0.94, 0, 0.68, 0)
        mapOptionsContainer.Position = UDim2.new(0.03, 0, 0.32, 0)
        mapOptionsContainer.BackgroundTransparency = 1
        mapOptionsContainer.Parent = mapSelectionFrame

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.Padding = UDim.new(0.04, 0)
        layout.Parent = mapOptionsContainer

        return mapSelectionGui
end

local function clearMapOptions()
        for _, button in ipairs(mapOptionButtons) do
                if button then
                        button:Destroy()
                end
        end
        mapOptionButtons = {}
        mapVoteLabels = {}
end

local function showMapSelection(options, totalPlayers)
        createMapSelectionGui()
        clearMapOptions()

        mapVoteTotalPlayers = totalPlayers or 0

        for index, option in ipairs(options or {}) do
                local container = Instance.new("Frame")
                container.Name = string.format("Option%d", index)
                container.Size = UDim2.new(0.3, 0, 1, 0)
                container.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
                container.BackgroundTransparency = 0.05
                container.BorderSizePixel = 0
                container.Parent = mapOptionsContainer

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
                if mapVoteTotalPlayers > 0 then
                        voteLabel.Text = string.format("0 / %d votes", mapVoteTotalPlayers)
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

                mapOptionButtons[index] = {
                        Container = container,
                        Button = voteButton,
                        Option = option,
                }
                mapVoteLabels[index] = voteLabel
        end

        if mapSelectionStatusLabel then
                if totalPlayers and totalPlayers > 0 then
                        mapSelectionStatusLabel.Text = string.format("Vote for a map (%d players)", totalPlayers)
                else
                        mapSelectionStatusLabel.Text = "Vote for a map"
                end
        end

        mapSelectionGui.Enabled = true
end

local function updateMapVoteCounts(counts, totalPlayers)
        if totalPlayers then
                mapVoteTotalPlayers = totalPlayers
        end

        local displayTotal = mapVoteTotalPlayers or 0

        for index, label in pairs(mapVoteLabels) do
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
        for index, entry in ipairs(mapOptionButtons) do
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

        if mapSelectionStatusLabel then
                if option and option.Name then
                        mapSelectionStatusLabel.Text = string.format("%s will be loaded.", option.Name)
                else
                        mapSelectionStatusLabel.Text = "Map selected."
                end
        end
end

local function ensureHoverGui()
        if hoverGui then
                return hoverGui
        end

	hoverGuiContainer = Instance.new("ScreenGui")
	hoverGuiContainer.Name = "EnemyHoverUI"
	hoverGuiContainer.ResetOnSpawn = false
	hoverGuiContainer.IgnoreGuiInset = true
	hoverGuiContainer.DisplayOrder = 6
	hoverGuiContainer.Enabled = true
	hoverGuiContainer.Parent = playerGui

        hoverGui = Instance.new("Frame")
        hoverGui.Name = "EnemyHoverFrame"
        hoverGui.AnchorPoint = Vector2.new(0, 1)
        hoverGui.Size = UDim2.new(0.18, 0, 0.08, 0)
        hoverGui.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        hoverGui.BackgroundTransparency = 0.2
        hoverGui.BorderSizePixel = 0
        hoverGui.Visible = false
        hoverGui.Parent = hoverGuiContainer

        local hoverCorner = Instance.new("UICorner")
        hoverCorner.CornerRadius = UDim.new(0.25, 0)
        hoverCorner.Parent = hoverGui

        hoverNameLabel = Instance.new("TextLabel")
        hoverNameLabel.Name = "NameLabel"
        hoverNameLabel.BackgroundTransparency = 1
        hoverNameLabel.AnchorPoint = Vector2.new(0, 0)
        hoverNameLabel.Position = UDim2.new(0.04, 0, 0.12, 0)
        hoverNameLabel.Size = UDim2.new(0.92, 0, 0.46, 0)
        hoverNameLabel.Font = Enum.Font.GothamBold
        hoverNameLabel.TextColor3 = Color3.new(1, 1, 1)
        hoverNameLabel.TextSize = 18
        hoverNameLabel.TextXAlignment = Enum.TextXAlignment.Left
        hoverNameLabel.Text = "Enemy"
        hoverNameLabel.Parent = hoverGui
        applyScaledText(hoverNameLabel, 12, 28)

        hoverHealthLabel = Instance.new("TextLabel")
        hoverHealthLabel.Name = "HealthLabel"
        hoverHealthLabel.BackgroundTransparency = 1
        hoverHealthLabel.AnchorPoint = Vector2.new(0, 0)
        hoverHealthLabel.Position = UDim2.new(0.04, 0, 0.58, 0)
        hoverHealthLabel.Size = UDim2.new(0.92, 0, 0.32, 0)
	hoverHealthLabel.Font = Enum.Font.Gotham
        hoverHealthLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        hoverHealthLabel.TextSize = 16
        hoverHealthLabel.TextXAlignment = Enum.TextXAlignment.Left
        hoverHealthLabel.Text = "HP: 0"
        hoverHealthLabel.Parent = hoverGui
        applyScaledText(hoverHealthLabel, 12, 24)

	hoverCombinedLabel = nil

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
                if typeof(config) == "table" and config.Cost and config.Name == towerModel.Name then
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

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TowerHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 4
	screenGui.Parent = playerGui

        shopFrame = Instance.new("Frame")
        shopFrame.Name = "Shop"
        shopFrame.Size = UDim2.new(0.7, 0, 0.22, 0)
        shopFrame.AnchorPoint = Vector2.new(0.5, 1)
        shopFrame.Position = UDim2.new(0.5, 0, 0.98, 0)
        shopFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        shopFrame.BackgroundTransparency = 0.1
        shopFrame.BorderSizePixel = 0
        shopFrame.Parent = screenGui

        local shopCorner = Instance.new("UICorner")
        shopCorner.CornerRadius = UDim.new(0.05, 0)
        shopCorner.Parent = shopFrame

        local slotLayout = Instance.new("UIListLayout")
        slotLayout.FillDirection = Enum.FillDirection.Horizontal
        slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
        slotLayout.Padding = UDim.new(0.02, 0)
        slotLayout.Parent = shopFrame

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
                slotContainer.Parent = shopFrame

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

        statusFrame = Instance.new("Frame")
        statusFrame.Name = "Status"
        statusFrame.AnchorPoint = Vector2.new(0, 1)
        statusFrame.Size = UDim2.new(0.22, 0, 0.34, 0)
        statusFrame.Position = UDim2.new(0.02, 0, 0.98, 0)
        statusFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        statusFrame.BackgroundTransparency = 0.1
        statusFrame.BorderSizePixel = 0
        statusFrame.Parent = screenGui

        local statusCorner = Instance.new("UICorner")
        statusCorner.CornerRadius = UDim.new(0.05, 0)
        statusCorner.Parent = statusFrame

        local statusConstraint = Instance.new("UISizeConstraint")
        statusConstraint.MinSize = Vector2.new(280, 200)
        statusConstraint.Parent = statusFrame

        moneyLabel = Instance.new("TextLabel")
        moneyLabel.Name = "MoneyLabel"
        moneyLabel.BackgroundTransparency = 1
        moneyLabel.AnchorPoint = Vector2.new(0, 0)
        moneyLabel.Position = UDim2.new(0.04, 0, 0.05, 0)
        moneyLabel.Size = UDim2.new(0.92, 0, 0.12, 0)
	moneyLabel.Font = Enum.Font.GothamBold
        moneyLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
        moneyLabel.TextSize = 20
        moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
        moneyLabel.Text = "$0"
        moneyLabel.Parent = statusFrame
        applyScaledText(moneyLabel, 16, 36)

        livesLabel = Instance.new("TextLabel")
        livesLabel.Name = "LivesLabel"
        livesLabel.BackgroundTransparency = 1
        livesLabel.AnchorPoint = Vector2.new(0, 0)
        livesLabel.Position = UDim2.new(0.04, 0, 0.24, 0)
        livesLabel.Size = UDim2.new(0.92, 0, 0.12, 0)
	livesLabel.Font = Enum.Font.Gotham
        livesLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
        livesLabel.TextSize = 18
        livesLabel.TextXAlignment = Enum.TextXAlignment.Left
        livesLabel.Text = "Lives: 0"
        livesLabel.Parent = statusFrame
        applyScaledText(livesLabel, 14, 32)

        waveLabel = Instance.new("TextLabel")
        waveLabel.Name = "WaveLabel"
        waveLabel.BackgroundTransparency = 1
        waveLabel.AnchorPoint = Vector2.new(0, 0)
        waveLabel.Position = UDim2.new(0.04, 0, 0.43, 0)
        waveLabel.Size = UDim2.new(0.92, 0, 0.12, 0)
	waveLabel.Font = Enum.Font.Gotham
        waveLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
        waveLabel.TextSize = 18
        waveLabel.TextXAlignment = Enum.TextXAlignment.Left
        waveLabel.Text = "Wave: 1"
        waveLabel.Parent = statusFrame
        applyScaledText(waveLabel, 14, 32)

        playerTowerTotalLabel = Instance.new("TextLabel")
        playerTowerTotalLabel.Name = "PlayerTowerTotal"
        playerTowerTotalLabel.BackgroundTransparency = 1
        playerTowerTotalLabel.AnchorPoint = Vector2.new(0, 0)
        playerTowerTotalLabel.Position = UDim2.new(0.04, 0, 0.62, 0)
        playerTowerTotalLabel.Size = UDim2.new(0.92, 0, 0.1, 0)
        playerTowerTotalLabel.Font = Enum.Font.Gotham
        playerTowerTotalLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        playerTowerTotalLabel.TextSize = 18
        playerTowerTotalLabel.TextXAlignment = Enum.TextXAlignment.Left
        playerTowerTotalLabel.Text = "Your Towers: 0 / ∞"
        playerTowerTotalLabel.Parent = statusFrame
        applyScaledText(playerTowerTotalLabel, 12, 28)

        teamTowerTotalLabel = Instance.new("TextLabel")
        teamTowerTotalLabel.Name = "TeamTowerTotal"
        teamTowerTotalLabel.BackgroundTransparency = 1
        teamTowerTotalLabel.AnchorPoint = Vector2.new(0, 0)
        teamTowerTotalLabel.Position = UDim2.new(0.04, 0, 0.76, 0)
        teamTowerTotalLabel.Size = UDim2.new(0.92, 0, 0.1, 0)
        teamTowerTotalLabel.Font = Enum.Font.Gotham
        teamTowerTotalLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        teamTowerTotalLabel.TextSize = 18
        teamTowerTotalLabel.TextXAlignment = Enum.TextXAlignment.Left
        teamTowerTotalLabel.Text = "Team Towers: 0 / ∞"
        teamTowerTotalLabel.Parent = statusFrame
        applyScaledText(teamTowerTotalLabel, 12, 28)

        preRoundCountdownLabel = Instance.new("TextLabel")
        preRoundCountdownLabel.Name = "CountdownLabel"
        preRoundCountdownLabel.BackgroundTransparency = 1
        preRoundCountdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        preRoundCountdownLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
        preRoundCountdownLabel.Size = UDim2.new(0.5, 0, 0.12, 0)
        preRoundCountdownLabel.Font = Enum.Font.GothamBold
        preRoundCountdownLabel.TextSize = 18
        preRoundCountdownLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
        preRoundCountdownLabel.TextXAlignment = Enum.TextXAlignment.Center
        preRoundCountdownLabel.TextYAlignment = Enum.TextYAlignment.Center
        preRoundCountdownLabel.Text = ""
        preRoundCountdownLabel.Visible = false
        preRoundCountdownLabel.ZIndex = 10
        preRoundCountdownLabel.Parent = screenGui
        applyScaledText(preRoundCountdownLabel, 18, 48)

        towerDetailsFrame = Instance.new("Frame")
        towerDetailsFrame.Name = "TowerDetails"
        towerDetailsFrame.AnchorPoint = Vector2.new(1, 0.5)
        towerDetailsFrame.Size = UDim2.new(0.26, 0, 0.34, 0)
        towerDetailsFrame.Position = UDim2.new(0.98, 0, 0.5, 0)
        towerDetailsFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        towerDetailsFrame.BackgroundTransparency = 0.1
        towerDetailsFrame.BorderSizePixel = 0
        towerDetailsFrame.Visible = false
        towerDetailsFrame.Parent = screenGui

        local detailsCorner = Instance.new("UICorner")
        detailsCorner.CornerRadius = UDim.new(0.05, 0)
	detailsCorner.Parent = towerDetailsFrame

        towerNameLabel = Instance.new("TextLabel")
        towerNameLabel.Name = "TowerNameLabel"
        towerNameLabel.BackgroundTransparency = 1
        towerNameLabel.AnchorPoint = Vector2.new(0, 0)
        towerNameLabel.Position = UDim2.new(0.05, 0, 0.08, 0)
        towerNameLabel.Size = UDim2.new(0.9, 0, 0.16, 0)
        towerNameLabel.Font = Enum.Font.GothamBold
        towerNameLabel.TextColor3 = Color3.new(1, 1, 1)
        towerNameLabel.TextSize = 20
        towerNameLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerNameLabel.Text = "Tower"
        towerNameLabel.Parent = towerDetailsFrame
        applyScaledText(towerNameLabel, 16, 36)

        towerLevelLabel = Instance.new("TextLabel")
        towerLevelLabel.Name = "TowerLevelLabel"
        towerLevelLabel.BackgroundTransparency = 1
        towerLevelLabel.AnchorPoint = Vector2.new(0, 0)
        towerLevelLabel.Position = UDim2.new(0.05, 0, 0.26, 0)
        towerLevelLabel.Size = UDim2.new(0.9, 0, 0.12, 0)
        towerLevelLabel.Font = Enum.Font.Gotham
        towerLevelLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerLevelLabel.TextSize = 16
        towerLevelLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerLevelLabel.Text = "Level: 1"
        towerLevelLabel.Parent = towerDetailsFrame
        applyScaledText(towerLevelLabel, 14, 30)

        towerStatsLabel = Instance.new("TextLabel")
        towerStatsLabel.Name = "TowerStatsLabel"
        towerStatsLabel.BackgroundTransparency = 1
        towerStatsLabel.AnchorPoint = Vector2.new(0, 0)
        towerStatsLabel.Position = UDim2.new(0.05, 0, 0.4, 0)
        towerStatsLabel.Size = UDim2.new(0.9, 0, 0.24, 0)
        towerStatsLabel.Font = Enum.Font.Gotham
        towerStatsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        towerStatsLabel.TextSize = 16
        towerStatsLabel.TextXAlignment = Enum.TextXAlignment.Left
        towerStatsLabel.TextYAlignment = Enum.TextYAlignment.Top
        towerStatsLabel.TextWrapped = true
        towerStatsLabel.Text = ""
        towerStatsLabel.Parent = towerDetailsFrame
        applyScaledText(towerStatsLabel, 12, 26)

        ownershipLabel = Instance.new("TextLabel")
        ownershipLabel.Name = "OwnershipLabel"
        ownershipLabel.BackgroundTransparency = 1
        ownershipLabel.AnchorPoint = Vector2.new(0, 0)
        ownershipLabel.Position = UDim2.new(0.05, 0, 0.64, 0)
        ownershipLabel.Size = UDim2.new(0.9, 0, 0.08, 0)
        ownershipLabel.Font = Enum.Font.Gotham
        ownershipLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        ownershipLabel.TextSize = 16
        ownershipLabel.TextXAlignment = Enum.TextXAlignment.Left
        ownershipLabel.Text = "Owner"
        ownershipLabel.Parent = towerDetailsFrame
        applyScaledText(ownershipLabel, 12, 26)

        upgradeDescriptionLabel = Instance.new("TextLabel")
        upgradeDescriptionLabel.Name = "UpgradeDescriptionLabel"
        upgradeDescriptionLabel.BackgroundTransparency = 1
        upgradeDescriptionLabel.AnchorPoint = Vector2.new(0, 0)
        upgradeDescriptionLabel.Position = UDim2.new(0.05, 0, 0.72, 0)
        upgradeDescriptionLabel.Size = UDim2.new(0.9, 0, 0.12, 0)
        upgradeDescriptionLabel.Font = Enum.Font.Gotham
        upgradeDescriptionLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        upgradeDescriptionLabel.TextSize = 14
        upgradeDescriptionLabel.TextWrapped = true
        upgradeDescriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
        upgradeDescriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
        upgradeDescriptionLabel.Text = ""
        upgradeDescriptionLabel.Parent = towerDetailsFrame
        applyScaledText(upgradeDescriptionLabel, 12, 24)

        upgradeButton = Instance.new("TextButton")
        upgradeButton.Name = "UpgradeButton"
        upgradeButton.Size = UDim2.new(0.44, 0, 0.14, 0)
        upgradeButton.AnchorPoint = Vector2.new(0, 1)
        upgradeButton.Position = UDim2.new(0.05, 0, 0.98, 0)
        upgradeButton.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
        upgradeButton.BorderSizePixel = 0
        upgradeButton.Font = Enum.Font.GothamBold
        upgradeButton.TextSize = 16
        upgradeButton.TextColor3 = Color3.new(1, 1, 1)
        upgradeButton.Text = "Upgrade"
        upgradeButton.AutoButtonColor = true
        upgradeButton.Visible = false
        upgradeButton.Parent = towerDetailsFrame
        applyScaledText(upgradeButton, 14, 30)

	upgradeButtonOriginalColor = upgradeButton.BackgroundColor3
	upgradeButtonOriginalTextColor = upgradeButton.TextColor3
	upgradeButtonOriginalBackgroundTransparency = upgradeButton.BackgroundTransparency
	upgradeButtonOriginalTextTransparency = upgradeButton.TextTransparency
	upgradeButtonOriginalAutoButtonColor = upgradeButton.AutoButtonColor

	upgradeButton.MouseButton1Click:Connect(function()
		if selectedTower then
			remotes.TowerUpgradeRequested:FireServer(selectedTower)
		end
	end)

        sellButton = Instance.new("TextButton")
        sellButton.Name = "SellButton"
        sellButton.Size = UDim2.new(0.44, 0, 0.14, 0)
        sellButton.AnchorPoint = Vector2.new(1, 1)
        sellButton.Position = UDim2.new(0.95, 0, 0.98, 0)
        sellButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
        sellButton.BorderSizePixel = 0
        sellButton.Font = Enum.Font.GothamBold
        sellButton.TextSize = 16
        sellButton.TextColor3 = Color3.new(1, 1, 1)
        sellButton.Text = "Sell"
        sellButton.AutoButtonColor = true
        sellButton.Visible = false
        sellButton.Parent = towerDetailsFrame
        applyScaledText(sellButton, 14, 30)

	sellButtonOriginalAutoButtonColor = sellButton.AutoButtonColor

	sellButton.MouseButton1Click:Connect(function()
		if selectedTower then
			remotes.TowerSellRequested:FireServer(selectedTower)
		end
	end)

        local function applyHudConstraints()
                if not screenGui then
                        return
                end

                local screenSize = screenGui.AbsoluteSize
                local screenWidth = screenSize.X > 0 and screenSize.X or 1920
                local screenHeight = screenSize.Y > 0 and screenSize.Y or 1080

                if shopFrame then
                        local aspect = shopFrame:FindFirstChild("AspectConstraint")
                        if not aspect then
                                aspect = Instance.new("UIAspectRatioConstraint")
                                aspect.Name = "AspectConstraint"
                                aspect.Parent = shopFrame
                        end
                        local widthScale = math.clamp(0.55 + (screenWidth / 1920) * 0.25, 0.6, 0.85)
                        local heightScale = math.clamp(0.18 + (screenHeight / 1080) * 0.05, 0.18, 0.28)
                        shopFrame.Size = UDim2.new(widthScale, 0, heightScale, 0)
                        aspect.AspectRatio = widthScale / math.max(heightScale, 0.01)
                        aspect.DominantAxis = Enum.DominantAxis.Width

                        local sizeConstraint = shopFrame:FindFirstChild("SizeConstraint")
                        if not sizeConstraint then
                                sizeConstraint = Instance.new("UISizeConstraint")
                                sizeConstraint.Name = "SizeConstraint"
                                sizeConstraint.Parent = shopFrame
                        end
                        sizeConstraint.MinSize = Vector2.new(math.max(screenSize.X * 0.35, 420), math.max(screenSize.Y * 0.1, 120))
                end

                if towerDetailsFrame then
                        local aspect = towerDetailsFrame:FindFirstChild("AspectConstraint")
                        if not aspect then
                                aspect = Instance.new("UIAspectRatioConstraint")
                                aspect.Name = "AspectConstraint"
                                aspect.Parent = towerDetailsFrame
                        end
                        local towerWidthScale = math.clamp(0.22 + (screenWidth / 3840) * 0.04, 0.22, 0.26)
                        towerDetailsFrame.Size = UDim2.new(towerWidthScale, 0, 0.34, 0)
                        aspect.AspectRatio = 0.76
                        aspect.DominantAxis = Enum.DominantAxis.Height

                        local sizeConstraint = towerDetailsFrame:FindFirstChild("SizeConstraint")
                        if not sizeConstraint then
                                sizeConstraint = Instance.new("UISizeConstraint")
                                sizeConstraint.Name = "SizeConstraint"
                                sizeConstraint.Parent = towerDetailsFrame
                        end
                        sizeConstraint.MinSize = Vector2.new(math.max(screenSize.X * 0.16, 280), math.max(screenSize.Y * 0.16, 220))
                end
        end

        applyHudConstraints()
        task.defer(applyHudConstraints)
        screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyHudConstraints)

	for _, button in pairs(shopSlotButtons) do
		connectShopButton(button)
	end

        applyLoadoutToShop()
        updateOverallTowerTotals()

        return screenGui
end

local function showTowerSelection()
	local gui = createSelectionGui()
	if not gui then
		return
	end

        for i = 1, LOADOUT_SLOT_COUNT do
                loadoutSelection[i] = nil
                if selectionSlotButtons[i] then
                        selectionSlotButtons[i]:SetAttribute("TowerType", nil)
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

local function createPlacementValidationParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
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

	local towersFolder = workspace:FindFirstChild("Towers")
	if towersFolder then
		table.insert(ignoreList, towersFolder)
	end

	params.FilterDescendantsInstances = ignoreList
	return params, ignoreList
end
local function findGroundBeneath(position)
	local map = workspace:FindFirstChild("Map")
	local ground = map and map:FindFirstChild("PathGround")
	if not ground then
		return nil
	end

	local params, ignoreList = createPlacementValidationParams()
	local origin = position + Vector3.new(0, 200, 0)
	local direction = Vector3.new(0, -400, 0)

	for _ = 1, MAX_GROUND_RAYCAST_ATTEMPTS do
		local result = workspace:Raycast(origin, direction, params)
		if not result then
			return nil
		end

		if result.Instance == ground or result.Instance:IsDescendantOf(ground) then
			return result
		end

		table.insert(ignoreList, result.Instance)
		params.FilterDescendantsInstances = ignoreList
		origin = result.Position - Vector3.new(0, 0.05, 0)
	end

	return nil
end
local function isPositionClear(position)
	local towersFolder = workspace:FindFirstChild("Towers")
	if not towersFolder then
		return true
	end

	local candidateHalfX = math.max(0.05, previewFootprintSize.X / 2)
	local candidateHalfZ = math.max(0.05, previewFootprintSize.Z / 2)

	for _, tower in ipairs(towersFolder:GetChildren()) do
		local primary = tower.PrimaryPart or tower:FindFirstChild("Base")
		if primary then
			local towerPos = primary.Position
			local otherHalfX = math.max(0.05, primary.Size.X / 2)
			local otherHalfZ = math.max(0.05, primary.Size.Z / 2)
			local deltaX = math.abs(towerPos.X - position.X)
			local deltaZ = math.abs(towerPos.Z - position.Z)
			local limitX = otherHalfX + candidateHalfX + PLACEMENT_EDGE_EPSILON
			local limitZ = otherHalfZ + candidateHalfZ + PLACEMENT_EDGE_EPSILON
			if deltaX <= limitX and deltaZ <= limitZ then
				return false
			end
		end
	end

	return true
end
local function evaluatePlacement(position)
	local groundResult = findGroundBeneath(position)
	if not groundResult then
		return false
	end

	local placementPosition = Vector3.new(
		groundResult.Position.X,
		groundResult.Position.Y,
		groundResult.Position.Z
	)

	if not isPositionClear(placementPosition) then
		return false
	end

	return true, placementPosition
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
		local valid, placementPosition = evaluatePlacement(hitPosition)
		placementValid = valid and true or false

		local previewVector
		if placementValid and placementPosition then
			previewVector = Vector3.new(placementPosition.X, placementPosition.Y + previewPart.Size.Y / 2, placementPosition.Z)
		else
			previewVector = Vector3.new(hitPosition.X, hitPosition.Y + previewPart.Size.Y / 2, hitPosition.Z)
		end

		previewPart.CFrame = CFrame.new(previewVector)
		local config = towerConfigs[placingTowerType]
		if previewRangeRing and previewRangeAdornment and config and config.Range then
			local ringBase = placementValid and placementPosition or hitPosition
			local ringY = ringBase.Y + 0.05
			updateRangeRing(previewRangeRing, previewRangeAdornment, config.Range, Vector3.new(ringBase.X, ringY, ringBase.Z))
		end

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
		if hoverGui and hoverGui:IsA("GuiObject") then
			hoverGui.Visible = false
		end
        end
end

local towerCountsEvent = remotes:FindFirstChild("TowerCountsUpdated")
if towerCountsEvent and towerCountsEvent:IsA("RemoteEvent") then
        towerCountsEvent.OnClientEvent:Connect(function(payload)
                if typeof(payload) == "table" then
                        towerCountSnapshot = payload
                else
                        towerCountSnapshot = nil
                end

                updateOverallTowerTotals()
                updateAllShopSlotCounts()
        end)
end

if remotes:FindFirstChild("MoneyChanged") then
        remotes.MoneyChanged.OnClientEvent:Connect(function(amount)
                currentMoney = math.max(0, math.floor((amount or 0) + 0.5))
                if moneyLabel then
                        moneyLabel.Text = string.format("$%d", currentMoney)
		end
		if selectedTower then
			updateTowerDetails(selectedTower)
		end
		updateStartButtonVisual()
	end)
end

if remotes:FindFirstChild("LivesChanged") then
	remotes.LivesChanged.OnClientEvent:Connect(function(lives)
		if livesLabel then
			livesLabel.Text = string.format("Lives: %d", math.floor(lives or 0))
		end
	end)
end

if remotes:FindFirstChild("WaveStarted") then
        remotes.WaveStarted.OnClientEvent:Connect(function(waveNumber)
                if waveLabel then
                        waveLabel.Text = string.format("Wave: %d", waveNumber or 1)
                end
                gameEnded = false
                if preRoundCountdownLabel then
                        preRoundCountdownLabel.Visible = false
                        preRoundCountdownLabel.Text = ""
                end
        end)
end

if remotes:FindFirstChild("GameEnded") then
        remotes.GameEnded.OnClientEvent:Connect(function(victory)
                gameEnded = true
                lastVictoryState = victory
                if preRoundCountdownLabel then
                        preRoundCountdownLabel.Visible = false
                        preRoundCountdownLabel.Text = ""
                end
        end)
end

if remotes:FindFirstChild("GameRestarted") then
        remotes.GameRestarted.OnClientEvent:Connect(function()
                gameEnded = false
                lastVictoryState = nil
                lobbyPhase = "lobby"
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
                lobbyPhase = "mapSelection"
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

if remotes:FindFirstChild("RoundSetupComplete") then
        remotes.RoundSetupComplete.OnClientEvent:Connect(function(payload)
                lobbyPhase = "inRound"
                updateInterfaceVisibility()
                if mapSelectionGui then
                        mapSelectionGui.Enabled = false
                end
                createGui()
                applyLoadoutToShop()
                if payload and payload.MapName and preRoundCountdownLabel then
                        preRoundCountdownLabel.Text = string.format("%s selected", payload.MapName)
                        preRoundCountdownLabel.Visible = true
                end
        end)
end

if remotes:FindFirstChild("RoundCountdownUpdated") then
        remotes.RoundCountdownUpdated.OnClientEvent:Connect(function(payload)
                if not preRoundCountdownLabel then
                        return
                end

                local remaining = payload and payload.Remaining or 0
                if remaining and remaining > 0 then
                        preRoundCountdownLabel.Text = string.format("Round starts in %ds", remaining)
                        preRoundCountdownLabel.Visible = true
                else
                        preRoundCountdownLabel.Visible = false
                        preRoundCountdownLabel.Text = ""
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
                if selectionScreenGui and selectionScreenGui.Enabled then
                        setActiveSelectionSlot(math.clamp(slotIndex, 1, LOADOUT_SLOT_COUNT))
                elseif lobbyPhase == "inRound" then
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
                if lobbyPhase ~= "inRound" then
                        return
                end
		if placingTowerType then
			local unitRay = mouse.UnitRay
			local rayResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, createRaycastParams())
			if rayResult then
				local valid, placementPosition = evaluatePlacement(rayResult.Position)
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
                if lobbyPhase ~= "inRound" then
                        return
                end
                if placingTowerType then
                        cancelPlacement()
                elseif selectedTower and not placingTowerType then
			local ownerId = selectedTower:GetAttribute("OwnerUserId")
			if ownerId == player.UserId and not gameEnded then
				remotes.TowerSellRequested:FireServer(selectedTower)
			end
		end
        elseif input.KeyCode == Enum.KeyCode.E then
                if lobbyPhase ~= "inRound" then
                        return
                end
                if not placingTowerType and selectedTower then
                        local ownerId = selectedTower:GetAttribute("OwnerUserId")
                        if ownerId == player.UserId and not gameEnded then
				remotes.TowerUpgradeRequested:FireServer(selectedTower)
			end
		end
	end
end)

remotes.TowerUpgraded.OnClientEvent:Connect(function(towerModel, _, previousModel)
        if not towerModel then
                return
        end

        if selectedTower and (towerModel == selectedTower or previousModel == selectedTower) then
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
        if selectedTower and (not selectedTower.Parent) then
                clearSelection()
        end
end)
