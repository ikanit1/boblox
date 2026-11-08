--!strict
-- Validate a replicated social snapshot without granting rewards or inferring personal wins.
local ContributionView = {}
local outcomes = {
	Won = "ПОБЕДА",
	FinaleFailed = "РЕАКТОР НЕ ЗАПУЩЕН",
	FinaleMissed = "ФИНАЛ НЕ ПРОЙДЕН",
	NotEnoughTrials = "НЕ ХВАТИЛО ЭТАПОВ",
	NoSurvival = "НОВАЯ ПОПЫТКА",
	Aborted = "ЗАБЕГ ПРЕРВАН",
	Left = "ВЫШЕЛ ИЗ ИГРЫ",
}
local function integer(value: any, minimum: number, maximum: number): boolean
	return type(value) == "number"
		and value == value
		and value % 1 == 0
		and value >= minimum
		and value <= maximum
end
local function name(value: any): string?
	if type(value) ~= "string" or #value == 0 or #value > 200 or not utf8.len(value) then
		return nil
	end
	return string.gsub(value, "[%c]", " ")
end
function ContributionView.read(payload: any, round: any, barrier: any): { any }?
	if
		not integer(round, 1, 1e9)
		or barrier ~= round
		or type(payload) ~= "table"
		or payload.Version ~= 1
		or payload.Round ~= round
		or type(payload.Players) ~= "table"
		or #payload.Players > 72
	then
		return nil
	end
	local result, seen = {}, {}
	for index, entry in payload.Players do
		if
			not integer(index, 1, #payload.Players)
			or type(entry) ~= "table"
			or not integer(entry.UserId, -1e12, 1e12)
			or seen[entry.UserId]
			or not integer(entry.Score, 0, 1e9)
			or not integer(entry.Survived, 0, 6)
			or not integer(entry.Energy, 0, 1e9)
			or type(entry.Left) ~= "boolean"
			or type(entry.Outcome) ~= "string"
			or not outcomes[entry.Outcome]
		then
			return nil
		end
		local displayName = name(entry.Name)
		if not displayName then
			return nil
		end
		seen[entry.UserId] = true
		table.insert(result, {
			UserId = entry.UserId,
			Name = displayName,
			Detail = string.format(
				"%d/6 этапов · %d очков · ⚡ %d",
				entry.Survived,
				entry.Score,
				entry.Energy
			),
			Outcome = if entry.Left then outcomes.Left else outcomes[entry.Outcome],
		})
	end
	return result
end
return ContributionView
