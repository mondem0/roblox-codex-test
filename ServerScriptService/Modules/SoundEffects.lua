local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Workspace = workspace

local DEFAULT_LIFETIME = 6

local SOUND_ID_KEYS = {
    "SoundId",
    "SoundID",
    "soundId",
    "soundID",
    "Id",
    "id",
    "AssetId",
    "assetId",
    "AssetID",
    "assetID",
    "Asset",
    "asset",
}

local START_TIME_KEYS = {
    "TimePosition",
    "StartTime",
    "StartPosition",
    "StartAt",
}

local function extractSoundId(config)
    if type(config) ~= "table" then
        return nil
    end

    for _, key in ipairs(SOUND_ID_KEYS) do
        local value = config[key]
        if value then
            return value
        end
    end

    if config[1] then
        return config[1]
    end

    return nil
end

local function applyProperties(sound, properties)
    for key, value in pairs(properties) do
        if type(key) == "string" then
            local lowerKey = string.lower(key)
            if lowerKey ~= "soundid" and lowerKey ~= "id" and lowerKey ~= "assetid" and lowerKey ~= "asset" then
                pcall(function()
                    sound[key] = value
                end)
            end
        end
    end
end

local function extractStartTime(source)
    if type(source) ~= "table" then
        return nil
    end

    for _, key in ipairs(START_TIME_KEYS) do
        local value = source[key]
        if value ~= nil then
            local numberValue = tonumber(value)
            if numberValue and numberValue >= 0 then
                return numberValue
            end
        end
    end

    return nil
end

local SoundEffects = {}

function SoundEffects.CreateSound(config)
    if not config then
        return nil
    end

    if typeof(config) == "Instance" and config:IsA("Sound") then
        return config:Clone()
    elseif type(config) == "string" then
        local sound = Instance.new("Sound")
        sound.SoundId = config
        return sound
    elseif type(config) == "table" then
        local soundId = extractSoundId(config)
        if not soundId then
            return nil
        end

        local sound = Instance.new("Sound")
        sound.SoundId = soundId
        applyProperties(sound, config)

        local startTime = extractStartTime(config)
        if startTime then
            sound.TimePosition = startTime
        end

        return sound
    end

    return nil
end

function SoundEffects.Play(parent, config, options)
    local sound = SoundEffects.CreateSound(config)
    if not sound then
        return nil
    end

    options = options or {}

    if options.Name and options.Name ~= "" then
        sound.Name = options.Name
    elseif not sound.Name or sound.Name == "" then
        sound.Name = "SoundEffect"
    end

    local anchor
    local targetParent
    if typeof(parent) == "Instance" then
        targetParent = parent
    elseif options.Position then
        anchor = Instance.new("Part")
        anchor.Name = options.AnchorName or "SoundAnchor"
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanQuery = false
        anchor.CanTouch = false
        anchor.CastShadow = false
        anchor.Transparency = 1
        anchor.Size = Vector3.new(0.1, 0.1, 0.1)
        anchor.CFrame = CFrame.new(options.Position)
        anchor.Parent = Workspace
        targetParent = anchor
    else
        targetParent = SoundService
    end

    sound.Parent = targetParent

    local startTime
    if options then
        startTime = extractStartTime(options)
    end

    if not startTime then
        startTime = extractStartTime(config)
    end

    if startTime then
        sound.TimePosition = startTime
    end

    if not sound.Looped then
        sound.Ended:Connect(function()
            if sound.Parent then
                sound:Destroy()
            end
        end)
    end

    sound:Play()

    local cleanupTime = options.Lifetime
    if not cleanupTime or cleanupTime <= 0 then
        cleanupTime = sound.TimeLength
        if not cleanupTime or cleanupTime <= 0 then
            cleanupTime = DEFAULT_LIFETIME
        else
            cleanupTime += 0.25
        end
    end

    Debris:AddItem(sound, cleanupTime)
    if anchor then
        Debris:AddItem(anchor, cleanupTime)
    end

    return sound
end

return SoundEffects
