--!strict
local Hints = require("../src/shared/PlayerHints")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

for _, reason in
	{
		"SafeColor",
		"LaserSweep",
		"LowGravity",
		"RedLight",
		"LavaRise",
		"MeteorRain",
		"DisappearingTiles",
		"SafeZone",
		"Spinner",
		"ReactorRush",
		"Fall",
		"Boundary",
		"Movement",
		"Reset",
	}
do
	local text = Hints.compactDefeat(reason)
	local lines = string.split(text, "\n")
	expect(#lines == 2, "Compact defeat has a reason and a separate corrective action: " .. reason)
	expect(#lines[1] > 0 and #lines[2] > 0, "Neither coaching line is empty: " .. reason)
	expect((utf8.len(lines[1]) or 99) <= 33, "Reason remains concise for a phone: " .. reason)
	expect((utf8.len(lines[2]) or 99) <= 38, "Corrective action remains concise for a phone: " .. reason)
end
expect(
	Hints.compactDefeat("UnexpectedServerReason") ~= Hints.compactDefeat("LaserSweep"),
	"Unknown defeat must not accuse a particular hazard"
)
expect(
	string.find(Hints.resultsHeading("FinaleFailed", 4, 6), "4 / 6", 1, true) ~= nil,
	"Team failure keeps the player's four successes in the headline"
)
expect(
	string.find(Hints.resultsHeading("NoSurvival", 0, 6), "0 / 6", 1, true) ~= nil,
	"Zero success is presented as a real result"
)
expect(
	string.find(Hints.resultsHeading("Won", 6, 6), "ПОБЕДА", 1, true) ~= nil,
	"Only confirmed personal victory uses victory wording"
)
expect(
	string.find(Hints.resultsHeading("FinaleMissed", 5, 6), "ПОБЕДА", 1, true) == nil,
	"A team victory cannot invent a personal win"
)
expect(
	string.find(Hints.teamResult("FinaleFailed", false, 3, 5), "3 / 5", 1, true) ~= nil,
	"Failed charge retains its exact progress"
)
expect(
	string.find(Hints.teamResult("FinaleFailed", false, 5, 5), "никто не выжил", 1, true) ~= nil,
	"Charged but dead team is distinct from missing charge"
)
expect(
	string.find(Hints.teamResult("FinaleMissed", true, 5, 5), "команда справилась", 1, true)
		~= nil,
	"Team success stays visible even when the local player lost"
)
expect(
	string.find(Hints.resultDetail("NotEnoughTrials", true), "Поздний вход", 1, true) ~= nil,
	"Impossible late-entry win is explained without blaming the player"
)
expect(
	string.find(Hints.resultDetail("FinaleFailed", true), "Поздний вход", 1, true) ~= nil,
	"Late entry is also explained when the shared finale fails"
)
expect(
	string.find(Hints.resultDetail("Aborted", true), "Поздний вход", 1, true) == nil,
	"Abort is not misrepresented as a late-entry loss"
)
expect(
	string.find(Hints.resultDetail("Won", true), "Поздний вход", 1, true) == nil,
	"An authoritative win is never contradicted by inferred participation"
)
for _, phase in { "Waiting", "Voting", "Results", "", nil } do
	expect(Hints.lateEntryNotice(phase, 3, 6) == nil, "No late-entry notice outside an active run")
end
expect(Hints.lateEntryNotice("Rule", 0, 6) == nil, "No notice before the first trial index is published")
expect(Hints.lateEntryNotice("Rule", "2", 6) == nil, "Malformed trial index is ignored")
for ruleIndex = 1, 6 do
	for _, phase in { "Rule", "Break" } do
		local notice = Hints.lateEntryNotice(phase, ruleIndex, 6)
		expect(notice ~= nil and #notice > 0, "Every in-progress trial explains late entry")
		local remaining = 6 - ruleIndex
		local promisesWin = string.find(
			notice :: string,
			"победа — со следующего",
			1,
			true
		) == nil and remaining > 0
		-- A win needs WinTrials successes among the trials still ahead of the newcomer.
		expect(
			promisesWin == (remaining >= Hints.WinTrials),
			"Late-entry notice matches whether a personal win is still reachable at trial " .. ruleIndex
		)
	end
end
expect(
	string.find(Hints.lateEntryNotice("Rule", 2, 6) :: string, "(3/6)", 1, true) ~= nil,
	"Early late entry names the next admitted trial"
)
expect(
	string.find(Hints.lateEntryNotice("Rule", 6, 6) :: string, "следующего забега", 1, true)
		~= nil,
	"Joining during the finale waits for the next run"
)
expect(
	Hints.teamResultWithContribution("FinaleFailed", false, 8, 10, 3)
		== Hints.teamResult("FinaleFailed", false, 8, 10) .. " · твой вклад ⚡3",
	"Personal finale contribution is appended to the shared reactor line"
)
expect(
	Hints.teamResultWithContribution("Won", true, 10, 10, 0) == Hints.teamResult("Won", true, 10, 10),
	"No contribution text when the player collected nothing"
)
expect(
	Hints.teamResultWithContribution("Aborted", false, 4, 10, 2) == Hints.teamResult("Aborted", false, 4, 10),
	"Aborted runs do not show a contribution"
)
expect(
	Hints.teamResultWithContribution("FinaleFailed", false, 0, 0, 2)
		== Hints.teamResult("FinaleFailed", false, 0, 0),
	"No contribution without a finale goal"
)
expect(
	Hints.teamResultWithContribution("Won", true, 10, 10, nil) == Hints.teamResult("Won", true, 10, 10),
	"A missing RunEnergy attribute is tolerated"
)
-- Movement warning: one concise line that fits the compact phone panel.
expect((utf8.len(Hints.MovementWarning) or 99) <= 52, "Movement warning fits a single compact panel line")
expect(
	string.find(Hints.MovementWarning, "награда", 1, true) ~= nil,
	"Movement warning names the lost reward"
)

expect(
	string.find(Hints.MovementWarning, "снята", 1, true) ~= nil,
	"Movement warning says the reward is withdrawn"
)

-- Forfeited outcome: its own symbol and text, distinct from the other outcomes.
expect(
	Hints.Forfeited.Symbol ~= "✓"
		and Hints.Forfeited.Symbol ~= "×"
		and Hints.Forfeited.Symbol ~= "·"
		and Hints.Forfeited.Symbol ~= "—"
		and Hints.Forfeited.Symbol ~= "▶",
	"Forfeited symbol differs from every other outcome symbol"
)
expect(
	Hints.Forfeited.Label == "жив, награда снята",
	"Forfeited wording names survival and the withdrawn reward"
)
expect((utf8.len(Hints.Forfeited.CompactToast) or 99) <= 24, "Compact forfeited toast fits a phone")
expect(Hints.forfeitedLine({ "Survived", "Eliminated", "Pending" }) == nil, "No forfeited trials, no line")
expect(Hints.forfeitedLine({}) == nil, "Missing outcomes, no line")
expect(
	Hints.forfeitedLine({ "Survived", "Forfeited", "Survived" })
		== "! Этап 2: жив, награда снята",
	"Single forfeited trial is named"
)
expect(
	Hints.forfeitedLine({ "Forfeited", "Survived", "Survived", "Forfeited" })
		== "! Этапы 1, 4: жив, награда снята",
	"Several forfeited trials are listed in order"
)

-- NewRecord contract: "" | "Score" | "Survived" | "Score,Survived"; absent means no data.
expect(Hints.newRecordLine(nil, 340, 5, 6) == nil, "Absent NewRecord shows nothing")
expect(Hints.newRecordLine("", 340, 5, 6) == nil, "Empty NewRecord shows nothing")
expect(Hints.newRecordLine("Unknown", 340, 5, 6) == nil, "Unknown NewRecord value is ignored")
expect(Hints.newRecordLine(true, 340, 5, 6) == nil, "Non-string NewRecord is ignored")
expect(
	Hints.newRecordLine("Score", 340, 5, 6) == "НОВЫЙ РЕКОРД: 340 очков",
	"Score-only record"
)
expect(
	Hints.newRecordLine("Survived", 340, 5, 6) == "НОВЫЙ РЕКОРД: 5 / 6 этапов",
	"Survived-only record"
)
expect(
	Hints.newRecordLine("Score,Survived", 340, 5, 6)
		== "НОВЫЙ РЕКОРД: 340 очков · 5 / 6 этапов",
	"Both records are combined in contract order"
)
expect(Hints.newRecordLine("Score", nil, 5, 6) == nil, "A record without its value is not claimed")

-- Mastery: only finite integer clear counters are part of the v2 server contract.
local flawless: { [string]: unknown } =
	{ Flawless_SafeColor = true, Flawless_LaserSweep = 3, Flawless_RedLight = 0, Flawless_Spinner = "x" }
local function read(name: string): unknown
	return flawless[name]
end
local ruleIds = { "SafeColor", "LaserSweep", "RedLight", "Spinner", "LavaRise" }
local rules, clears = Hints.flawlessCount(read, ruleIds)
expect(rules == 1 and clears == 3, "Flawless counts only valid integers and ignores booleans and junk")
local none, noneClears = Hints.flawlessCount(function()
	return nil
end, ruleIds)
expect(none == 0 and noneClears == 0, "No Flawless attributes means zero mastery")

local empty = Hints.masterySummary(nil, nil, nil, 0, 0, 10, 6)
expect(#string.split(empty, "\n") == 2, "Mastery summary is two lines")
expect(string.find(empty, "Счёт —", 1, true) ~= nil, "Missing best score is shown as a dash")
expect(string.find(empty, "Паркур —", 1, true) ~= nil, "Missing practice record is shown as a dash")
expect(string.find(empty, "0 / 10 правил", 1, true) ~= nil, "Mastery starts at zero of ten rules")
local full = Hints.masterySummary(340, 5, 42.126, 2, 4, 10, 6)
expect(string.find(full, "Счёт 340", 1, true) ~= nil, "Best score is shown")
expect(string.find(full, "Этапы 5 / 6", 1, true) ~= nil, "Best survived is shown as N / 6")
expect(string.find(full, "Паркур 42.13 с", 1, true) ~= nil, "Best practice is rounded to hundredths")
expect(
	string.find(full, "2 / 10 правил (4 раз)", 1, true) ~= nil,
	"Repeated flawless clears are counted"
)
for _, line in string.split(full, "\n") do
	expect((utf8.len(line) or 99) <= 48, "Mastery lines stay readable on a phone row")
end
expect(
	not string.find(Hints.masterySummary(340, 5, nil, 1, 1, 10, 6), "(1 раз)", 1, true),
	"A single clear per rule is not repeated in parentheses"
)

-- Malformed attributes must not manufacture records, mastery or invalid UI numbers.
for _, value in { true, false, "3", -1, 0, 0.5, 1.5, math.huge, -math.huge, 0 / 0, 1e100 } do
	local invalidRules, invalidClears = Hints.flawlessCount(function()
		return value
	end, { "SafeColor" })
	expect(invalidRules == 0 and invalidClears == 0, "Malformed mastery counter is ignored")
end
local maximumRules, maximumClears = Hints.flawlessCount(function()
	return 1_000_000_000
end, { "SafeColor" })
expect(maximumRules == 1 and maximumClears == 1_000_000_000, "Maximum stored mastery counter is readable")
for _, code in { "Score,Score", "Survived,Score", "Score,Unknown", "Score,", ",Survived" } do
	expect(Hints.newRecordLine(code, 340, 5, 6) == nil, "Only exact NewRecord contract values are accepted")
end
for _, value in { true, "5", -1, 0, 0.5, math.huge, -math.huge, 0 / 0 } do
	expect(Hints.newRecordLine("Score", value, 5, 6) == nil, "Malformed score cannot claim a record")
	expect(Hints.newRecordLine("Survived", 340, value, 6) == nil, "Malformed survival cannot claim a record")
	local summary = Hints.masterySummary(value, value, value, 0, 0, 10, 6)
	expect(string.find(summary, "Счёт —", 1, true) ~= nil, "Malformed score remains a dash")
	expect(string.find(summary, "Этапы —", 1, true) ~= nil, "Malformed survival remains a dash")
	if value ~= 0.5 then
		expect(string.find(summary, "Паркур —", 1, true) ~= nil, "Malformed practice remains a dash")
	end
end
expect(Hints.newRecordLine("Survived", 340, 7, 6) == nil, "Survival record cannot exceed run length")
for _, value in { math.huge, -math.huge, 0 / 0, 1.5 } do
	expect(Hints.lateEntryNotice("Rule", value, 6) == nil, "Invalid admission index is ignored")
	expect(
		Hints.teamResultWithContribution("Won", true, 10, 10, value) == Hints.teamResult("Won", true, 10, 10),
		"Invalid contribution is not shown"
	)
end
for _, code in { "FinaleMissed", "NoSurvival", "NotEnoughTrials" } do
	local detail = Hints.resultDetail(code, false, "Forfeited")
	expect(
		string.find(detail, "Ты выжил в финале", 1, true) ~= nil,
		"Forfeited finale never implies death"
	)
	expect(
		string.find(detail, "награда снята", 1, true) ~= nil,
		"Forfeited finale explains no personal win"
	)
end
expect(
	Hints.resultDetail("Aborted", false, "Forfeited") == Hints.resultDetail("Aborted", false),
	"Aborted result keeps priority over a final outcome"
)
expect(
	Hints.resultDetail("Won", false, "Forfeited") == Hints.resultDetail("Won", false),
	"Presentation does not override authoritative win using inconsistent attributes"
)

-- Next goals use persistent records after the catalog is complete, never leaderstats Best.
local goalEconomy = {
	Quests = {
		survive = { Target = 8, Reward = 50 },
		stars = { Target = 10, Reward = 50 },
		runs = { Target = 2, Reward = 60 },
	},
	Trails = {
		{ Id = "None", Name = "Без следа", Price = 0 },
		{ Id = "Cyan", Name = "Ионный след", Price = 60 },
	},
}
local goalAttributes: { [string]: any } = { Coins = 20, DataStatus = "Saved", DataPersistent = true }
local function nextGoal(): string
	return Hints.nextGoal(function(name)
		return goalAttributes[name]
	end, goalEconomy, 6)
end
expect(
	string.find(nextGoal(), "ещё 40 монет", 1, true) ~= nil,
	"Unaffordable item shows the exact remaining coins"
)
goalAttributes.Quest_survive = 8
expect(
	string.find(nextGoal(), "ГОТОВА НАГРАДА", 1, true) ~= nil,
	"Claimable quest has priority over catalog"
)
goalAttributes.Claimed_survive = true
goalAttributes.Coins = 60
expect(
	string.find(nextGoal(), "примерь в коллекции", 1, true) ~= nil,
	"Affordable item suggests the reversible preview"
)
goalAttributes.Owned_Cyan = true
goalAttributes.BestRunSurvived = 5
expect(
	string.find(nextGoal(), "пройди 6 / 6", 1, true) ~= nil,
	"Full catalog points to one additional successful trial"
)
expect(
	string.find(nextGoal(), "Твой рекорд: 5 / 6", 1, true) ~= nil,
	"Goal states the existing record without claiming the target"
)
goalAttributes.BestRunSurvived = 6
expect(
	string.find(nextGoal(), "первый рекорд", 1, true) ~= nil,
	"Six of six leads to a first practice finish when absent"
)
goalAttributes.BestPracticeSeconds = 12.345
goalAttributes.BestRunScore = 340
goalAttributes.Best = 99999
expect(string.find(nextGoal(), "340 очков", 1, true) ~= nil, "Score goal uses profile BestRunScore")
expect(string.find(nextGoal(), "12.35 с", 1, true) ~= nil, "Practice goal preserves fractional saved time")
expect(string.find(nextGoal(), "99999", 1, true) == nil, "Session scoreboard does not replace profile record")
goalAttributes.DataStatus = "Session"
goalAttributes.DataPersistent = false
expect(
	string.find(nextGoal(), "ЦЕЛЬ ЭТОЙ СЕССИИ", 1, true) ~= nil,
	"Temporary profile has no implied cross-session progress"
)
expect(string.find(nextGoal(), "сохран", 1, true) == nil, "Temporary goal never promises a save")
goalAttributes.DataStatus = "Loading"
expect(
	string.find(nextGoal(), "дождись загрузки", 1, true) ~= nil,
	"Loading suppresses record and purchase suggestions"
)
goalAttributes.DataStatus = "Saved"
goalAttributes.DataPersistent = true
for _, value in { true, "12", 0, -1, math.huge, 0 / 0, 1e100 } do
	goalAttributes.BestPracticeSeconds = value
	expect(
		string.find(nextGoal(), "первый рекорд", 1, true) ~= nil,
		"Malformed practice data cannot become a claimed record"
	)
end
for _, value in { true, "6", 7, -1, 0.5, math.huge, 0 / 0, 1e100 } do
	goalAttributes.BestRunSurvived = value
	expect(
		string.find(nextGoal(), "пройди 1 / 6", 1, true) ~= nil,
		"Malformed survival record does not manufacture six of six"
	)
end
goalAttributes.BestRunSurvived = 6
goalAttributes.BestPracticeSeconds = 10
goalAttributes.BestRunScore = math.huge
expect(
	string.find(nextGoal(), "10.00 с", 1, true) ~= nil,
	"Valid practice still provides a goal without a valid score"
)
expect(string.find(nextGoal(), "очков", 1, true) == nil, "Malformed score is omitted from goal")

for count = 0, 3 do
	expect(Hints.lunarProgress(count, 3) == string.format("★ %d/3", count), "Personal lunar progress")
	local text = Hints.lunarCommand("Active", 2, count, 3)
	expect((utf8.len(text) or 99) <= 34, "Lunar command fits a compact phone instruction")
	expect(string.find(text, "★ " .. count .. "/3", 1, true) ~= nil, "Active command shows own quota")
	expect(
		Hints.lunarCommand("Warning", 2, count, 3) == "⚠ Уйди с плиток «ПРОВАЛ»",
		"Floor danger overrides pickup progress, even after quota"
	)
end
for _, count in { -1, 4, 0.5, math.huge, 0 / 0, "3", true } do
	expect(Hints.lunarProgress(count, 3) == "", "Malformed lunar progress is omitted")
end
expect(Hints.lunarProgress(3, 0) == "", "Cleaned-up lunar goal is hidden")
expect(Hints.lunarProgress(nil, 3) == "", "Partial replication does not invent progress")
expect(
	string.find(Hints.lunarCommand("Warning", 1, 0, 3), "ПРОВАЛ", 1, true) == nil,
	"Opening lunar warning does not invent a disappearing-floor deadline"
)
expect(
	string.find(Hints.lunarCommand("Active", 3, 3, 3), "держись", 1, true) ~= nil,
	"Quota completion keeps the survival objective visible"
)
goalEconomy.MasteryMilestones = {
	{ Id = "FirstRun", Title = "Первый шаг", Goal = "Забег со звездой", Target = 1 },
	{
		Id = "PerfectRun",
		Title = "Покоритель комнаты",
		Goal = "Победа 6/6 с вкладом",
		Target = 1,
	},
	{
		Id = "Collector",
		Title = "Точный собиратель",
		Goal = "Три чистых сбора",
		Target = 3,
	},
	{ Id = "Practice", Title = "Паркурист", Goal = "Пройди паркур", Target = 1 },
	{
		Id = "TeamVeteran",
		Title = "Опора команды",
		Goal = "Пять побед с вкладом",
		Target = 5,
	},
}
expect(
	string.find(nextGoal(), "Первый шаг", 1, true) ~= nil,
	"First meaningful finish is the initial permanent goal"
)
goalAttributes.Mastery_FirstRun = 1
expect(
	string.find(nextGoal(), "Первый шаг", 1, true) ~= nil,
	"Goal remains until authoritative unlock arrives"
)
goalAttributes.UnlockedTitle_FirstRun = true
expect(
	string.find(nextGoal(), "Паркурист", 1, true) ~= nil,
	"Accessible parkour comes before demanding a perfect run"
)
goalAttributes.UnlockedTitle_Practice = true
goalAttributes.Mastery_Collector = 2
expect(
	string.find(nextGoal(), "Точный собиратель", 1, true) ~= nil,
	"Different clean collector rules become the next objective"
)
expect(string.find(nextGoal(), "2/3", 1, true) ~= nil, "Permanent goal uses server mastery progress")
goalAttributes.DataStatus = "Session"
goalAttributes.DataPersistent = false
expect(
	string.find(nextGoal(), "ЦЕЛЬ ЭТОЙ СЕССИИ", 1, true) ~= nil,
	"Temporary milestone does not promise permanence"
)
goalAttributes.UnlockedTitle_Collector = true
expect(
	string.find(nextGoal(), "Покоритель комнаты", 1, true) ~= nil,
	"Perfect run follows accessible mastery objectives"
)
goalAttributes.UnlockedTitle_PerfectRun = true
expect(
	string.find(nextGoal(), "Опора команды", 1, true) ~= nil,
	"Team contribution remains a long-term objective"
)
goalAttributes.UnlockedTitle_TeamVeteran = true
expect(
	string.find(nextGoal(), "10.00 с", 1, true) ~= nil,
	"All milestones completed returns to persistent personal records"
)
for _, value in { -1, 1.5, 6, math.huge, -math.huge, 0 / 0, "3", true } do
	expect(
		Hints.masteryProgress(value, 5) == 0,
		"Malformed milestone progress cannot manufacture earned completion"
	)
end
expect(Hints.masteryProgress(nil, 5) == 0, "Missing replicated progress starts unknown at zero")
expect(Hints.masteryProgress(3, 5) == 3, "Valid progress remains exact")

print("PlayerHints: " .. checks .. " checks passed")
