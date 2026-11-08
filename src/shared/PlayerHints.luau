--!strict
-- Short coaching text; it never decides rewards or the outcome of an attempt.
local PlayerHints = {
	CompactDefeat = {
		SafeColor = { Cause = "ПОЛ ИСЧЕЗ", Action = "Ищи нужный знак заранее" },
		LaserSweep = {
			Cause = "ЗАДЕЛ ЛУЧ",
			Action = "Прыгай перед встречей с лучом",
		},
		LowGravity = {
			Cause = "ПАДЕНИЕ",
			Action = "Приземляйся внутри комнаты",
		},
		RedLight = {
			Cause = "ДВИЖЕНИЕ НА КРАСНЫЙ",
			Action = "Остановись ещё на жёлтый",
		},
		LavaRise = {
			Cause = "ПОПАЛ В ЛАВУ",
			Action = "Запрыгни на голубую платформу",
		},
		MeteorRain = {
			Cause = "УДАР МЕТЕОРА",
			Action = "Сразу уходи с красной метки",
		},
		DisappearingTiles = {
			Cause = "ПРОВАЛ ПОД НОГАМИ",
			Action = "Уйди с отмеченной плитки",
		},
		SafeZone = {
			Cause = "ВНЕ УБЕЖИЩА",
			Action = "Беги внутрь зелёного квадрата",
		},
		Spinner = {
			Cause = "ЗАДЕЛ ВРАЩАЮЩИЙСЯ ЛУЧ",
			Action = "Отойди от центра и прыгай",
		},
		PressureWave = {
			Cause = "НАКРЫЛА ВОЛНА",
			Action = "Встань на зелёную полосу за экраном",
		},
		ChangingWalls = {
			Cause = "ЗАДЕЛ СТЕНУ",
			Action = "Проходи через большой зелёный проём",
		},
		ReactorRush = {
			Cause = "ЗАДЕЛ ЛУЧ В ФИНАЛЕ",
			Action = "Прыгай и после зарядки",
		},
		Fall = { Cause = "ПАДЕНИЕ", Action = "Следи за местом приземления" },
		Boundary = {
			Cause = "ЗА ГРАНИЦЕЙ КОМНАТЫ",
			Action = "Оставайся на поле испытания",
		},
		Movement = {
			Cause = "ДВИЖЕНИЕ НЕ ПОДТВЕРЖДЕНО",
			Action = "Следующая попытка скоро",
		},
		Reset = {
			Cause = "ПОПЫТКА ПРЕРВАНА",
			Action = "Вернёшься с полным здоровьем",
		},
	},
	Defeat = {
		SafeColor = "Ищи нужный символ заранее; стой на нём до возврата пола.",
		LaserSweep = "Смотри на приближающийся луч и прыгай чуть раньше.",
		LowGravity = "После высокого прыжка приземляйся внутри комнаты.",
		RedLight = "Останавливайся на жёлтый сигнал, до появления красного.",
		LavaRise = "Поднимись на голубую платформу до подъёма лавы.",
		MeteorRain = "Уходи с красной метки сразу и проверь соседнюю плитку.",
		DisappearingTiles = "Надпись «ПРОВАЛ» — сигнал перейти на обычную плитку.",
		SafeZone = "Беги к зелёному убежищу, как только оно появится.",
		Spinner = "Держись дальше от центра и прыгай перед встречей с лучом.",
		PressureWave = "Ищи зелёную полосу за экраном: перед встречной волной укрытие меняется.",
		ChangingWalls = "Встань напротив зелёного проёма заранее; высокий щит нельзя перепрыгнуть.",
		ReactorRush = "Перепрыгивай луч даже после полной зарядки реактора.",
		Fall = "Удерживайся на безопасном полу и смотри, куда приземляешься.",
		Boundary = "Оставайся внутри испытательной комнаты.",
		Movement = "Персонаж оказался вне допустимой зоны движения.",
		Reset = "Попытка прервана. В следующем испытании начнёшь с полным здоровьем.",
	},
	Results = {
		Won = {
			Title = "ТВОЯ ПОБЕДА!",
			Detail = "Минимум 4 успеха, финал пережит, реактор заряжен.",
		},
		FinaleFailed = {
			Title = "ТВОЙ РЕЗУЛЬТАТ",
			Detail = "Твои успехи засчитаны. В финале нужны заряд и выживание.",
		},
		FinaleMissed = {
			Title = "ПОЧТИ ПОЛУЧИЛОСЬ",
			Detail = "Для победы переживи финал. Зарядка не отключает луч.",
		},
		NotEnoughTrials = {
			Title = "ХОРОШЕЕ НАЧАЛО",
			Detail = "Для победы нужны 4 успеха и выживание в успешном финале.",
		},
		NoSurvival = {
			Title = "ПОПРОБУЕМ ЕЩЁ",
			Detail = "Начни с одного успеха. После ошибки вернёшься на следующий этап.",
		},
		Aborted = {
			Title = "КОМНАТА ПЕРЕЗАПУСКАЕТСЯ",
			Detail = "Забег прерван. Уже заработанные награды остаются у тебя.",
		},
		None = {
			Title = "ЗАБЕГ ЗАВЕРШЁН",
			Detail = "В следующем забеге можно пройти все шесть испытаний.",
		},
	},
}

function PlayerHints.compactDefeat(reason: string): string
	local hint = PlayerHints.CompactDefeat[reason]
	if not hint then
		return "ПОПЫТКА ЗАВЕРШЕНА\nСледи за предупреждением комнаты"
	end
	return hint.Cause .. "\n" .. hint.Action
end

function PlayerHints.resultsHeading(code: string, survived: number, trialCount: number): string
	if code == "Aborted" then
		return "ЗАБЕГ ПРЕРВАН · " .. survived .. " / " .. trialCount
	end
	return (if code == "Won" then "ПОБЕДА · " else "ТВОЙ РЕЗУЛЬТАТ: ")
		.. survived
		.. " / "
		.. trialCount
end

function PlayerHints.teamResult(code: string, success: boolean, charge: number, goal: number): string
	if code == "Aborted" then
		return "Комната готовит новый забег"
	elseif success then
		return "РЕАКТОР: ЗАРЯЖЕН · команда справилась"
	elseif goal > 0 and charge >= goal then
		return "РЕАКТОР: ЗАРЯЖЕН · никто не выжил"
	elseif goal > 0 then
		return string.format("РЕАКТОР: %d / %d · не заряжен", charge, goal)
	end
	return "РЕАКТОР: финал не завершён"
end

-- Minimum successful trials for a personal win; mirrors RuleMath.runOutcome on the server.
PlayerHints.WinTrials = 4

-- Explains, before admission, what joining a run that is already in progress means.
-- Returns nil when no run is in progress (voting, waiting, results).
local function finiteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function positiveInteger(value: unknown): boolean
	return finiteNumber(value) and (value :: number) >= 1 and value == math.floor(value :: number)
end

function PlayerHints.lateEntryNotice(phase: unknown, ruleIndex: unknown, ruleCount: number): string?
	if (phase ~= "Rule" and phase ~= "Break") or not positiveInteger(ruleIndex) then
		return nil
	end
	local index = ruleIndex :: number
	local remaining = ruleCount - index
	if remaining <= 0 then
		return "Идёт финал. Вступишь в начале следующего забега."
	elseif remaining < PlayerHints.WinTrials then
		return "Забег уже идёт: награды за этапы сохранятся, победа — со следующего забега."
	end
	return string.format(
		"Забег уже идёт: вступишь со следующего этапа (%d/%d).",
		index + 1,
		ruleCount
	)
end

-- Appends the player's own finale contribution (RunEnergy) to the shared reactor line.
-- Nothing is added for aborted runs, runs without a finale goal, or players who skipped it.
function PlayerHints.teamResultWithContribution(
	code: string,
	success: boolean,
	charge: number,
	goal: number,
	energy: unknown
): string
	local line = PlayerHints.teamResult(code, success, charge, goal)
	if code == "Aborted" or goal <= 0 or not positiveInteger(energy) then
		return line
	end
	return line .. " · твой вклад ⚡" .. (energy :: number)
end

PlayerHints.MasteryTitle = "РЕКОРДЫ И МАСТЕРСТВО"
PlayerHints.InviteLabel = "ПОЗВАТЬ ДРУЗЕЙ"

-- Shown in the compact rule panel while the server reports MovementWarning = true.
-- The attempt continues, but this trial no longer pays its stage reward.
PlayerHints.MovementWarning =
	"Движение не подтверждено — награда этапа снята"

-- Trial outcome "Forfeited": the player survived, but the server withdrew the stage reward
-- (unconfirmed movement). Symbol + text + colour; never colour alone.
PlayerHints.Forfeited = {
	Symbol = "!",
	Label = "жив, награда снята",
	Toast = "! ЖИВ · НАГРАДА ЭТАПА СНЯТА",
	CompactToast = "! Жив · награда снята",
}

-- Lists forfeited trials for the results panel, e.g. "! Этапы 2, 4: жив, награда снята".
-- Returns nil when no outcome is "Forfeited" (or the attribute is absent).
function PlayerHints.forfeitedLine(outcomes: { unknown }): string?
	local indices = {}
	for index, outcome in outcomes do
		if outcome == "Forfeited" then
			table.insert(indices, tostring(index))
		end
	end
	if #indices == 0 then
		return nil
	end
	return PlayerHints.Forfeited.Symbol
		.. (if #indices == 1 then " Этап " else " Этапы ")
		.. table.concat(indices, ", ")
		.. ": "
		.. PlayerHints.Forfeited.Label
end

-- Server contract: NewRecord is "" | "Score" | "Survived" | "Score,Survived".
-- Returns nil for an absent, empty or unknown value so nothing is shown before the server sets it.
function PlayerHints.newRecordLine(
	code: unknown,
	score: unknown,
	survived: unknown,
	trialCount: number
): string?
	if code ~= "Score" and code ~= "Survived" and code ~= "Score,Survived" then
		return nil
	end
	local parts = {}
	if (code == "Score" or code == "Score,Survived") and positiveInteger(score) then
		table.insert(parts, (score :: number) .. " очков")
	end
	if
		(code == "Survived" or code == "Score,Survived")
		and positiveInteger(survived)
		and (survived :: number) <= trialCount
	then
		table.insert(parts, (survived :: number) .. " / " .. trialCount .. " этапов")
	end
	if #parts == 0 then
		return nil
	end
	return "НОВЫЙ РЕКОРД: " .. table.concat(parts, " · ")
end

-- Only finite positive integer counters match the server contract. Missing or malformed
-- attributes never manufacture mastery (including booleans and fractional counts).
function PlayerHints.flawlessCount(read: (string) -> unknown, ruleIds: { string }): (number, number)
	local rules, clears = 0, 0
	for _, id in ruleIds do
		local value = read("Flawless_" .. id)
		if positiveInteger(value) and (value :: number) <= 1_000_000_000 then
			rules += 1
			clears += value :: number
		end
	end
	return rules, clears
end

-- Two short lines for the «Рекорды и мастерство» block. Every argument may be nil (no data yet).
function PlayerHints.masterySummary(
	bestScore: unknown,
	bestSurvived: unknown,
	bestPracticeSeconds: unknown,
	flawlessRules: number,
	flawlessClears: number,
	ruleCount: number,
	trialCount: number
): string
	local scoreText = if positiveInteger(bestScore) then tostring(bestScore) else "—"
	local survivedText = if positiveInteger(bestSurvived) and (bestSurvived :: number) <= trialCount
		then (bestSurvived :: number) .. " / " .. trialCount
		else "—"
	local practiceText = if finiteNumber(bestPracticeSeconds) and (bestPracticeSeconds :: number) > 0
		then string.format("%.2f с", bestPracticeSeconds :: number)
		else "—"
	local flawlessText = if flawlessClears > flawlessRules
		then string.format("%d / %d правил (%d раз)", flawlessRules, ruleCount, flawlessClears)
		else string.format("%d / %d правил", flawlessRules, ruleCount)
	return "Счёт "
		.. scoreText
		.. " · Этапы "
		.. survivedText
		.. " · Паркур "
		.. practiceText
		.. "\nБезупречно: "
		.. flawlessText
end

-- Offers a reachable goal without confusing the session scoreboard with saved profile records.
-- This function only describes server-published values; it cannot grant a reward or claim.
function PlayerHints.masteryProgress(value: unknown, target: number): number
	return if positiveInteger(value) and (value :: number) <= target then value :: number else 0
end

function PlayerHints.nextGoal(read: (string) -> unknown, economy: any, ruleCount: number): string
	if read("DataStatus") == "Loading" then
		return "ЦЕЛЬ: дождись загрузки профиля или осмотри лабораторию."
	end
	local function count(name: string): number
		local value = read(name)
		return if positiveInteger(value) and (value :: number) <= 1_000_000_000 then value :: number else 0
	end
	for _, id in { "survive", "stars", "runs" } do
		local quest = economy.Quests[id]
		if count("Quest_" .. id) >= quest.Target and read("Claimed_" .. id) ~= true then
			return "ГОТОВА НАГРАДА: +"
				.. quest.Reward
				.. " монет — открой «Цели»."
		end
	end
	local status = read("DataStatus")
	local temporary = read("DataPersistent") == false or status == "Session" or status == "Busy"
	local prefix = if temporary then "ЦЕЛЬ ЭТОЙ СЕССИИ: " else "ЛИЧНАЯ ЦЕЛЬ: "
	-- Ready mastery cosmetics are actionable now, unlike a distant coin or title target.
	if type(economy.trailState) == "function" and type(economy.nextTrailGoal) == "function" then
		for _, trail in economy.Trails do
			if economy.trailState(trail, read).Kind == "Available" then
				return prefix .. (economy.nextTrailGoal(read) or "Открой коллекцию.")
			end
		end
	end
	-- Offer the first finish and the station challenge before demanding a perfect run.
	-- Unlock flags are authoritative; progress reaching a target does not award a title locally.
	for _, id in { "FirstRun", "Practice", "Collector", "PerfectRun", "TeamVeteran" } do
		for _, milestone in economy.MasteryMilestones or {} do
			if milestone.Id == id and read("UnlockedTitle_" .. id) ~= true then
				return prefix
					.. "«"
					.. milestone.Title
					.. "» — "
					.. milestone.Goal
					.. string.format(
						" (%d/%d).",
						PlayerHints.masteryProgress(read("Mastery_" .. id), milestone.Target),
						milestone.Target
					)
			end
		end
	end
	if type(economy.nextTrailGoal) == "function" then
		local goal = economy.nextTrailGoal(read)
		if goal then
			return prefix .. goal
		end
	end
	for _, trail in economy.Trails do
		if trail.Price > 0 and read("Owned_" .. trail.Id) ~= true then
			local remaining = math.max(0, trail.Price - count("Coins"))
			return if remaining == 0
				then "ДОСТУПЕН СЛЕД: " .. trail.Name .. " — примерь в коллекции."
				else "СЛЕДУЮЩАЯ ЦЕЛЬ: "
					.. trail.Name
					.. " — ещё "
					.. remaining
					.. " монет."
		end
	end
	local trials = if positiveInteger(ruleCount) and ruleCount <= 100 then ruleCount else 6
	local survived = count("BestRunSurvived")
	local bestSurvived = if survived <= trials then survived else 0
	if bestSurvived < trials then
		return prefix
			.. string.format(
				"пройди %d / %d этапов. Твой рекорд: %d / %d.",
				bestSurvived + 1,
				trials,
				bestSurvived,
				trials
			)
	end
	local practice = read("BestPracticeSeconds")
	if not finiteNumber(practice) or (practice :: number) <= 0 or (practice :: number) > 1_000_000_000 then
		return prefix
			.. "пройди паркур в лаборатории — установи первый рекорд."
	end
	local score = count("BestRunScore")
	return prefix
		.. if score > 0
			then string.format(
				"улучши рекорд %d очков или паркур %.2f с.",
				score,
				practice :: number
			)
			else string.format("улучши рекорд паркура %.2f с.", practice :: number)
end

function PlayerHints.resultDetail(code: string, lateEntry: boolean, finaleOutcome: unknown?): string
	if code ~= "Won" and code ~= "Aborted" and finaleOutcome == "Forfeited" then
		return "Ты выжил в финале, но награда снята. Для победы пройди его без предупреждений."
	end
	if lateEntry and code ~= "Won" and code ~= "Aborted" then
		return "Поздний вход: полная попытка победить — в следующем забеге."
	end
	return (PlayerHints.Results[code] or PlayerHints.Results.None).Detail
end

function PlayerHints.lunarProgress(count: unknown, goal: unknown): string
	if goal ~= 3 or typeof(count) ~= "number" or count < 0 or count > 3 or count % 1 ~= 0 then
		return ""
	end
	return string.format("★ %d/3", count)
end

function PlayerHints.lunarCommand(stage: string, cycle: number, count: unknown, goal: unknown): string
	-- A floor deadline always takes precedence over optional pickup progress.
	if stage == "Warning" and cycle >= 2 then
		return "⚠ Уйди с плиток «ПРОВАЛ»"
	end
	local progress = PlayerHints.lunarProgress(count, goal)
	if progress == "" then
		return "Прыгай к своим звёздам ★"
	end
	return progress
		.. if count == 3 then " · держись на полу" else " · прыгай за звёздами"
end

return PlayerHints
