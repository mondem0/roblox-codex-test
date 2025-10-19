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
            Streams = {
                { Type = "Grunt", Count = 10, Interval = 0.8 },
                { Type = "Runner", Count = 10, Interval = 0.6, StartDelay = 0.4 },
            },
            Delay = 1,
        },
    },
})

addWave({
    Name = "wave3",
    Description = "Faster mixed packs that challenge maze coverage.",
    Reward = 90,
    Groups = {
        {
            Streams = {
                { Type = "Runner", Count = 12, Interval = 0.5 },
                { Type = "Grunt", Count = 6, Interval = 0.7, StartDelay = 0.35 },
            },
            Delay = 0.8,
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
            Streams = {
                { Type = "Runner", Count = 10, Interval = 0.55 },
                { Type = "Grunt", Count = 5, Interval = 0.75, StartDelay = 0.3 },
            },
            Delay = 0.9,
        },
    },
})

addWave({
    Name = "wave5",
    Description = "Shield phalanx introduces explosion-resistant frontline units.",
    Reward = 150,
    Groups = {
        { Type = "Runner", Count = 10, Delay = 0.6 },
        {
            Streams = {
                { Type = "Shielder", Count = 5, Interval = 1.25 },
                { Type = "Tank", Count = 5, Interval = 1.1, StartDelay = 0.6 },
            },
            Delay = 1.4,
        },
        { Type = "Grunt", Count = 12, Delay = 0.5 },
    },
})

addWave({
    Name = "wave6",
    Description = "Storm Tyrant arrives with unstoppable, explosion-proof bodyguards.",
    Reward = 260,
    Groups = {
        {
            Streams = {
                { Type = "Shielder", Count = 3, Interval = 1.5 },
                { Type = "Tank", Count = 3, Interval = 1.1, StartDelay = 0.75 },
            },
            Delay = 1.6,
        },
        { Type = "Boss1", Count = 2, Delay = 2.5 },
        { Type = "LightningBoss", Count = 1 },
    },
    Metadata = {
        Notes = "Bosses ignore slow effects while Shielders shrug off untargeted splash damage.",
    },
})

addWave({
    Name = "wave7",
    Description = "Broodmothers split into fresh attackers the moment they fall.",
    Reward = 210,
    Groups = {
        {
            Streams = {
                { Type = "Broodmother", Count = 4, Interval = 2.4 },
                { Type = "Runner", Count = 12, Interval = 0.7, StartDelay = 1.2 },
            },
            Delay = 1.8,
        },
        {
            Type = "Broodmother",
            Count = 3,
            Delay = 2.8,
        },
    },
    Metadata = {
        Notes = "Broodmothers split into Broodlings and Runners—keep splash damage ready to mop up.",
    },
})

addWave({
    Name = "wave8",
    Description = "Frost Warden shockwaves disable towers that collapse too close.",
    Reward = 280,
    Groups = {
        { Type = "FrostWarden", Count = 3, Delay = 3 },
        {
            Streams = {
                { Type = "Runner", Count = 14, Interval = 0.55 },
                { Type = "FrostWarden", Count = 3, Interval = 3.25, StartDelay = 1.4 },
            },
            Delay = 2.2,
        },
        {
            Type = "LightningBoss",
            Count = 1,
            Delay = 2.8,
        },
    },
    Metadata = {
        Notes = "Frost Wardens freeze nearby towers on death—spread your defenses to avoid chain stuns.",
    },
})

waves.Definitions = waveDefinitions
waves.AddWave = addWave
waves.DefaultNamePattern = defaultNamePattern

return waves
