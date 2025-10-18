local TowerConfigs = {
	Soldier = {
		Name = "Soldier",
		ModelName = "Soldier",
		Cost = 150,
		BaseSize = Vector3.new(4, 1, 4),
		Range = 15,
		Damage = 8,
		FireRate = 0.75,
		Targeting = "First",
		Upgrades = {
			{
				Cost = 350,
				Range = 18,
				Damage = 10,
				FireRate = 0.65,
				Description = "More damage, sligtly faster"
			},
			{
				Cost = 600,
				Range = 21,
				Damage = 14,
				FireRate = 0.5,
				Description = "Even more damage, much faster"
			}
		}
	},
	Cannon = {
		Name = "Cannon",
		ModelName = "Cannon",
		Cost = 250,
		BaseSize = Vector3.new(5.6, 1, 5.6),
		Range = 17,
		Damage = 15,
		FireRate = 1.5,
		SplashColor = Color3.fromRGB(255, 170, 95),
		Targeting = "First",
		Upgrades = {
			{
				Cost = 400,
				Range = 20,
				Damage = 25,
				SplashRadius = 6,
				FireRate = 1.35,
				Description = "Adds an explosion"
			},
			{
				Cost = 700,
				Range = 23,
				Damage = 30,
				SplashRadius = 8,
				FireRate = 1.1,
				Description = "Bigger explosion"
			}
		}
	},
	FrostMage = {
		Name = "Frost Cannon",
		ModelName = "FrostCannon",
		Cost = 200,
		BaseSize = Vector3.new(4.6, 1, 4.6),
		Range = 13,
		Damage = 6,
		FireRate = 1.75,
		SlowDuration = 2.5,
		SlowPercent = 0.35,
		SplashColor = Color3.fromRGB(0, 81, 255),
		SplashRadius = 4,
		Targeting = "First",
		Upgrades = {
			{
				Cost = 400,
				Range = 17,
				Damage = 8,
				SlowDuration = 3,
				SlowPercent = 0.4,
				Description = "Longer slows and extra damage"
			},
			{
				Cost = 600,
				Range = 20,
				Damage = 12,
				SlowDuration = 3.5,
				SlowPercent = 0.5,
				Description = "Freezing blasts cripple enemies"
			}
		}
	}
}

return TowerConfigs
