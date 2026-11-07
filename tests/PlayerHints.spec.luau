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
print("PlayerHints: " .. checks .. " checks passed")
