--!strict

-- All prices are earned coins. This alpha has no Robux products.
local EconomyConfig = {
	Trails = {
		{ Id = "None", Name = "Без следа", Price = 0, Color = Color3.fromRGB(220, 229, 255) },
		{ Id = "Cyan", Name = "Ионный след", Price = 60, Color = Color3.fromRGB(67, 218, 255) },
		{
			Id = "Pink",
			Name = "Розовая комета",
			Price = 100,
			Color = Color3.fromRGB(255, 115, 173),
		},
		{
			Id = "Gold",
			Name = "Золотая искра",
			Price = 180,
			Color = Color3.fromRGB(255, 213, 79),
		},
		{
			Id = "Emerald",
			Name = "Изумрудный импульс",
			Price = 260,
			Color = Color3.fromRGB(66, 220, 169),
		},
	},
	Quests = {
		survive = { Name = "Пройди 8 испытаний", Target = 8, Reward = 50 },
		stars = { Name = "Собери 10 зарядов", Target = 10, Reward = 50 },
		runs = { Name = "Заверши 2 забега", Target = 2, Reward = 60 },
	},
	Rewards = {
		SurvivalCoins = 12,
		SurvivalXP = 20,
		StarCoins = 2,
		StarXP = 3,
		RunCoins = 15,
		RunXP = 25,
		WinCoins = 20,
	},
	Persistence = {
		StoreName = "RuleRoomProfiles_v1",
		TestStoreName = "RuleRoomProfiles_TEST_v1",
		-- Studio stays in memory until BOTH an explicit opt-in and sandbox ID match.
		StudioDataStoreEnabled = false,
		TestPlaceId = 0,
		LeaseSeconds = 180,
		AutosaveSeconds = 45,
		RequestTimeoutSeconds = 15,
		ShutdownSeconds = 25,
	},
}

return EconomyConfig
