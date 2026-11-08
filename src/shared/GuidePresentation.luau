--!strict
-- Illustrative diagrams only: never used for hitboxes, timers, admission or rewards.
local GuidePresentation = { Duration = 10, MaxShapes = 24 }
GuidePresentation.RuleIds = {
	"SafeColor",
	"LaserSweep",
	"LowGravity",
	"RedLight",
	"LavaRise",
	"MeteorRain",
	"DisappearingTiles",
	"SafeZone",
	"Spinner",
	"PressureWave",
	"ChangingWalls",
	"ReactorRush",
}

local lessons = {
	SafeColor = {
		{
			"Найди СИНИЙ ●",
			"Перейди на СИНИЙ ●",
			"Останься: другой пол исчез",
		},
		"Смотри на слово и символ, а не только на цвет.",
	},
	LaserSweep = {
		{
			"Жёлтый луч: приготовься",
			"Прыгни над красным лучом",
			"Приземлись за лучом",
		},
		"Прыгай перед встречей с лучом, не после касания.",
	},
	LowGravity = {
		{
			"Найди свою звезду ★",
			"Прыгай выше и собери ★",
			"Уйди с метки ПРОВАЛ",
		},
		"Звёзды личные; опасный пол исчезает и на Луне.",
	},
	RedLight = {
		{
			"Зелёный: двигайся",
			"Жёлтый: остановись",
			"Красный: замри",
		},
		"На зелёный уходи со своей помеченной плитки.",
	},
	LavaRise = {
		{
			"Найди голубую платформу",
			"Запрыгни до подъёма лавы",
			"Останься на платформе",
		},
		"Платформами можно делиться; пол внизу опасен.",
	},
	MeteorRain = {
		{
			"Квадрат предупреждает об ударе",
			"Выйди из квадрата",
			"Проверь следующую метку",
		},
		"Не беги из одной метки в другую.",
	},
	DisappearingTiles = {
		{
			"ПРОВАЛ: пол скоро исчезнет",
			"Перейди на обычную плитку",
			"Дождись восстановления",
		},
		"Следующая волна может выбрать другие плитки.",
	},
	SafeZone = {
		{
			"Найди квадрат УБЕЖИЩЕ",
			"Добеги внутрь до шторма",
			"Останься внутри границы",
		},
		"После волны ищи новое убежище.",
	},
	Spinner = {
		{
			"Найди вращающийся луч",
			"Перепрыгни подходящий луч",
			"Следи за следующим оборотом",
		},
		"Углы не спасают; подальше от центра проще выбрать момент.",
	},
	PressureWave = {
		{
			"Найди щит и сторону волны",
			"Встань за щитом от волны",
			"Следующая волна с другой стороны",
		},
		"Щит пропускает тебя: защищает область за ним, не перед ним.",
	},
	ChangingWalls = {
		{
			"Найди проём в стене",
			"Совместись с движущимся проёмом",
			"Следующий проход с другой стороны",
		},
		"Иди через широкий проём, а не сквозь панель.",
	},
	ReactorRush = {
		{
			"Соберите общий заряд: до 24 с",
			"Полный заряд: выживи ещё 4 с",
			"Реактор запущен, если кто-то выжил",
		},
		"Для личной победы: 4 этапа и выживание в успешном финале.",
	},
}

local function finite(value: any, fallback: number): number
	return if typeof(value) == "number"
			and value == value
			and math.abs(value) < math.huge
		then value
		else fallback
end

function GuidePresentation.bounds(width: number, height: number, touch: boolean): (number, number)
	local w = math.min(600, math.max(120, width - 24))
	local h = math.min(320, math.max(120, height - 24))
	if touch then
		if width > height then
			w = math.min(w, math.max(120, width - 336))
		else
			h = math.min(h, math.max(120, height - 176))
		end
	end
	return w, h
end

function GuidePresentation.snapshot(
	ruleId: string,
	seconds: number,
	reduced: boolean,
	manualStep: number?
): any?
	local lesson = lessons[ruleId]
	if not lesson then
		return nil
	end
	local elapsed = math.clamp(finite(seconds, 0), 0, GuidePresentation.Duration)
	local stage = if reduced
		then math.clamp(math.floor(finite(manualStep, 1)), 1, 3)
		elseif ruleId == "ReactorRush" then (if elapsed < 6 then 1 elseif elapsed < 10 then 2 else 3)
		else (if elapsed < 2 then 1 elseif elapsed < 7 then 2 else 3)
	local t = if reduced then 1 else math.clamp((elapsed - 2) / 5, 0, 1)
	local shapes = {}
	local function shape(
		x: number,
		y: number,
		w: number,
		h: number,
		tone: string,
		text: string?,
		angle: number?
	)
		table.insert(
			shapes,
			{ X = x, Y = y, Width = w, Height = h, Tone = tone, Text = text or "", Angle = angle or 0 }
		)
	end
	local function player(x: number, y: number)
		shape(x, y, 0.12, 0.22, "Player", "●")
	end
	local function floor()
		shape(0.02, 0.76, 0.96, 0.18, "Floor")
	end
	local function grid()
		for row = 0, 2 do
			for column = 0, 2 do
				shape(0.04 + column * 0.31, 0.04 + row * 0.30, 0.28, 0.27, "Floor")
			end
		end
	end
	if ruleId == "SafeColor" then
		for index, tone in { "Blue", "Pink", "Yellow", "Green" } do
			shape(
				0.03 + (index - 1) * 0.245,
				0.18,
				0.22,
				0.64,
				if stage == 3 and index ~= 1 then "Void" else tone,
				({ "●", "◆", "▲", "■" })[index]
			)
		end
		player(if stage == 1 then 0.67 else 0.08 + (1 - t) * 0.59, 0.40)
	elseif ruleId == "LaserSweep" or ruleId == "Spinner" then
		floor()
		shape(
			if ruleId == "Spinner" then 0.47 else 0.58 - t * 0.25,
			0.59,
			0.035,
			0.17,
			if stage == 1 then "Warn" else "Danger",
			"",
			if ruleId == "Spinner" then 20 - 40 * t else 0
		)
		shape(
			0.06,
			0.05,
			0.88,
			0.22,
			"Void",
			if ruleId == "Spinner" then "↻   ПРЫЖОК ↑" else "ЛУЧ ←   ПРЫЖОК ↑"
		)
		player(0.36 + t * 0.18, if stage == 2 then 0.26 else 0.53)
	elseif ruleId == "LowGravity" then
		floor()
		shape(0.57, 0.12, 0.18, 0.26, "Gold", if stage < 3 then "★" else "✓")
		shape(
			0.12,
			0.76,
			0.22,
			0.18,
			if stage == 3 then "Danger" else "Floor",
			if stage == 3 then "!" else ""
		)
		player(
			if stage == 1 then 0.17 elseif stage == 2 then 0.57 else 0.78,
			if stage == 2 then 0.22 else 0.53
		)
	elseif ruleId == "RedLight" then
		floor()
		shape(
			0.42,
			0.08,
			0.18,
			0.26,
			({ "Safe", "Warn", "Danger" })[stage],
			({ "→", "Ⅱ", "СТОП" })[stage]
		)
		shape(0.1, 0.76, 0.2, 0.18, "Danger", "!")
		player(if stage == 1 then 0.2 else 0.68, 0.53)
	elseif ruleId == "LavaRise" then
		floor()
		shape(0.02, 0.68, 0.96, 0.26, if stage == 1 then "Warn" else "Danger", "ЛАВА")
		shape(0.57, 0.45, 0.32, 0.2, "Blue", "ПЛАТФОРМА")
		player(if stage == 1 then 0.2 else 0.66, if stage == 1 then 0.45 else 0.21)
	elseif ruleId == "MeteorRain" then
		grid()
		shape(0.35, 0.34, 0.28, 0.27, if stage == 2 then "Danger" else "Warn", "×")
		player(if stage == 1 then 0.43 else 0.09, if stage == 1 then 0.37 else 0.08)
		if stage == 3 then
			shape(0.66, 0.64, 0.28, 0.27, "Warn", "×")
		end
	elseif ruleId == "DisappearingTiles" then
		grid()
		shape(
			0.35,
			0.34,
			0.28,
			0.27,
			if stage == 2 then "Void" else "Warn",
			if stage == 2 then "↓" else "!"
		)
		player(if stage == 1 then 0.43 else 0.09, 0.37)
	elseif ruleId == "SafeZone" then
		grid()
		shape(0.66, 0.04, 0.28, 0.27, "Safe", "■")
		player(if stage == 1 then 0.12 else 0.73, if stage == 1 then 0.65 else 0.07)
	elseif ruleId == "PressureWave" then
		grid()
		local reverse = stage == 3
		shape(
			if reverse then 0.76 else 0.07 + t * 0.12,
			0.04,
			0.04,
			0.88,
			if stage == 1 then "Warn" else "Danger"
		)
		shape(if reverse then 0.12 else 0.57, 0.20, 0.25, 0.57, "Safe", "ЗА")
		shape(if reverse then 0.39 else 0.52, 0.16, 0.04, 0.65, "Blue")
		shape(0.03, 0.01, 0.92, 0.20, "Void", if reverse then "ВОЛНА ←" else "ВОЛНА →")
		player(if reverse then 0.19 else 0.63, 0.38)
	elseif ruleId == "ChangingWalls" then
		grid()
		local gap = if stage == 3 then 0.65 else 0.2
		local y = if stage == 1 then 0.16 else 0.16 + t * 0.45
		shape(0.03, y, gap - 0.03, 0.14, "Danger")
		shape(gap + 0.25, y, 0.97 - gap - 0.25, 0.14, "Danger")
		shape(gap, y, 0.25, 0.14, "Safe", if stage == 3 then "↑" else "↓")
		player(gap + 0.065, if stage == 1 then 0.66 else 0.3)
	elseif ruleId == "ReactorRush" then
		floor()
		shape(
			0.58,
			0.16,
			0.33,
			0.48,
			if stage == 1 then "Blue" else "Gold",
			if stage == 1 then "⚡" elseif stage == 2 then "4 С" else "✓"
		)
		shape(0.2, 0.16, 0.18, 0.22, "Gold", if stage == 1 then "⚡ →" else "ПРЫГАЙ")
		shape(0.36, 0.60, 0.04, 0.16, "Danger")
		player(0.25, if stage == 2 then 0.35 else 0.53)
	end
	return {
		Stage = stage,
		Command = lesson[1][stage],
		Tip = lesson[2],
		Shapes = shapes,
		Done = elapsed >= GuidePresentation.Duration,
	}
end

return GuidePresentation
