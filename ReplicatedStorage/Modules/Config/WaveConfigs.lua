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
	Description = "Introduces Grunts",
	Reward = 65,
	Groups = {
		{ Type = "Grunt", Count = 10, Delay = 0.8 },
	},
})

addWave({
	Name = "wave2",
	Description = "Introduces Runners",
	Reward = 75,
	Groups = {
		{ Type = "Grunt", Count = 10, Delay = 0.7 },
		{ Type = "Runner", Count = 5, Delay = 0.5 },
		{
			Spawns = {
				{ Type = "Grunt" },
				{ Type = "Runner" },
			},
			Repeat = 3,
			Delay = 1,
		},
	},
})

addWave({
	Name = "wave3",
	Description = "Grunt, Runner and introduced Tanks",
	Reward = 90,
	Groups = {
		{
			Spawns = {
				{ Type = "Runner" },
				{ Type = "Grunt" },
			},
			Repeat = 20,
			Delay = 0.5,
		},
		{ Type = "Tank", Count = 5, Delay = 1.3 },
	},
})

addWave({
	Name = "wave4",
	Description = "Introduces Lightning",
	Reward = 110,
	Groups = {
		{ Type = "Tank", Count = 10, Delay = 0.8 },
		{
			Spawns = {
				{ Type = "Lightning" },
				{ Type = "Runner" },
			},
			Repeat = 7,
			Delay = 0.5,
		},
	},
})

addWave({
	Name = "wave5",
	Description = "Chiller wave + introduces Shielder",
	Reward = 140,
	Groups = {
		{ Type = "Lightning", Count = 15, Delay = 0.25 },
		{ Type = "Shielder", Count = 5, Delay = 0.5 },
	},
})

addWave({
	Name = "wave6",
	Description = "Boss wave",
	Reward = 140,
	Groups = {
		{ Type = "Tank", Count = 20, Delay = 0.6 },
		{ Type = "Shielder", Count = 15, Delay = 0.8 },
		{ Type = "Lightning", Count = 20, Delay = 0.15 },
		{ Type = "Tank", Count = 25, Delay = 0.6 },
		{ Type = "Boss1", Count = 1, Delay = 0 },
	},
})

addWave({
	Name = "wave7",
	Description = "Fast wave",
	Reward = 180,
	Groups = {
		{
			Spawns = {
				{ Type = "Shielder" },
				{ Type = "Lightning" },
			},
			Repeat = 25,
			Delay = 0.5,
		},
		{ Type = "Lightning", Count = 35, Delay = 0.15 },
	},
})

addWave({
	Name = "wave8",
	Description = "Lightning Boss wave",
	Reward = 250,
	Groups = {
		{ Type = "Boss1", Count = 3, Delay = 15 },
		{ Type = "Lightning", Count = 15, Delay = 0.15 },
		{ Type = "Shielder", Count = 10, Delay = 0.8 },
		{ Type = "LightningBoss", Count = 1, Delay = 0 },
	},
})

waves.Definitions = waveDefinitions
waves.AddWave = addWave
waves.DefaultNamePattern = defaultNamePattern

return waves
