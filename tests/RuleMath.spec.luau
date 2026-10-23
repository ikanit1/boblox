--!strict
-- Run from project root: luau tests/RuleMath.spec.luau
local RuleMath = require("../src/server/RuleMath")

local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

local standing = { x = 0, z = 0, feetY = 1, headY = 5, halfX = 1, halfZ = 0.5 }
local jumping = { x = 0, z = 0, feetY = 3, headY = 7, halfX = 1, halfZ = 0.5 }
local outside = { x = 34, z = 0, feetY = 1, headY = 5, halfX = 1, halfZ = 0.5 }
local behind = { x = 0, z = -10, feetY = 1, headY = 5, halfX = 1, halfZ = 0.5 }
local below = { x = 0, z = 0, feetY = -7, headY = -3, halfX = 1, halfZ = 0.5 }

expect(RuleMath.sweptBeamIntersects(standing, -1, 1, 1.9, 0.5, 0.5, 30), "Standing player must be hit")
expect(not RuleMath.sweptBeamIntersects(jumping, -1, 1, 1.9, 0.5, 0.5, 30), "A clear jump must avoid beam")
expect(not RuleMath.sweptBeamIntersects(outside, -1, 1, 1.9, 0.5, 0.5, 30), "Player outside beam width")
expect(not RuleMath.sweptBeamIntersects(behind, -1, 1, 1.9, 0.5, 0.5, 30), "No hit behind beam path")
expect(not RuleMath.sweptBeamIntersects(below, -1, 1, 1.9, 0.5, 0.5, 30), "No hit below beam")
expect(RuleMath.sweptBeamIntersects(standing, -12, 12, 1.9, 0.5, 0.5, 30), "Fast beam cannot tunnel")
expect(RuleMath.sweptBeamIntersects(standing, 12, -12, 1.9, 0.5, 0.5, 30), "Reverse sweep cannot tunnel")
expect(RuleMath.pingPong(0, 6, 30) == -30, "Sweep starts on near edge")
expect(RuleMath.pingPong(6, 6, 30) == 30, "Sweep reaches far edge")
expect(RuleMath.pingPong(12, 6, 30) == -30, "Sweep reverses without teleporting")
expect(RuleMath.pingPong(3, 6, 30) == 0, "Sweep crosses the center")
expect(RuleMath.isFinite(0) and RuleMath.isFinite(-15), "Normal positions are finite")
expect(not RuleMath.isFinite(math.huge), "Infinite positions are rejected")
expect(not RuleMath.isFinite(0 / 0), "NaN positions are rejected")

expect(RuleMath.insideZone(-10, -10, -15, -15, 9), "Zone supports negative positions")
expect(RuleMath.insideZone(9, 9, 0, 0, 9), "Marked zone boundary is safe")
expect(not RuleMath.insideZone(9.1, 0, 0, 0, 9), "Outside marker receives storm damage")
expect(not RuleMath.insideZone(0 / 0, 0, 0, 0, 9), "NaN cannot satisfy a safe zone")
expect(RuleMath.spinnerIntersects(standing, 0, 28, 0.5), "Spinner hits a grounded body")
expect(not RuleMath.spinnerIntersects(jumping, 0, 28, 0.5), "Jump clears rotating beam")
expect(RuleMath.spinnerIntersects(behind, math.pi / 2, 28, 0.5), "Quarter-turn hits Z axis")
expect(not RuleMath.spinnerIntersects(behind, 0, 28, 0.5), "Quarter-turn and zero angle differ")
expect(not RuleMath.spinnerIntersects(outside, 0, 28, 0.5), "Finite spinner does not hit beyond its endpoint")
local spinnerLength = RuleMath.spinnerHalfLength(30)
for _, x in { -29, 29 } do
	for _, z in { -29, 29 } do
		local corner = { x = x, z = z, feetY = 1, headY = 5, halfX = 1, halfZ = 0.5 }
		local clearCorner = { x = x, z = z, feetY = 3, headY = 7, halfX = 1, halfZ = 0.5 }
		local crossing = math.atan2(-z, x)
		expect(
			RuleMath.spinnerIntersects(corner, crossing, spinnerLength, 0.5),
			"Every playable corner meets the rotating beam"
		)
		expect(
			not RuleMath.spinnerIntersects(clearCorner, crossing, spinnerLength, 0.5),
			"A corner jump still clears the extended beam"
		)
		expect(
			RuleMath.sweptSpinnerIntersects(corner, crossing - 0.15, crossing + 0.15, spinnerLength, 0.5),
			"Forward sweep cannot skip a corner between observations"
		)
		expect(
			RuleMath.sweptSpinnerIntersects(corner, crossing + 0.15, crossing - 0.15, spinnerLength, 0.5),
			"Reverse sweep uses the same corner coverage"
		)
	end
end
expect(not pcall(RuleMath.spinnerHalfLength, math.huge), "An invalid arena cannot create an unbounded beam")
expect(RuleMath.reactorStage(0, 5) == 0, "Empty reactor has no lit stages")
expect(
	RuleMath.reactorStage(1, 5) == 0 and RuleMath.reactorStage(2, 5) == 1,
	"First solo stage lights at the one-third threshold"
)
expect(
	RuleMath.reactorStage(4, 5) == 2 and RuleMath.reactorStage(5, 5) == 3,
	"Second and final solo stages reflect earned charge"
)
expect(
	RuleMath.reactorStage(8, 24) == 1 and RuleMath.reactorStage(16, 24) == 2,
	"Stage thresholds also scale for a full team"
)
expect(
	RuleMath.reactorStage(30, 24) == 3 and RuleMath.reactorStage(-1, 5) == 0,
	"Stage display stays within its three indicators"
)
expect(
	RuleMath.reactorStage(1, 0) == 0 and RuleMath.reactorStage(0 / 0, 5) == 0,
	"Invalid charge data cannot light a stage"
)
expect(not RuleMath.finaleSucceeded(5, 5, false, 1), "Charged reactor is not a win before safe completion")
expect(
	not RuleMath.finaleSucceeded(5, 5, true, 0),
	"A charged reactor with no survivors cannot announce success"
)
expect(not RuleMath.finaleSucceeded(4, 5, true, 2), "Survival without enough energy is not team success")
expect(RuleMath.finaleSucceeded(5, 5, true, 1), "A solo survivor can complete the charged reactor")
expect(RuleMath.finaleSucceeded(6, 5, true, 2), "Simultaneous pickups over the goal preserve team success")
expect(not RuleMath.finaleSucceeded(math.huge, 5, true, 1), "Non-finite energy cannot grant success")
expect(not RuleMath.finaleSucceeded(5, 0, true, 1), "An invalid zero goal cannot grant success")
local beforeRun = RuleMath.joinedTrialResults(0, 6)
local lateJoin = RuleMath.joinedTrialResults(3, 6)
local afterFinale = RuleMath.joinedTrialResults(6, 6)
for index = 1, 6 do
	expect(beforeRun[index] == "Pending", "A new run leaves every trial pending")
	expect(
		lateJoin[index] == (if index <= 3 then "Missed" else "Pending"),
		"Late joining cannot claim the current or earlier hazards"
	)
	expect(
		afterFinale[index] == "Missed",
		"Joining after the final admission cannot claim any completed trial"
	)
end
expect(RuleMath.teamGoal(1) == 5 and RuleMath.teamGoal(12) == 24, "Finale scales from solo to twelve players")
expect(RuleMath.teamGoal(100) == 24, "Finale pickups remain bounded")
local eligible, won = RuleMath.runOutcome(0, false, true)
expect(not eligible and not won, "Lobby and zero-survival players receive no run completion")
eligible, won = RuleMath.runOutcome(1, false, false)
expect(eligible and not won, "One completed trial qualifies for participation only")
eligible, won = RuleMath.runOutcome(3, true, true)
expect(eligible and not won, "Finale alone cannot bypass four-trial threshold")
eligible, won = RuleMath.runOutcome(4, false, true)
expect(eligible and not won, "Dying in the finale cannot count as a win")
eligible, won = RuleMath.runOutcome(4, true, false)
expect(eligible and not won, "A failed team objective cannot award wins")
eligible, won = RuleMath.runOutcome(4, true, true)
expect(eligible and won, "Four trials plus living through charged finale wins")
expect(RuleMath.travelPlausible(16, 1, 16), "Normal movement at full walk speed is allowed")
expect(RuleMath.travelPlausible(24, 0.1, 16), "Delayed replication burst receives a jitter envelope")
expect(RuleMath.travelPlausible(30, 1, 16), "Minor collision and correction displacement is tolerated")
expect(not RuleMath.travelPlausible(50, 0.05, 16), "Teleport across the arena cannot pass before collection")
expect(not RuleMath.travelPlausible(50, 1, 16), "Repeated short teleports accumulate across one second")
expect(RuleMath.travelPlausible(64, 4, 16), "Server stall uses actual elapsed time for travel")
expect(not RuleMath.travelPlausible(1, -1, 16), "Negative observation intervals fail closed")
expect(not RuleMath.travelPlausible(0 / 0, 1, 16), "Non-finite travel fails closed")
expect(not RuleMath.travelPlausible(1, 0 / 0, 16), "Non-finite observation interval fails closed")
expect(not RuleMath.travelPlausible(1, 1, math.huge), "Non-finite speed fails closed")
expect(RuleMath.airbornePlausible(3, 196.2), "Normal jumps have generous airtime allowance")
expect(not RuleMath.airbornePlausible(4.1, 196.2), "Prolonged unsupported hover fails normal gravity")
expect(RuleMath.airbornePlausible(6, 196.2 * 0.28), "Lunar jumps have extended allowance")
expect(not RuleMath.airbornePlausible(7.1, 196.2 * 0.28), "Low gravity does not permit indefinite hover")
expect(not RuleMath.airbornePlausible(math.huge, 196.2), "Invalid airborne duration fails closed")
expect(not RuleMath.airbornePlausible(1, 0 / 0), "Invalid gravity fails closed")
print("RuleMath: " .. checks .. " checks passed")
