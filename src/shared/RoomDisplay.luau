--!strict
-- Decorative station status derives from server state; it never decides a result.
local RoomDisplay = {}
local function count(value: any, maximum: number): number
	return if type(value) == "number"
			and value == value
			and value < math.huge
		then math.floor(math.clamp(value, 0, maximum))
		else 0
end
function RoomDisplay.snapshot(read: (string) -> any): { [string]: any }
	local phase = read("Phase")
	local index = count(read("RuleIndex"), 6)
	local charge = count(read("TeamCharge"), 1000)
	local goal = count(read("TeamGoal"), 1000)
	local result = {
		Heading = "РЕАКТОР ОЖИДАЕТ",
		Detail = "6 ЭТАПОВ · ОБЩИЙ ФИНАЛ",
		Lit = 0,
		Charged = false,
	}
	if read("RunsPaused") == true then
		result.Heading = "Ⅱ ИСПЫТАНИЯ НА ПАУЗЕ"
		result.Detail = "ЛАБОРАТОРИЯ И ПАРКУР ДОСТУПНЫ"
	elseif phase == "Voting" then
		result.Heading = "ВЫБЕРИ РИТМ ЗАБЕГА"
		result.Detail = "МИКС · РЕАКЦИЯ · КОСМОС"
	elseif phase == "Rule" or phase == "Break" then
		if read("RuleId") == "ReactorRush" and goal > 0 then
			result.Heading = string.format("⚡ РЕАКТОР %d / %d", charge, goal)
			result.Detail = if read("FinaleStage") == "Stabilizing"
				then "СТАБИЛИЗАЦИЯ · ПЕРЕПРЫГИВАЙТЕ ЛУЧ"
				elseif charge >= goal then "ЗАРЯЖЕН · ДОЖИВИТЕ ДО КОНЦА"
				else "СОБИРАЙТЕ ЗАРЯДЫ ВМЕСТЕ"
			result.Lit = math.clamp(math.floor(charge / goal * 6), 0, 6)
			-- Charged is visual energy, never a substitute for FinaleSuccess.
			result.Charged = charge >= goal
		else
			result.Heading = string.format("ЭТАП %d / 6", index)
			result.Detail = if phase == "Break"
				then "ПЕРЕДЫШКА · СЛЕДУЮЩЕЕ ПРАВИЛО СКОРО"
				else "КОМНАТА ПРОВЕРЯЕТ КОМАНДУ"
			result.Lit = index
		end
	elseif phase == "Results" then
		if read("FinaleSuccess") == true then
			result.Heading = "✓ РЕАКТОР ЗАПУЩЕН"
			result.Detail = "СПАСИБО ЗА КОМАНДНУЮ РАБОТУ"
			result.Lit, result.Charged = 6, true
		else
			result.Heading = "↻ НОВАЯ ПОПЫТКА"
			result.Detail = if goal > 0 and charge >= goal
				then "ЗАРЯД БЫЛ ПОЛНЫМ · ФИНАЛ НЕ ЗАВЕРШЁН"
				else "КАЖДЫЙ ЭТАП — ШАНС СТАТЬ ЛУЧШЕ"
		end
	end
	return result
end
return RoomDisplay
