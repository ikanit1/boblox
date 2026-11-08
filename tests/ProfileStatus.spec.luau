--!strict
local Status = require("../src/shared/ProfileStatus")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

for _, status in { "Loading", "Unknown", "Saved" } do
	expect(
		not Status.canJoin(status, false, true, true),
		"Consent cannot bypass loading/inconsistent persistence"
	)
end
expect(not Status.canJoin(nil, nil, true, true), "Missing initial state fails closed")
expect(Status.canJoin("Saved", true, false, false), "Loaded cloud profile needs no temporary consent")
local pending = Status.describe("Unavailable", true)
expect(pending.Warning and not pending.Temporary, "Live-lease retry is not permanent fallback")
expect(Status.canJoin("Unavailable", true, false, false), "Automatic retry can continue the game")
expect(
	string.find(pending.Compact, "повторяем", 1, true) ~= nil,
	"Retry display identifies automatic recovery"
)

for _, status in { "Session", "Busy", "Unavailable" } do
	local view = Status.describe(status, false)
	expect(
		view.Warning and view.Temporary and not view.Loading,
		"Fallback is playable but explicitly temporary"
	)
	expect(
		view.PlayText == "ИГРАТЬ ВРЕМЕННО",
		"Entry action explains its persistence consequence"
	)
	expect(not Status.canJoin(status, false, nil, nil), "Direct Join/proximity cannot imply consent")
	expect(not Status.canJoin(status, false, false, "true"), "String cannot spoof boolean consent")
	expect(not Status.canJoin(status, false, false, 1), "Number cannot spoof boolean consent")
	expect(Status.canJoin(status, false, false, true), "Explicit temporary choice is admitted")
	expect(Status.canJoin(status, false, true, nil), "Accepted session can rejoin without repeated prompts")
end
expect(Status.describe("Saved", true).Warning == false, "Recovered save clears warning")
local retry = Status.retry(true, 105, 3, 100)
expect(
	retry.Visible and not retry.Enabled and retry.Text == "ПОВТОР ЧЕРЕЗ 5 С",
	"Retry cooldown uses the shared server clock"
)
retry = Status.retry(true, 105, 2, 105)
expect(
	retry.Visible and retry.Enabled and retry.Text == "ПОВТОРИТЬ ЗАГРУЗКУ",
	"Retry becomes usable exactly at the deadline"
)
expect(
	string.find(retry.Hint, "до временной игры", 1, true) ~= nil,
	"Retry wording explains its admission boundary"
)
for _, args in
	{
		{ false, 0, 3, 100 },
		{ "true", 0, 3, 100 },
		{ true, 0, 0, 100 },
		{ true, 0, 4, 100 },
		{ true, 0, 1.5, 100 },
		{ true, 0 / 0, 3, 100 },
		{ true, math.huge, 3, 100 },
		{ true, 0, 3, math.huge },
	}
do
	local view = Status.retry(table.unpack(args))
	expect(not view.Visible and not view.Enabled, "Missing, exhausted or malformed retry state fails closed")
end
print("ProfileStatus: " .. checks .. " checks passed")
