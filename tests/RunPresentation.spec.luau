--!strict
local Presentation = require("../src/shared/RunPresentation")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

expect(Presentation.resultCode(6, true, true) == "Won", "Perfect completed run wins")
expect(Presentation.resultCode(4, true, true) == "Won", "Four is the winning boundary")
expect(
	Presentation.resultCode(3, true, true) == "NotEnoughTrials",
	"A late finalist sees the missing threshold"
)
expect(Presentation.resultCode(5, false, true) == "FinaleMissed", "Team success is not personal success")
expect(
	Presentation.resultCode(4, true, false) == "FinaleFailed",
	"Living through an uncharged finale is not a win"
)
expect(
	Presentation.resultCode(0, false, true) == "NoSurvival",
	"A participant who lost every trial sees no-survival"
)
expect(Presentation.resultCode(6, true, true, true) == "Aborted", "Incomplete or aborted runs never look won")
expect(Presentation.resultCode(0, false, false, true) == "Aborted", "Abort has a distinct recovery message")
expect(Presentation.rewardDelta(40, 52) == 12, "Award deltas count only newly granted currency")
expect(Presentation.rewardDelta(40, 40) == 0, "Rejected or duplicate awards contribute zero")
expect(Presentation.rewardDelta(40, 5) == 0, "Spending cannot become a negative earned reward")
expect(Presentation.rewardDelta(nil, 12) == 0, "Missing profile state cannot invent a reward")
expect(Presentation.rewardDelta(0, nil) == 0, "Missing response cannot invent a reward")
expect(Presentation.rewardDelta(0, math.huge) == 0, "Nonfinite deltas are not presented")
expect(Presentation.rewardDelta(0 / 0, 2) == 0, "NaN is rejected")
print("RunPresentation: " .. checks .. " checks passed")
