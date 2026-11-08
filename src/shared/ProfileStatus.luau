--!strict
-- Shared wording and admission policy. Only the server publishes persistence/consent.
local ProfileStatus = {}

export type View = {
	Loading: boolean,
	Temporary: boolean,
	Warning: boolean,
	Title: string,
	Body: string,
	Hint: string,
	Compact: string,
	PlayText: string,
}

function ProfileStatus.describe(status: any, persistent: any): View
	if status == "Saved" and persistent == true then
		return {
			Loading = false,
			Temporary = false,
			Warning = false,
			Title = "КОМНАТА МЕНЯЕТ ПРАВИЛА",
			Body = "",
			Hint = "Можно играть одному или вместе с друзьями.",
			Compact = "Сохранение включено",
			PlayText = "ИГРАТЬ",
		}
	end
	if status == "Unavailable" and persistent == true then
		return {
			Loading = false,
			Temporary = false,
			Warning = true,
			Title = "СОХРАНЕНИЕ ЗАДЕРЖИВАЕТСЯ",
			Body = "Последние изменения пока не сохранены. Повторяем автоматически. Можно продолжить играть.",
			Hint = "До подтверждения сохранения последние награды могут потеряться при выходе.",
			Compact = "Сохранение задерживается · повторяем",
			PlayText = "ПРОДОЛЖИТЬ",
		}
	end
	if status == "Session" or status == "Busy" or status == "Unavailable" then
		return {
			Loading = false,
			Temporary = true,
			Warning = true,
			Title = "ПРОГРЕСС ТОЛЬКО ДО ВЫХОДА",
			Body = if status == "Session"
				then "Это локальная проверка игры. Монеты, опыт и покупки этой сессии не сохранятся после выхода."
				elseif
					status == "Busy"
				then "Профиль занят другой сессией. Здесь можно играть временно: новые награды и покупки не сохранятся."
				else "Сохранение недоступно. Новые награды и покупки этой сессии не сохранятся после выхода.",
			Hint = if status == "Session"
				then "Играть временно или просто осмотреться — решаешь ты."
				else "Для новой попытки загрузки выйди и зайди позже. Временный прогресс не переносится.",
			Compact = "БЕЗ СОХРАНЕНИЯ · прогресс до выхода",
			PlayText = "ИГРАТЬ ВРЕМЕННО",
		}
	end
	-- Missing or inconsistent attributes cannot silently opt a newcomer into fallback play.
	return {
		Loading = true,
		Temporary = false,
		Warning = false,
		Title = "КОМНАТА МЕНЯЕТ ПРАВИЛА",
		Body = "",
		Hint = "Загружаем прогресс…",
		Compact = "Загружаем прогресс…",
		PlayText = "ЗАГРУЗКА",
	}
end

function ProfileStatus.canJoin(status: any, persistent: any, accepted: any, requestAcceptance: any): boolean
	local view = ProfileStatus.describe(status, persistent)
	return not view.Loading and (not view.Temporary or accepted == true or requestAcceptance == true)
end

function ProfileStatus.retry(canRetry: any, retryAt: any, remaining: any, now: any): any
	local valid = canRetry == true
		and type(retryAt) == "number"
		and retryAt == retryAt
		and math.abs(retryAt) < math.huge
		and retryAt >= 0
		and type(remaining) == "number"
		and remaining >= 1
		and remaining <= 3
		and remaining % 1 == 0
		and type(now) == "number"
		and now == now
		and math.abs(now) < math.huge
	if not valid then
		return { Visible = false, Enabled = false, Text = "ПОВТОРИТЬ ЗАГРУЗКУ", Hint = "" }
	end
	local seconds = math.max(0, math.ceil(retryAt - now))
	return {
		Visible = true,
		Enabled = seconds == 0,
		Text = if seconds > 0
			then string.format("ПОВТОР ЧЕРЕЗ %d С", math.min(seconds, 999))
			else "ПОВТОРИТЬ ЗАГРУЗКУ",
		Hint = string.format(
			"Ещё попыток: %d. Повтор доступен до временной игры.",
			remaining
		),
	}
end

return ProfileStatus
