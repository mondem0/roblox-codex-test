local TowerConfigs = {
    OverallPlacementLimit = {
        PerPlayer = 40,
        Global = 120,
    },
    Archer = {
        Name = "Archer",
        ModelName = "Archer",
        Cost = 150,
        PlacementLimit = 12,
        BaseSize = Vector3.new(4, 1, 4),
        Range = 18,
        Damage = 8,
        FireRate = 0.75,
        Targeting = "First",
        HiddenDetection = true,
        FireSound = "rbxassetid://2234567890",
        Upgrades = {
            {
                Cost = 200,
                Range = 20,
                Damage = 12,
                FireRate = 0.65,
                ModelName = "ArcherTier2",
                Description = "+4 damage, +2 range, slightly faster"
            },
            {
                Cost = 350,
                Range = 24,
                Damage = 18,
                FireRate = 0.5,
                ModelName = "ArcherTier3",
                Description = "+6 damage, +4 range, much faster"
            }
        }
    },
    Cannon = {
        Name = "Cannon",
        ModelName = "Cannon",
        Cost = 250,
        PlacementLimit = {
            PerPlayer = 4,
            Global = 12,
        },
        BaseSize = Vector3.new(4.5, 1.2, 4.5),
        Range = 22,
        Damage = 20,
        FireRate = 1.5,
        SplashRadius = 6,
        SplashColor = Color3.fromRGB(255, 170, 95),
        Targeting = "Strong",
        FireSound = {
            SoundId = "rbxassetid://2234567891",
            Volume = 1.2,
            StartTime = 0.1,
        },
        Upgrades = {
            {
                Cost = 300,
                Range = 24,
                Damage = 28,
                SplashRadius = 7,
                FireRate = 1.35,
                ModelName = "CannonMk2",
                Description = "Bigger explosion, more damage"
            },
            {
                Cost = 500,
                Range = 28,
                Damage = 40,
                SplashRadius = 8,
                FireRate = 1.1,
                ModelName = "CannonMk3",
                Description = "Heavy shells devastate clusters"
            }
        }
    },
    FrostMage = {
        Name = "Frost Mage",
        ModelName = "FrostMage",
        Cost = 200,
        PlacementLimit = 8,
        BaseSize = Vector3.new(4, 1, 4),
        Range = 20,
        Damage = 6,
        FireRate = 1.25,
        SlowDuration = 2.5,
        SlowPercent = 0.35,
        Targeting = "First",
        FireSound = {
            SoundId = "rbxassetid://2234567892",
            Volume = 0.9,
            TimePosition = 0.2,
        },
        Upgrades = {
            {
                Cost = 280,
                Range = 22,
                Damage = 8,
                SlowDuration = 3,
                SlowPercent = 0.4,
                ModelName = "FrostMageAdept",
                Description = "Longer slows and extra damage"
            },
            {
                Cost = 420,
                Range = 26,
                Damage = 11,
                SlowDuration = 3.5,
                SlowPercent = 0.5,
                ModelName = "FrostMageArchon",
                Description = "Freezing blasts cripple enemies"
            }
        }
    },
    CliffSniper = {
        Name = "Cliff Sniper",
        ModelName = "CliffSniper",
        Cost = 400,
        PlacementLimit = 6,
        PlacementSurface = "Cliff",
        PlacementSurfaceParts = { "CliffPlacement" },
        BaseSize = Vector3.new(3.5, 1, 3.5),
        Range = 40,
        Damage = 30,
        FireRate = 2.25,
        Targeting = "Strong",
        HiddenDetection = true,
        FireSound = {
            SoundId = "rbxassetid://2234567893",
            Volume = 1,
        },
        Upgrades = {
            {
                Cost = 450,
                Range = 44,
                Damage = 42,
                FireRate = 1.9,
                ModelName = "CliffSniperTier2",
                Description = "+12 damage, +4 range, faster shots",
            },
            {
                Cost = 650,
                Range = 50,
                Damage = 60,
                FireRate = 1.6,
                ModelName = "CliffSniperTier3",
                Description = "Massive range and high-powered rounds",
            }
        }
    },
    Farm = {
        Name = "Farm",
        ModelName = "Farm",
        Cost = 300,
        PlacementLimit = 12,
        BaseSize = Vector3.new(5, 1, 5),
        Range = 0,
        Damage = 0,
        FireRate = 10,
        IncomePerWave = 125,
        Description = "Generates bonus cash at the start of each wave.",
    }
}

return TowerConfigs
