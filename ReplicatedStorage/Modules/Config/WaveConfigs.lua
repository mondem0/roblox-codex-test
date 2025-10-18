local WaveConfigs = {
    {
        { Type = "Grunt", Count = 12, Delay = 0.75 },
    },
    {
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
    {
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
    {
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
    {
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
}

return WaveConfigs
