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
    Boss1 = {
        Name = "Obsidian Colossus",
        ModelName = "Boss1",
        Health = 600,
        Speed = 10,
        Reward = 150,
        DebuffImmunities = { Slow = true },
    },
    LightningBoss = {
        Name = "Storm Tyrant",
        ModelName = "LightningBoss",
        Health = 850,
        Speed = 12,
        Reward = 225,
        DebuffImmunities = { Slow = true },
    }
}

return EnemyConfigs
