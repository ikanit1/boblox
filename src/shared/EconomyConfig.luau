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
		-- Mastery rewards are free claims, not more expensive coin sinks.
		{
			Id = "Aurora",
			Name = "Полярное сияние",
			Price = 0,
			UnlockTitle = "Practice",
			Color = Color3.fromRGB(85, 255, 190),
			ColorEnd = Color3.fromRGB(120, 95, 255),
			WidthScale = 0.85,
			Lifetime = 0.38,
			Style = "Широкая зелёно-фиолетовая лента",
		},
		{
			Id = "Prism",
			Name = "Спектральная лента",
			Price = 0,
			UnlockTitle = "Collector",
			Color = Color3.fromRGB(255, 120, 205),
			ColorEnd = Color3.fromRGB(90, 225, 255),
			WidthScale = 0.42,
			Lifetime = 0.48,
			Style = "Тонкая длинная розово-голубая лента",
		},
		{
			Id = "Solar",
			Name = "Солнечный шлейф",
			Price = 0,
			UnlockTitle = "PerfectRun",
			Color = Color3.fromRGB(255, 240, 180),
			ColorEnd = Color3.fromRGB(255, 100, 45),
			WidthScale = 1,
			Lifetime = 0.32,
			Style = "Широкий короткий золотисто-огненный шлейф",
		},
		{
			Id = "Nova",
			Name = "Пульс созвездия",
			Price = 0,
			UnlockTitle = "TeamVeteran",
			Color = Color3.fromRGB(155, 130, 255),
			ColorEnd = Color3.fromRGB(240, 250, 255),
			WidthScale = 0.72,
			Lifetime = 0.5,
			Style = "Длинный фиолетово-белый шлейф",
		},
	},
	-- Permanent goals award titles only; they never alter survival odds or currency.
	MasteryMilestones = {
		{
			Id = "FirstRun",
			Title = "Первый шаг",
			Description = "Заверши забег: пройди хотя бы одно испытание и собери звезду или энергию.",
			Goal = "Забег с собранной звездой или энергией",
			Target = 1,
		},
		{
			Id = "PerfectRun",
			Title = "Покоритель комнаты",
			Description = "Выживи во всех 6 испытаниях, собери энергию реактора и победи лично.",
			Goal = "Победа 6/6 с вкладом в реактор",
			Target = 1,
		},
		{
			Id = "Collector",
			Title = "Точный собиратель",
			Description = "Собери предмет и выживи без урона и нарушений в каждом из трёх правил: Лунная комната, Замри, Реактор.",
			Goal = "Разные испытания с чистым сбором",
			Target = 3,
		},
		{
			Id = "Practice",
			Title = "Паркурист",
			Description = "Пройди все контрольные точки паркура и достигни финиша.",
			Goal = "Полное прохождение паркура",
			Target = 1,
		},
		{
			Id = "TeamVeteran",
			Title = "Опора команды",
			Description = "Победи лично в 5 забегах, каждый раз собрав энергию реактора.",
			Goal = "Личные победы с вкладом в реактор",
			Target = 5,
		},
	},
	Quests = {
		survive = { Name = "Пройди 8 испытаний", Target = 8, Reward = 50 },
		stars = { Name = "Собери 10 ★ или ⚡", Target = 10, Reward = 50 },
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

local function count(value: unknown): number
	return if type(value) == "number"
			and value == value
			and value >= 0
			and value <= 1_000_000_000
		then math.floor(value)
		else 0
end

-- Display policy only. ProfileData validates every ownership and unlock request on the server.
function EconomyConfig.trailState(trail: any, read: (string) -> unknown): any
	local owned = trail.Id == "None" or read("Owned_" .. trail.Id) == true
	if owned then
		local equipped = read("EquippedTrail") == trail.Id
		return {
			Kind = if equipped then "Equipped" else "Owned",
			Action = if equipped then nil else "Equip",
			Remaining = 0,
		}
	end
	if trail.UnlockTitle and read("UnlockedTitle_" .. trail.UnlockTitle) ~= true then
		return { Kind = "Locked", Action = nil, Remaining = 0 }
	end
	local remaining = math.max(0, trail.Price - count(read("Coins")))
	return {
		Kind = if trail.UnlockTitle
			then "Available"
			elseif remaining == 0 then "Affordable"
			else "Unaffordable",
		Action = if remaining == 0 then "Purchase" else nil,
		Remaining = remaining,
	}
end

function EconomyConfig.nextTrailGoal(read: (string) -> unknown): string?
	local best, bestState, bestRank = nil, nil, math.huge
	for _, trail in EconomyConfig.Trails do
		local state = EconomyConfig.trailState(trail, read)
		local rank = if state.Kind == "Available"
			then 0
			elseif state.Kind == "Affordable" then 1
			elseif state.Kind == "Unaffordable" then 2
			elseif state.Kind == "Locked" then 3
			else math.huge
		if rank < bestRank or (rank == 2 and rank == bestRank and state.Remaining < bestState.Remaining) then
			best, bestState, bestRank = trail, state, rank
		end
	end
	if not best then
		return nil
	end
	if bestState.Kind == "Available" then
		return "НАГРАДА ГОТОВА: "
			.. best.Name
			.. " — забери бесплатно в коллекции."
	elseif bestState.Kind == "Affordable" then
		return "ДОСТУПЕН СЛЕД: " .. best.Name .. " — примерь в коллекции."
	elseif bestState.Kind == "Unaffordable" then
		return "СЛЕДУЮЩАЯ ЦЕЛЬ: "
			.. best.Name
			.. " — ещё "
			.. bestState.Remaining
			.. " монет."
	end
	for _, milestone in EconomyConfig.MasteryMilestones do
		if milestone.Id == best.UnlockTitle then
			return "БЕСПЛАТНЫЙ СЛЕД: "
				.. best.Name
				.. " — "
				.. milestone.Goal
				.. string.format(
					" (%d/%d).",
					math.min(count(read("Mastery_" .. milestone.Id)), milestone.Target),
					milestone.Target
				)
		end
	end
	return nil
end

return EconomyConfig
