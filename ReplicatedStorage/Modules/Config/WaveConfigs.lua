local wave1 = {
    { Type = "Grunt", Count = 12, Delay = 0.75 },
}

local wave2 = {
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
}

local wave3 = {
    {
        Spawns = {
            { Type = "Runner", Count = 2 },
            { Type = "Grunt", Count = 1 },
        },
        Repeat = 6,
        Delay = 0.55,
    },
    { Type = "Grunt", Count = 16, Delay = 0.65 },
}

local wave4 = {
    { Type = "Tank", Count = 6, Delay = 1.3 },
    {
        Spawns = {
            { Type = "Runner", Count = 2 },
            { Type = "Grunt", Count = 1 },
        },
        Repeat = 5,
        Delay = 0.6,
    },
}

local wave5 = {
    {
        Spawns = {
            { Type = "Grunt", Count = 2 },
            { Type = "Tank", Count = 1 },
        },
        Repeat = 6,
        Delay = 0.7,
    },
    { Type = "Runner", Count = 12, Delay = 0.55 },
}

--
-- Expose each wave both by name (wave1, wave2, …) and by numeric index so
-- existing wave iteration logic continues to function unchanged while keeping
-- the configuration easy to scan in Studio.
--
local namedWaves = {
    wave1 = wave1,
    wave2 = wave2,
    wave3 = wave3,
    wave4 = wave4,
    wave5 = wave5,
}

local ordered = {
    namedWaves.wave1,
    namedWaves.wave2,
    namedWaves.wave3,
    namedWaves.wave4,
    namedWaves.wave5,
}

for index, wave in ipairs(ordered) do
    namedWaves[index] = wave
end

return namedWaves
