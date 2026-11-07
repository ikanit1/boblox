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

expect(not Presentation.isLateEntry(1, 6), "A full attempt can qualify for a win")
expect(not Presentation.isLateEntry(3, 6), "Joining trial three still allows four successes")
expect(Presentation.isLateEntry(4, 6), "Joining trial four cannot earn the normal four-success win")
expect(Presentation.isLateEntry(6, 6), "A finalist joining alone gets a partial-attempt notice")
expect(not Presentation.isLateEntry(0, 6), "A non-participant is not falsely labelled late")
expect(not Presentation.isLateEntry(7, 6), "The next run is not a late entry into the old one")
expect(
	Presentation.firstEnteredTrial({ "Skipped", "Skipped", "Playing", "Pending", "Pending", "Pending" }) == 3,
	"The first admission is found while playing"
)
expect(
	Presentation.firstEnteredTrial({ "Skipped", "Skipped", "Skipped", "Eliminated", "Survived", "Survived" })
		== 4,
	"An early death still counts as participation when explaining late entry"
)
expect(Presentation.firstEnteredTrial({ "Skipped", "Pending", "Pending" }) == 0, "No invented participation")
expect(Presentation.firstEnteredTrial({
	"Survived",
	"Survived",
	"Eliminated",
	"Survived",
	"Survived",
	"Survived",
}) == 1, "An ordinary survivor break must not become a late-entry attempt")

for _, available in { 90, 150, 176, 190, 210, 239, 240, 270, 700 } do
	local layout = Presentation.resultsLayout(available)
	expect(
		layout.ViewportHeight <= available,
		"Results never overlap lower controls by forcing a taller viewport"
	)
	expect(layout.ContentHeight >= layout.ViewportHeight, "Scrollable content covers the viewport")
	local bottom = 0
	for _, name in { "Heading", "Summary", "Personal", "Rewards", "Trials", "Goal", "Next" } do
		local row = layout.Rows[name]
		if name ~= "Trials" then
			expect(row.Visible, "Essential information cannot disappear: " .. name)
		end
		if row.Visible then
			expect(row.Y >= bottom, "Visible result rows must not overlap: " .. name)
			expect(
				row.Y + row.Height <= layout.ContentHeight,
				"Result row remains reachable in canvas: " .. name
			)
			bottom = row.Y + row.Height
		end
	end
	if available >= 176 then
		local goal = layout.Rows.Goal
		expect(
			goal.Y + goal.Height <= layout.ViewportHeight,
			"Next goal is visible without scrolling on supported short layouts"
		)
	end
end
print("RunPresentation: " .. checks .. " checks passed")
