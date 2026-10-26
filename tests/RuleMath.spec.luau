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
for _, distance in { 25, 29 } do
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local x, z = distance * xSign, distance * zSign
			local corner = { x = x, z = z, feetY = 1, headY = 5, halfX = 1, halfZ = 0.5 }
			local jumpingCorner = { x = x, z = z, feetY = 3, headY = 7, halfX = 1, halfZ = 0.5 }
			local crossing = math.atan2(-z, x)
			expect(
				RuleMath.spinnerIntersects(corner, crossing, spinnerLength, 0.5),
				"Standing in any arena corner cannot bypass the spinner"
			)
			expect(
				not RuleMath.spinnerIntersects(jumpingCorner, crossing, spinnerLength, 0.5),
				"A clear jump still avoids the spinner in a corner"
			)
		end
	end
end
expect(
	not RuleMath.finaleSucceeded(11, 5, false, 0),
	"Charged then eliminated team cannot announce a successful finale"
)
expect(
	not RuleMath.finaleSucceeded(5, 5, false, 1),
	"Meeting the charge target before completion is not success"
)
expect(not RuleMath.finaleSucceeded(5, 5, true, 0), "Success requires a living participant at completion")
expect(not RuleMath.finaleSucceeded(4, 5, true, 2), "Surviving without enough energy is not success")
expect(RuleMath.finaleSucceeded(5, 5, true, 1), "Completing a charged finale works for a solo survivor")
expect(
	RuleMath.finaleSucceeded(11, 5, true, 2),
	"Excess collected energy preserves a completed team's success"
)
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

-- Ballistic oracle: sample shortly before ground contact, then after the next
-- native jump. Neither sample is within the one-stud ground-ray margin.
for _, gravity in { 196.2, 196.2 * 0.28 } do
	local jumpSpeed, fallVelocity, timeUntilLanding, timeSinceJump = 50, -40, 0.04, 0.12
	local beforeHeight = -fallVelocity * timeUntilLanding + gravity * timeUntilLanding ^ 2 / 2
	local afterHeight = jumpSpeed * timeSinceJump - gravity * timeSinceJump ^ 2 / 2
	local afterVelocity = jumpSpeed - gravity * timeSinceJump
	expect(
		RuleMath.missedLanding(
			beforeHeight,
			afterHeight,
			fallVelocity,
			afterVelocity,
			timeUntilLanding + timeSinceJump,
			gravity,
			jumpSpeed
		),
		"A sampled descent and ascent around a real supporting-floor bounce is consistent"
	)
	expect(
		not RuleMath.missedLanding(
			beforeHeight + 30,
			afterHeight + 30,
			fallVelocity,
			afterVelocity,
			0.16,
			gravity,
			jumpSpeed
		),
		"The same reversal high above the supporting floor is not a landing"
	)
end
expect(
	not RuleMath.missedLanding(3, 3, 0, 0, 0.1, 196.2, 50),
	"Stationary hover never resets airborne evidence"
)
expect(not RuleMath.missedLanding(4, 3, -10, -30, 0.1, 196.2, 50), "Continuing descent is not a bounce")
expect(not RuleMath.missedLanding(3, 4, 30, 10, 0.1, 196.2, 50), "Continuing ascent is not a bounce")
expect(not RuleMath.missedLanding(1.7, 4.6, -40, 90, 0.16, 196.2, 50), "Excessive upward impulse is rejected")
expect(
	not RuleMath.missedLanding(1.7, 4.6, -40, 26, 0.6, 196.2, 50),
	"Unobserved long gaps do not prove a landing"
)
expect(
	not RuleMath.missedLanding(6, 4.6, -2, 26, 0.05, 196.2, 50),
	"There must be enough time to reach the floor"
)
expect(
	not RuleMath.missedLanding(1.7, 7, -40, 49, 0.16, 196.2, 50),
	"Observed rise height must fit the measured velocity"
)
expect(
	not RuleMath.missedLanding(-3, 1, -40, 40, 0.1, 196.2, 50),
	"An underground reversal cannot be a landing"
)
expect(
	not RuleMath.missedLanding(0 / 0, 1, -40, 40, 0.1, 196.2, 50),
	"Nonfinite landing evidence is rejected"
)
print("RuleMath: " .. checks .. " checks passed")
