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

function PlayerHints.resultDetail(code: string, lateEntry: boolean): string
	if lateEntry and code ~= "Won" and code ~= "Aborted" then
		return "Поздний вход: полная попытка победить — в следующем забеге."
	end
	return (PlayerHints.Results[code] or PlayerHints.Results.None).Detail
end

return PlayerHints
