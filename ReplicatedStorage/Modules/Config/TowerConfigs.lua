local TowerConfigs = {
    Archer = {
        Name = "Archer",
        Cost = 150,
        Range = 18,
        Damage = 8,
        FireRate = 0.75,
        Targeting = "First",
        Upgrades = {
            {
                Cost = 200,
                Range = 20,
                Damage = 12,
                FireRate = 0.65,
                Description = "+4 damage, +2 range, slightly faster"
            },
            {
                Cost = 350,
                Range = 24,
                Damage = 18,
                FireRate = 0.5,
                Description = "+6 damage, +4 range, much faster"
            }
        }
    },
    Cannon = {
        Name = "Cannon",
        Cost = 250,
        Range = 22,
        Damage = 20,
        FireRate = 1.5,
        SplashRadius = 6,
        Targeting = "Strong",
        Upgrades = {
            {
                Cost = 300,
                Range = 24,
                Damage = 28,
                SplashRadius = 7,
                FireRate = 1.35,
                Description = "Bigger explosion, more damage"
            },
            {
                Cost = 500,
                Range = 28,
                Damage = 40,
                SplashRadius = 8,
                FireRate = 1.1,
                Description = "Heavy shells devastate clusters"
            }
        }
    },
    FrostMage = {
        Name = "Frost Mage",
        Cost = 200,
        Range = 20,
        Damage = 6,
        FireRate = 1.25,
        SlowDuration = 2.5,
        SlowPercent = 0.35,
        Targeting = "First",
        Upgrades = {
            {
                Cost = 280,
                Range = 22,
                Damage = 8,
                SlowDuration = 3,
                SlowPercent = 0.4,
                Description = "Longer slows and extra damage"
            },
            {
                Cost = 420,
                Range = 26,
                Damage = 11,
                SlowDuration = 3.5,
                SlowPercent = 0.5,
                Description = "Freezing blasts cripple enemies"
            }
        }
    }
}

return TowerConfigs
