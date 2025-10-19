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
local shopSlotButtons = {}
local shopSlotOriginalText = {}
local shopSlotPriceLabels = {}
local beginPlacement

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
local selectionConfirmButton
local selectionConfirmButtonOriginalAutoButtonColor
local loadoutSelection = {}
local selectionComplete = false

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

local function updateConfirmButtonState()
        if not selectionConfirmButton then
                return
        end

        local ready = hasAnySelectedTowers()

	if selectionConfirmButtonOriginalAutoButtonColor == nil then
		selectionConfirmButtonOriginalAutoButtonColor = selectionConfirmButton.AutoButtonColor
	end

	selectionConfirmButton.Active = ready
	if selectionConfirmButtonOriginalAutoButtonColor ~= nil then
		selectionConfirmButton.AutoButtonColor = ready and selectionConfirmButtonOriginalAutoButtonColor or false
	end
	selectionConfirmButton:SetAttribute("SelectionReady", ready)
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

local function assignTowerToSlot(slotIndex, towerType)
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
                local orderA = configA and configA.SelectionOrder or math.huge
                local orderB = configB and configB.SelectionOrder or math.huge
                if orderA ~= orderB then
                        return orderA < orderB
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
                        button.Size = UDim2.fromOffset(500, 56)
                        button.Position = UDim2.new(0, 5, 0, 0)
                        button.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
                        button.BorderSizePixel = 0
                        button.TextColor3 = Color3.new(1, 1, 1)
                        button.Font = Enum.Font.Gotham
                        button.TextSize = 20
                        button.AutoButtonColor = true
                        button.LayoutOrder = typeof(config.SelectionOrder) == "number" and config.SelectionOrder or 0
                        button.Parent = selectionTowerList
                        button:SetAttribute("TowerType", towerType)
                        button:SetAttribute("TowerClientGenerated", true)
                        button.Text = config.Name or towerType

                        button.MouseButton1Click:Connect(function()
                                local slotIndex = selectionActiveSlot or findFirstEmptySlot() or 1
                                assignTowerToSlot(slotIndex, towerType)
                        end)
                end
        end

        local layout = selectionTowerList:FindFirstChildWhichIsA("UIListLayout")
        if selectionTowerList:IsA("ScrollingFrame") and layout then
                selectionTowerList.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 10)
        end
end

local function createSelectionGui()
	if selectionScreenGui then
		return selectionScreenGui
	end

	selectionScreenGui = Instance.new("ScreenGui")
	selectionScreenGui.Name = "TowerSelectionUI"
	selectionScreenGui.ResetOnSpawn = false
	selectionScreenGui.IgnoreGuiInset = true
	selectionScreenGui.DisplayOrder = 5
	selectionScreenGui.Enabled = true
	selectionScreenGui.Parent = playerGui

	selectionFrame = Instance.new("Frame")
	selectionFrame.Name = "SelectionFrame"
        selectionFrame.Size = UDim2.fromOffset(620, 420)
	selectionFrame.Position = UDim2.fromOffset(0, 0)
	selectionFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	selectionFrame.BorderSizePixel = 0
	selectionFrame.Parent = selectionScreenGui

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 12)
	frameCorner.Parent = selectionFrame

	local title = Instance.new("TextLabel")
	title.Name = "TitleLabel"
	title.Size = UDim2.fromOffset(400, 40)
	title.Position = UDim2.new(0, 10, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.Text = "Select Your Towers"
	title.Parent = selectionFrame

	selectionTowerList = Instance.new("ScrollingFrame")
	selectionTowerList.Name = "TowerList"
        selectionTowerList.Size = UDim2.fromOffset(600, 230)
	selectionTowerList.Position = UDim2.new(0, 10, 0, 60)
	selectionTowerList.CanvasSize = UDim2.fromOffset(0, 0)
	selectionTowerList.ScrollBarThickness = 6
	selectionTowerList.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	selectionTowerList.BorderSizePixel = 0
	selectionTowerList.Parent = selectionFrame

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 8)
	listCorner.Parent = selectionTowerList

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = selectionTowerList

	local slotsLabel = Instance.new("TextLabel")
	slotsLabel.Name = "SlotsLabel"
        slotsLabel.Size = UDim2.fromOffset(600, 24)
	slotsLabel.Position = UDim2.new(0, 10, 0, 290)
	slotsLabel.BackgroundTransparency = 1
	slotsLabel.Font = Enum.Font.Gotham
	slotsLabel.TextSize = 18
	slotsLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
        slotsLabel.Text = string.format("Assign up to %d towers to your loadout (minimum one):", LOADOUT_SLOT_COUNT)
	slotsLabel.TextXAlignment = Enum.TextXAlignment.Left
	slotsLabel.Parent = selectionFrame

	local slotsFrame = Instance.new("Frame")
	slotsFrame.Name = "SlotsContainer"
        slotsFrame.Size = UDim2.fromOffset(600, 48)
	slotsFrame.Position = UDim2.new(0, 10, 0, 315)
	slotsFrame.BackgroundTransparency = 1
	slotsFrame.Parent = selectionFrame

	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.FillDirection = Enum.FillDirection.Horizontal
	slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotsLayout.Padding = UDim.new(0, 8)
	slotsLayout.Parent = slotsFrame

	selectionSlotButtons = {}
	selectionSlotOriginalText = {}
        for i = 1, LOADOUT_SLOT_COUNT do
                local button = Instance.new("TextButton")
                button.Name = string.format("Slot%d", i)
                button.Size = UDim2.fromOffset(112, 48)
                button.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
                button.BorderSizePixel = 0
                button.Font = Enum.Font.Gotham
                button.TextSize = 18
                button.TextColor3 = Color3.new(1, 1, 1)
                button.AutoButtonColor = true
                button.Text = string.format("Slot %d", i)
                button.Parent = slotsFrame
                button.LayoutOrder = i
                button:SetAttribute("SlotIndex", i)
                selectionSlotButtons[i] = button
                selectionSlotOriginalText[i] = button.Text

		button.MouseButton1Click:Connect(function()
			setActiveSelectionSlot(i)
		end)
		button.MouseButton2Click:Connect(function()
			clearSlot(i)
		end)
	end

	selectionConfirmButton = Instance.new("TextButton")
	selectionConfirmButton.Name = "ConfirmButton"
        selectionConfirmButton.Size = UDim2.fromOffset(200, 44)
        selectionConfirmButton.Position = UDim2.new(0.5, -100, 0, 370)
	selectionConfirmButton.BackgroundColor3 = Color3.fromRGB(70, 130, 90)
	selectionConfirmButton.BorderSizePixel = 0
	selectionConfirmButton.Font = Enum.Font.GothamBold
	selectionConfirmButton.TextSize = 20
	selectionConfirmButton.TextColor3 = Color3.new(1, 1, 1)
	selectionConfirmButton.AutoButtonColor = true
	selectionConfirmButton.Text = "Confirm Loadout"
	selectionConfirmButton.Parent = selectionFrame
	selectionConfirmButtonOriginalAutoButtonColor = selectionConfirmButton.AutoButtonColor

        selectionConfirmButton.MouseButton1Click:Connect(function()
                if selectionComplete or not selectionConfirmButton.Active then
                        return
                end

                if not hasAnySelectedTowers() then
                        return
                end

                selectionComplete = true
                selectionScreenGui.Enabled = false
                applyLoadoutToShop()
        end)

	local function updateSelectionLayout()
		if not selectionScreenGui or not selectionFrame then
			return
		end

		local absoluteSize = selectionScreenGui.AbsoluteSize
		local frameSize = selectionFrame.AbsoluteSize
		local posX = math.max(math.floor((absoluteSize.X - frameSize.X) * 0.5), 0)
		local posY = math.max(math.floor((absoluteSize.Y - frameSize.Y) * 0.5), 0)
		selectionFrame.Position = UDim2.fromOffset(posX, posY)
	end

	updateSelectionLayout()
	task.defer(updateSelectionLayout)
	selectionScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSelectionLayout)

	selectionComplete = false
	populateTowerSelectionButtons()
	for index in pairs(selectionSlotButtons) do
		updateSelectionSlotDisplay(index)
	end
	setActiveSelectionSlot(findFirstEmptySlot() or 1)
	updateConfirmButtonState()

	return selectionScreenGui
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
	hoverGui.Size = UDim2.fromOffset(220, 48)
	hoverGui.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	hoverGui.BackgroundTransparency = 0.2
	hoverGui.BorderSizePixel = 0
	hoverGui.Visible = false
	hoverGui.Parent = hoverGuiContainer

	local hoverCorner = Instance.new("UICorner")
	hoverCorner.CornerRadius = UDim.new(0, 8)
	hoverCorner.Parent = hoverGui

	hoverNameLabel = Instance.new("TextLabel")
	hoverNameLabel.Name = "NameLabel"
	hoverNameLabel.BackgroundTransparency = 1
	hoverNameLabel.Position = UDim2.new(0, 8, 0, 4)
	hoverNameLabel.Size = UDim2.fromOffset(204, 22)
	hoverNameLabel.Font = Enum.Font.GothamBold
	hoverNameLabel.TextColor3 = Color3.new(1, 1, 1)
	hoverNameLabel.TextSize = 18
	hoverNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	hoverNameLabel.Text = "Enemy"
	hoverNameLabel.Parent = hoverGui

	hoverHealthLabel = Instance.new("TextLabel")
	hoverHealthLabel.Name = "HealthLabel"
	hoverHealthLabel.BackgroundTransparency = 1
	hoverHealthLabel.Position = UDim2.new(0, 8, 0, 24)
	hoverHealthLabel.Size = UDim2.fromOffset(204, 20)
	hoverHealthLabel.Font = Enum.Font.Gotham
	hoverHealthLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	hoverHealthLabel.TextSize = 16
	hoverHealthLabel.TextXAlignment = Enum.TextXAlignment.Left
	hoverHealthLabel.Text = "HP: 0"
	hoverHealthLabel.Parent = hoverGui

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

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TowerHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 4
	screenGui.Parent = playerGui

	shopFrame = Instance.new("Frame")
	shopFrame.Name = "Shop"
        shopFrame.Size = UDim2.fromOffset(720, 140)
	shopFrame.Position = UDim2.fromOffset(0, 0)
	shopFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	shopFrame.BackgroundTransparency = 0.1
	shopFrame.BorderSizePixel = 0
	shopFrame.Parent = screenGui

	local shopCorner = Instance.new("UICorner")
	shopCorner.CornerRadius = UDim.new(0, 12)
	shopCorner.Parent = shopFrame

	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Padding = UDim.new(0, 12)
	slotLayout.Parent = shopFrame

	shopSlotButtons = {}
	shopSlotOriginalText = {}
        for i = 1, LOADOUT_SLOT_COUNT do
                local slotContainer = Instance.new("Frame")
                slotContainer.Name = string.format("ShopSlotContainer%d", i)
		slotContainer.Size = UDim2.fromOffset(120, 108)
		slotContainer.BackgroundTransparency = 1
		slotContainer.BorderSizePixel = 0
		slotContainer.LayoutOrder = i
		slotContainer.Parent = shopFrame

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "PriceLabel"
		priceLabel.BackgroundTransparency = 1
		priceLabel.Size = UDim2.fromOffset(120, 22)
		priceLabel.Position = UDim2.fromOffset(0, 0)
		priceLabel.Font = Enum.Font.Gotham
		priceLabel.TextSize = 18
		priceLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
		priceLabel.Text = ""
		priceLabel.TextXAlignment = Enum.TextXAlignment.Center
		priceLabel.TextYAlignment = Enum.TextYAlignment.Center
		priceLabel.TextWrapped = true
		priceLabel.TextScaled = false
		priceLabel.Visible = false
		priceLabel.Parent = slotContainer
		shopSlotPriceLabels[i] = priceLabel

		local button = Instance.new("TextButton")
		button.Name = string.format("ShopSlot%d", i)
		button.Size = UDim2.fromOffset(120, 80)
		button.Position = UDim2.fromOffset(0, 24)
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
	end

	statusFrame = Instance.new("Frame")
	statusFrame.Name = "Status"
	statusFrame.Size = UDim2.fromOffset(320, 180)
	statusFrame.Position = UDim2.fromOffset(0, 0)
	statusFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	statusFrame.BackgroundTransparency = 0.1
	statusFrame.BorderSizePixel = 0
	statusFrame.Parent = screenGui

	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = UDim.new(0, 12)
	statusCorner.Parent = statusFrame

	moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "MoneyLabel"
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Position = UDim2.new(0, 12, 0, 12)
	moneyLabel.Size = UDim2.fromOffset(296, 24)
	moneyLabel.Font = Enum.Font.GothamBold
	moneyLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	moneyLabel.TextSize = 20
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyLabel.Text = "$0"
	moneyLabel.Parent = statusFrame

	livesLabel = Instance.new("TextLabel")
	livesLabel.Name = "LivesLabel"
	livesLabel.BackgroundTransparency = 1
	livesLabel.Position = UDim2.new(0, 12, 0, 44)
	livesLabel.Size = UDim2.fromOffset(296, 24)
	livesLabel.Font = Enum.Font.Gotham
	livesLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
	livesLabel.TextSize = 18
	livesLabel.TextXAlignment = Enum.TextXAlignment.Left
	livesLabel.Text = "Lives: 0"
	livesLabel.Parent = statusFrame

	waveLabel = Instance.new("TextLabel")
	waveLabel.Name = "WaveLabel"
	waveLabel.BackgroundTransparency = 1
	waveLabel.Position = UDim2.new(0, 12, 0, 76)
	waveLabel.Size = UDim2.fromOffset(296, 24)
	waveLabel.Font = Enum.Font.Gotham
	waveLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
	waveLabel.TextSize = 18
	waveLabel.TextXAlignment = Enum.TextXAlignment.Left
	waveLabel.Text = "Wave: 1"
	waveLabel.Parent = statusFrame

	startButton = Instance.new("TextButton")
	startButton.Name = "StartButton"
	startButton.Size = UDim2.fromOffset(296, 36)
	startButton.Position = UDim2.new(0, 12, 0, 112)
	startButton.BackgroundColor3 = Color3.fromRGB(70, 130, 90)
	startButton.BorderSizePixel = 0
	startButton.Font = Enum.Font.GothamBold
	startButton.TextSize = 18
	startButton.TextColor3 = Color3.new(1, 1, 1)
	startButton.Text = "Start Wave"
	startButton.AutoButtonColor = true
	startButton.Parent = statusFrame

	startButton.MouseButton1Click:Connect(function()
		if gameEnded then
			remotes.RequestRestart:FireServer()
		else
			remotes.RequestWaveStart:FireServer()
		end
	end)

	towerDetailsFrame = Instance.new("Frame")
	towerDetailsFrame.Name = "TowerDetails"
	towerDetailsFrame.Size = UDim2.fromOffset(380, 240)
	towerDetailsFrame.Position = UDim2.fromOffset(0, 0)
	towerDetailsFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	towerDetailsFrame.BackgroundTransparency = 0.1
	towerDetailsFrame.BorderSizePixel = 0
	towerDetailsFrame.Visible = false
	towerDetailsFrame.Parent = screenGui

	local detailsCorner = Instance.new("UICorner")
	detailsCorner.CornerRadius = UDim.new(0, 12)
	detailsCorner.Parent = towerDetailsFrame

	towerNameLabel = Instance.new("TextLabel")
	towerNameLabel.Name = "TowerNameLabel"
	towerNameLabel.BackgroundTransparency = 1
	towerNameLabel.Position = UDim2.new(0, 16, 0, 16)
	towerNameLabel.Size = UDim2.fromOffset(348, 26)
	towerNameLabel.Font = Enum.Font.GothamBold
	towerNameLabel.TextColor3 = Color3.new(1, 1, 1)
	towerNameLabel.TextSize = 20
	towerNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	towerNameLabel.Text = "Tower"
	towerNameLabel.Parent = towerDetailsFrame

	towerLevelLabel = Instance.new("TextLabel")
	towerLevelLabel.Name = "TowerLevelLabel"
	towerLevelLabel.BackgroundTransparency = 1
	towerLevelLabel.Position = UDim2.new(0, 16, 0, 48)
	towerLevelLabel.Size = UDim2.fromOffset(348, 20)
	towerLevelLabel.Font = Enum.Font.Gotham
	towerLevelLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	towerLevelLabel.TextSize = 16
	towerLevelLabel.TextXAlignment = Enum.TextXAlignment.Left
	towerLevelLabel.Text = "Level: 1"
	towerLevelLabel.Parent = towerDetailsFrame

	towerStatsLabel = Instance.new("TextLabel")
	towerStatsLabel.Name = "TowerStatsLabel"
	towerStatsLabel.BackgroundTransparency = 1
	towerStatsLabel.Position = UDim2.new(0, 16, 0, 72)
	towerStatsLabel.Size = UDim2.fromOffset(348, 72)
	towerStatsLabel.Font = Enum.Font.Gotham
	towerStatsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	towerStatsLabel.TextSize = 16
	towerStatsLabel.TextXAlignment = Enum.TextXAlignment.Left
	towerStatsLabel.TextYAlignment = Enum.TextYAlignment.Top
	towerStatsLabel.TextWrapped = true
	towerStatsLabel.Text = ""
	towerStatsLabel.Parent = towerDetailsFrame

	ownershipLabel = Instance.new("TextLabel")
	ownershipLabel.Name = "OwnershipLabel"
	ownershipLabel.BackgroundTransparency = 1
	ownershipLabel.Position = UDim2.new(0, 16, 0, 140)
	ownershipLabel.Size = UDim2.fromOffset(348, 20)
	ownershipLabel.Font = Enum.Font.Gotham
	ownershipLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	ownershipLabel.TextSize = 16
	ownershipLabel.TextXAlignment = Enum.TextXAlignment.Left
	ownershipLabel.Text = "Owner"
	ownershipLabel.Parent = towerDetailsFrame

	upgradeDescriptionLabel = Instance.new("TextLabel")
	upgradeDescriptionLabel.Name = "UpgradeDescriptionLabel"
	upgradeDescriptionLabel.BackgroundTransparency = 1
	upgradeDescriptionLabel.Position = UDim2.new(0, 16, 0, 164)
	upgradeDescriptionLabel.Size = UDim2.fromOffset(348, 28)
	upgradeDescriptionLabel.Font = Enum.Font.Gotham
	upgradeDescriptionLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	upgradeDescriptionLabel.TextSize = 14
	upgradeDescriptionLabel.TextWrapped = true
	upgradeDescriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	upgradeDescriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	upgradeDescriptionLabel.Text = ""
	upgradeDescriptionLabel.Parent = towerDetailsFrame

	upgradeButton = Instance.new("TextButton")
	upgradeButton.Name = "UpgradeButton"
	upgradeButton.Size = UDim2.fromOffset(170, 34)
	upgradeButton.Position = UDim2.new(0, 16, 0, 198)
	upgradeButton.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
	upgradeButton.BorderSizePixel = 0
	upgradeButton.Font = Enum.Font.GothamBold
	upgradeButton.TextSize = 16
	upgradeButton.TextColor3 = Color3.new(1, 1, 1)
	upgradeButton.Text = "Upgrade"
	upgradeButton.AutoButtonColor = true
	upgradeButton.Visible = false
	upgradeButton.Parent = towerDetailsFrame

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
	sellButton.Size = UDim2.fromOffset(170, 34)
	sellButton.Position = UDim2.new(0, 194, 0, 198)
	sellButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	sellButton.BorderSizePixel = 0
	sellButton.Font = Enum.Font.GothamBold
	sellButton.TextSize = 16
	sellButton.TextColor3 = Color3.new(1, 1, 1)
	sellButton.Text = "Sell"
	sellButton.AutoButtonColor = true
	sellButton.Visible = false
	sellButton.Parent = towerDetailsFrame

	sellButtonOriginalAutoButtonColor = sellButton.AutoButtonColor

	sellButton.MouseButton1Click:Connect(function()
		if selectedTower then
			remotes.TowerSellRequested:FireServer(selectedTower)
		end
	end)

	priceLabelContainer = Instance.new("Frame")
	priceLabelContainer.Name = "PlayerTowerPriceLabels"
	priceLabelContainer.Size = UDim2.fromOffset(240, 52)
	priceLabelContainer.Position = UDim2.new(0, 190, 0, -72)
	priceLabelContainer.AnchorPoint = Vector2.new(0.5, 1)
	priceLabelContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	priceLabelContainer.BackgroundTransparency = 0.2
	priceLabelContainer.BorderSizePixel = 0
	priceLabelContainer.Visible = false
	priceLabelContainer.Parent = towerDetailsFrame

	local priceCorner = Instance.new("UICorner")
	priceCorner.CornerRadius = UDim.new(0, 10)
	priceCorner.Parent = priceLabelContainer

	upgradePriceLabel = Instance.new("TextLabel")
	upgradePriceLabel.Name = "UpgradePriceLabel"
	upgradePriceLabel.BackgroundTransparency = 1
	upgradePriceLabel.Position = UDim2.new(0, 10, 0, 6)
	upgradePriceLabel.Size = UDim2.fromOffset(200, 18)
	upgradePriceLabel.Font = Enum.Font.Gotham
	upgradePriceLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	upgradePriceLabel.TextSize = 16
	upgradePriceLabel.TextXAlignment = Enum.TextXAlignment.Left
	upgradePriceLabel.Text = "Upgrade: $0"
	upgradePriceLabel.Parent = priceLabelContainer

	sellPriceLabel = Instance.new("TextLabel")
	sellPriceLabel.Name = "SellPriceLabel"
	sellPriceLabel.BackgroundTransparency = 1
	sellPriceLabel.Position = UDim2.new(0, 10, 0, 26)
	sellPriceLabel.Size = UDim2.fromOffset(200, 18)
	sellPriceLabel.Font = Enum.Font.Gotham
	sellPriceLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	sellPriceLabel.TextSize = 16
	sellPriceLabel.TextXAlignment = Enum.TextXAlignment.Left
	sellPriceLabel.Text = "Sell: $0"
	sellPriceLabel.Parent = priceLabelContainer

	local function updateHudLayout()
		if not screenGui then
			return
		end

		local absoluteSize = screenGui.AbsoluteSize

		if shopFrame then
			local shopSize = shopFrame.AbsoluteSize
			local shopX = math.max(math.floor((absoluteSize.X - shopSize.X) * 0.5), 0)
			local shopY = math.max(absoluteSize.Y - shopSize.Y - 10, 0)
			shopFrame.Position = UDim2.fromOffset(shopX, shopY)
		end

		if statusFrame then
			local statusSize = statusFrame.AbsoluteSize
			local statusX = math.max(absoluteSize.X - statusSize.X - 20, 0)
			local statusY = math.max(absoluteSize.Y - statusSize.Y - 20, 0)
			statusFrame.Position = UDim2.fromOffset(statusX, statusY)
		end

		if towerDetailsFrame then
			local detailsSize = towerDetailsFrame.AbsoluteSize
			local detailsX = math.max(absoluteSize.X - detailsSize.X - 20, 0)
			towerDetailsFrame.Position = UDim2.fromOffset(detailsX, 20)
		end
	end

	updateHudLayout()
	task.defer(updateHudLayout)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateHudLayout)

	for _, button in pairs(shopSlotButtons) do
		connectShopButton(button)
	end

	applyLoadoutToShop()

	return screenGui
end

local function showTowerSelection()
	local gui = createSelectionGui()
	if not gui then
		return
	end

        selectionComplete = false
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
		updateStartButtonVisual()
	end)
end

if remotes:FindFirstChild("GameEnded") then
	remotes.GameEnded.OnClientEvent:Connect(function(victory)
		gameEnded = true
		lastVictoryState = victory
		updateStartButtonVisual()
	end)
end

if remotes:FindFirstChild("GameRestarted") then
	remotes.GameRestarted.OnClientEvent:Connect(function()
		gameEnded = false
		lastVictoryState = nil
		updateStartButtonVisual()
		clearSelection()
		showTowerSelection()
	end)
end

createGui()
updateStartButtonVisual()
showTowerSelection()

UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
                return
        end

        local slotIndex = SLOT_KEY_CODES[input.KeyCode]
        if slotIndex then
                if selectionScreenGui and selectionScreenGui.Enabled then
                        setActiveSelectionSlot(math.clamp(slotIndex, 1, LOADOUT_SLOT_COUNT))
                else
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
	updatePriceLabelHoverState()

	if selectedTower and (not selectedTower.Parent) then
		clearSelection()
	end
end)
