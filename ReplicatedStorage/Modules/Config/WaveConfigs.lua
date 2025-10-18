local WaveConfigs = {
    {
        { Type = "Grunt", Count = 12, Delay = 0.75, BatchSize = 2 },
    },
    {
        { Type = "Grunt", Count = 14, Delay = 0.7 },
        {
            Types = {
                { Type = "Grunt", Count = 1 },
                { Type = "Runner", Count = 1 },
            },
            Repeat = 4,
            Delay = 0.85,
        },
    },
    {
        { Type = "Runner", Count = 12, Delay = 0.55 },
        {
            Types = {
                { Type = "Runner", Count = 1 },
                { Type = "Tank", Count = 1 },
            },
            Repeat = 3,
            Delay = 1.25,
        },
        { Type = "Grunt", Count = 12, Delay = 0.6 },
    },
    {
        { Type = "Tank", Count = 6, Delay = 1.3, BatchSize = 2 },
        { Type = "Runner", Count = 10, Delay = 0.6 },
    },
    {
        { Type = "Grunt", Count = 20, Delay = 0.6, BatchSize = 2 },
        { Type = "Tank", Count = 8, Delay = 1.1, BatchSize = 2 },
        { Type = "Runner", Count = 12, Delay = 0.55 },
    },
}

return WaveConfigs
