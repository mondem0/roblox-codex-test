local waves = {}
local waveDefinitions = {}
local defaultNamePattern = "wave%d"

local function cloneTable(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function applyMetadataDefaults(metadata)
    metadata.Reward = metadata.Reward or 75
    metadata.Description = metadata.Description or ""
    return metadata
end

local function addWave(definition)
    assert(type(definition) == "table", "Wave definition must be a table")

    local groups = definition.Groups or definition
    assert(type(groups) == "table", "Wave definition must include a Groups table or be an array of groups")

    local index = #waves + 1
    local name = definition.Name or string.format(defaultNamePattern, index)

    waves[index] = groups
    waves[name] = groups

    if definition.Groups then
        local metadata = cloneTable(definition)
        metadata.Index = index
        metadata.Name = name
        metadata.Groups = groups
        applyMetadataDefaults(metadata)

        waveDefinitions[index] = metadata
        waveDefinitions[name] = metadata
    else
        local metadata = applyMetadataDefaults({
            Index = index,
            Name = name,
            Groups = groups,
        })

        waveDefinitions[index] = metadata
        waveDefinitions[name] = metadata
    end

    return groups
end

addWave({
    Name = "wave1",
    Description = "Warm-up wave of slow Grunts to let players place their first towers.",
    Reward = 65,
    Groups = {
        { Type = "Grunt", Count = 12, Delay = 0.75 },
    },
})

addWave({
    Name = "wave2",
    Description = "Introduces Runners while keeping a steady trickle of Grunts.",
    Reward = 75,
    Groups = {
        { Type = "Grunt", Count = 14, Delay = 0.7 },
        { Type = "Runner", Count = 6, Delay = 0.6 },
        {
            Spawns = {
                { Type = "Grunt", Count = 2 },
                { Type = "Runner", Count = 1 },
            },
            Repeat = 4,
            Delay = 0.65,
        },
    },
})

addWave({
    Name = "wave3",
    Description = "Faster mixed packs that challenge maze coverage.",
    Reward = 90,
    Groups = {
        {
            Spawns = {
                { Type = "Runner", Count = 2 },
                { Type = "Grunt", Count = 1 },
            },
            Repeat = 6,
            Delay = 0.55,
        },
        { Type = "Grunt", Count = 16, Delay = 0.65 },
    },
})

addWave({
    Name = "wave4",
    Description = "Adds Tanks to force single-target upgrades.",
    Reward = 110,
    Groups = {
        { Type = "Tank", Count = 6, Delay = 1.3 },
        {
            Spawns = {
                { Type = "Runner", Count = 2 },
                { Type = "Grunt", Count = 1 },
            },
            Repeat = 5,
            Delay = 0.6,
        },
    },
})

addWave({
    Name = "wave5",
    Description = "Final exam with simultaneous Tank support.",
    Reward = 140,
    Groups = {
        {
            Spawns = {
                { Type = "Grunt", Count = 2 },
                { Type = "Tank", Count = 1 },
            },
            Repeat = 6,
            Delay = 0.7,
        },
        { Type = "Runner", Count = 12, Delay = 0.55 },
    },
})

waves.Definitions = waveDefinitions
waves.AddWave = addWave
waves.DefaultNamePattern = defaultNamePattern

return waves
