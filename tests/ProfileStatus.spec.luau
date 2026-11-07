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
print("ProfileStatus: " .. checks .. " checks passed")
