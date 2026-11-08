--!strict
local Display = require("../src/shared/RoomDisplay")
local checks = 0
local function expect(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end
local function render(values)
	return Display.snapshot(function(name)
		return values[name]
	end)
end
expect(render({}).Lit == 0, "Missing state is idle")
expect(render({ Phase = "Voting" }).Lit == 0, "Voting does not imply progress")
for index = 1, 6 do
	local view = render({ Phase = "Rule", RuleIndex = index })
	expect(
		view.Lit == index and string.find(view.Heading, tostring(index), 1, true) ~= nil,
		"Stage has text and segments"
	)
end
local charging = render({ Phase = "Rule", RuleId = "ReactorRush", TeamCharge = 2, TeamGoal = 5 })
expect(charging.Lit == 2 and not charging.Charged, "Partial charge")
local charged = render({ Phase = "Rule", RuleId = "ReactorRush", TeamCharge = 5, TeamGoal = 5 })
expect(
	charged.Charged and string.find(charged.Detail, "ДОЖИВИТЕ", 1, true) ~= nil,
	"Full charge is not yet victory"
)
local stabilizing = render({
	Phase = "Rule",
	RuleId = "ReactorRush",
	TeamCharge = 5,
	TeamGoal = 5,
	FinaleStage = "Stabilizing",
})
expect(
	stabilizing.Charged and string.find(stabilizing.Detail, "СТАБИЛИЗАЦИЯ", 1, true) ~= nil,
	"Charged reactor explains the second stage without claiming victory"
)
local dead = render({ Phase = "Results", TeamCharge = 5, TeamGoal = 5, FinaleSuccess = false })
expect(not dead.Charged and dead.Lit == 0, "Charged but uncompleted finale cannot look successful")
expect(string.find(dead.Detail, "НЕ ЗАВЕРШЁН", 1, true) ~= nil, "Failure explanation is explicit")
expect(render({ Phase = "Results", FinaleSuccess = true }).Lit == 6, "Confirmed team success")
expect(render({ RunsPaused = true, Phase = "Rule", RuleIndex = 4 }).Lit == 0, "Operations pause is explicit")
for _, bad in { math.huge, 0 / 0, "5", -1 } do
	expect(render({ Phase = "Rule", RuleIndex = bad }).Lit == 0, "Malformed replicated counters are bounded")
end
print("RoomDisplay: " .. checks .. " checks passed (presentation logic, not rendering)")
