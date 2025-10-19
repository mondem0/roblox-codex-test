local EnemyConfigs = {
    Grunt = {
        Name = "Grunt",
        ModelName = "Grunt",
        Health = 60,
        Speed = 12,
        Reward = 15
    },
    Runner = {
        Name = "Runner",
        ModelName = "Runner",
        Health = 45,
        Speed = 18,
        Reward = 12
    },
    Tank = {
        Name = "Tank",
        ModelName = "Tank",
        Health = 160,
        Speed = 8,
        Reward = 35
    },
    Shielder = {
        Name = "Bulwark Captain",
        ModelName = "Shielder",
        Health = 320,
        Speed = 9,
        Reward = 60,
        DebuffImmunities = { Explosion = true },
        SpawnSound = {
            SoundId = "rbxassetid://1234567890",
            Volume = 0.8,
            StartTime = 0.15,
        },
        DeathSound = {
            SoundId = "rbxassetid://1234567891",
            Volume = 1.1,
        },
    },
    Boss1 = {
        Name = "Obsidian Colossus",
        ModelName = "Boss1",
        Health = 600,
        Speed = 10,
        Reward = 150,
        DebuffImmunities = { Slow = true },
        SpawnSound = {
            SoundId = "rbxassetid://1234567892",
            Volume = 1.2,
        },
        DeathSound = "rbxassetid://1234567893",
    },
    LightningBoss = {
        Name = "Storm Tyrant",
        ModelName = "LightningBoss",
        Health = 850,
        Speed = 12,
        Reward = 225,
        DebuffImmunities = { Slow = true },
        SpawnSound = "rbxassetid://1234567894",
        DeathSound = {
            SoundId = "rbxassetid://1234567895",
            Volume = 1.3,
        },
    },
    Riftbreaker = {
        Name = "Riftbreaker Aethron",
        ModelName = "VoidReaver",
        Health = 1400,
        Speed = 11,
        Reward = 420,
        DebuffImmunities = { Slow = true },
        SpawnSound = {
            SoundId = "rbxassetid://1234567899",
            Volume = 1.25,
            StartTime = 0.1,
        },
        DeathSound = {
            SoundId = "rbxassetid://1234567900",
            Volume = 1.35,
        },
        Abilities = {
            SkipWaypoints = {
                {
                    TriggerPercent = 65,
                    SkipCount = 1,
                    Pathfind = true,
                    Sound = {
                        SoundId = "rbxassetid://1234567901",
                        Volume = 1.1,
                        StartTime = 0.2,
                    },
                },
                {
                    TriggerPercent = 35,
                    SkipCount = 2,
                    Pathfind = true,
                    Sound = {
                        SoundId = "rbxassetid://1234567905",
                        Volume = 1.05,
                    },
                    SoundName = "RiftbreakerWarp",
                },
            },
            StunPulse = {
                {
                    TriggerPercent = 25,
                    Radius = 18,
                    Duration = 4.5,
                    EffectColor = { 170, 80, 255 },
                    PulseSound = {
                        SoundId = "rbxassetid://1234567903",
                        Volume = 1.15,
                    },
                    PulseSoundName = "RiftbreakerStunPulse",
                    Sound = {
                        SoundId = "rbxassetid://1234567902",
                        Volume = 1.15,
                        StartTime = 0.35,
                    },
                    SoundName = "RiftbreakerStun",
                },
                {
                    TriggerPercent = 10,
                    Radius = 22,
                    Duration = 6,
                    EffectColor = { 255, 120, 220 },
                    PulseSoundName = "RiftbreakerFinalPulse",
                    Sound = "rbxassetid://1234567904",
                },
            },
        },
    },
    FrostWarden = {
        Name = "Frost Warden",
        ModelName = "FrostWarden",
        Health = 380,
        Speed = 10,
        Reward = 140,
        TowerStunOnDeath = {
            Radius = 14,
            Duration = 4.5,
            PulseSound = {
                SoundId = "rbxassetid://1234567897",
                Volume = 1,
            },
            PulseSoundName = "FrostWardenPulse",
            Sound = {
                SoundId = "rbxassetid://1234567896",
                Volume = 0.95,
                StartTime = 0.35,
            },
            SoundName = "FrostWardenStun",
            EffectColor = { 130, 220, 255 },
        },
    },
    Warcaller = {
        Name = "Aether Warcaller",
        ModelName = "Warcaller",
        Health = 520,
        Speed = 10,
        Reward = 185,
        SpawnSound = {
            SoundId = "rbxassetid://1234567906",
            Volume = 1.15,
            StartTime = 0.2,
        },
        DeathSound = {
            SoundId = "rbxassetid://1234567907",
            Volume = 1.2,
        },
        Abilities = {
            SpawnUnits = {
                {
                    TriggerPercent = 70,
                    Spawns = {
                        { Type = "Runner", Count = 3, OffsetRadius = 4, PlaySpawnSound = true },
                        { Type = "Grunt", Count = 2, ProgressOffset = -0.03 },
                    },
                    ProgressSpacing = 0.025,
                },
                {
                    TriggerPercent = 40,
                    Spawns = {
                        { Type = "Shade", Count = 2, OffsetRadius = 5, PlaySpawnSound = true },
                        { Type = "Broodling", Count = 3, ProgressSpacing = 0.035 },
                    },
                    Interval = 0.3,
                    StartDelay = 0.6,
                    ProgressOffset = 0.02,
                },
            },
        },
    },
    Shade = {
        Name = "Umbral Shade",
        ModelName = "Shade",
        Health = 140,
        Speed = 16,
        Reward = 65,
        Hidden = true,
        SpawnSound = {
            SoundId = "rbxassetid://1234567897",
            Volume = 0.7,
            StartTime = 0.2,
        },
        DeathSound = {
            SoundId = "rbxassetid://1234567898",
            Volume = 0.9,
        },
    },
    Broodling = {
        Name = "Broodling",
        ModelName = "Runner",
        Health = 30,
        Speed = 18,
        Reward = 10,
    },
    Broodmother = {
        Name = "Broodmother",
        ModelName = "Tank",
        Health = 320,
        Speed = 9,
        Reward = 95,
        SplitChildren = {
            {
                Type = "Runner",
                Count = 2,
                ProgressSpacing = 0.05,
                OffsetRadius = 3,
            },
            {
                Type = "Broodling",
                Count = 3,
                ProgressOffset = -0.04,
                ProgressSpacing = 0.05,
                PlaySpawnSound = true,
            },
        },
    }
}

return EnemyConfigs
