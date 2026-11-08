--!strict
-- Pure production geometry; this does not simulate Humanoid motion or network latency.
local Math = require("../src/server/TraversalMath")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function point(x: number, z: number, y: number?): Math.Point
	return { X = x, Y = y or 4.5, Z = z }
end
local function sheltered(p: Math.Point, plan: Math.Plan): boolean
	return Math.shelterIndex(p, plan, 16, 4, -12, 14, 2) ~= nil
end

for quarter = 0, 3 do
	local first, second = Math.plan(quarter, 1, 42, -21), Math.plan(quarter, 2, 42, -21)
	expect(#first.Covers == 3 and #second.Covers == 2, "The second wave has shifted screens")
	for x = -40, 40, 2 do
		for z = -40, 40, 2 do
			local p = point(x, z)
			local roundTrip = Math.worldPoint(Math.localPoint(p, quarter), quarter)
			expect(roundTrip.X == x and roundTrip.Z == z, "Quarter transforms are exact inverses")
			expect(
				not (sheltered(p, first) and sheltered(p, second)),
				"No stationary pressure shelter survives both directions without damage"
			)
			expect(
				not (Math.inGap(p, first, 9, 2) and Math.inGap(p, second, 9, 2)),
				"Wall openings have no stationary common lane"
			)
			for _, plan in { first, second } do
				local nearest = math.huge
				for _, coverX in plan.Covers do
					local destination = Math.worldPoint(point(coverX, 0), plan.Quarter)
					expect(sheltered(destination, plan), "Every authored cover has a real reachable shelter")
					nearest = math.min(nearest, math.sqrt((destination.X - x) ^ 2 + (destination.Z - z) ^ 2))
				end
				expect(
					nearest < 16 * 5,
					"Every floor sample can reach a shelter during warning at normal speed"
				)
				local localPoint = Math.localPoint(p, plan.Quarter)
				local destination = Math.worldPoint(point(plan.GapX, localPoint.Z), plan.Quarter)
				expect(Math.inGap(destination, plan, 9, 2), "The marked gap is genuinely safe")
				expect(
					math.abs(localPoint.X - plan.GapX) < 16 * 5,
					"Every floor sample can reach the new opening during warning"
				)
			end
		end
	end
	for _, plan in { first, second } do
		local before, after =
			Math.worldPoint(point(0, 0), plan.Quarter), Math.worldPoint(point(0, 0), plan.Quarter)
		local enter, leave = Math.contactInterval(before, after, -45, 45, plan.Quarter, 2)
		expect(
			enter ~= nil and leave ~= nil and enter < leave,
			"A whole-wave frame cannot tunnel past a stationary body"
		)
		local ahead = Math.worldPoint(point(0, 40), plan.Quarter)
		local behind = Math.worldPoint(point(0, -40), plan.Quarter)
		expect(
			Math.contactInterval(ahead, behind, -10, 10, plan.Quarter, 2) ~= nil,
			"An opposing fast crossing hits the swept slab"
		)
		local high = Math.worldPoint(point(plan.Covers[1], 0, 13), plan.Quarter)
		expect(not sheltered(high, plan), "Jumping above a pressure screen is not sheltered")
		local wrongSide = Math.worldPoint(point(plan.Covers[1], -9), plan.Quarter)
		expect(not sheltered(wrongSide, plan), "Standing inside or in front of a screen is not sheltered")
		local boundary = Math.worldPoint(point(plan.GapX + 7, 0), plan.Quarter)
		expect(Math.inGap(boundary, plan, 9, 2), "Opening includes the marked body-safe boundary")
		local outside = Math.worldPoint(point(plan.GapX + 7.01, 0), plan.Quarter)
		expect(not Math.inGap(outside, plan, 9, 2), "A body overlapping the panel receives a hit")
	end
end

local clipped = Math.clip(point(0, 0), point(30, 0), 6, 9, 7)
expect(clipped ~= nil and clipped.X == 10, "Late position is interpolated to the actual deadline")
expect(Math.clip(point(0, 0), point(30, 0), 6, 5, 7) == nil, "Backwards time is invalid")
expect(Math.clip(point(0, 0), point(0 / 0, 0), 6, 9, 7) == nil, "Nonfinite positions never fabricate shelter")
expect(Math.clip(point(0, 0), point(3, 0), 6, 7, 7).X == 3, "Exact-deadline position is retained")
local enter, leave = Math.contactInterval(point(-21, 0), point(0, 0), 0, 0, 0, 2)
expect(enter == 0 and leave == 1, "Moving sideways while overlapping a wall checks the entire interval")
expect(
	Math.contactInterval(point(0, 10), point(0, 20), -20, -10, 0, 2) == nil,
	"No contact is invented behind an unrelated plane"
)
expect(
	Math.front(-1, 42, 2) == -45 and Math.front(2, 42, 2) == 45,
	"Wave range safely encloses the entire floor"
)
expect(
	not Math.valid(point(math.huge, 0)) and not Math.valid(point(0, 0, 0 / 0)),
	"All nonfinite components are rejected"
)
local function body(z: number, feet: number): Math.Body
	return { x = 0, z = z, feetY = feet, headY = feet + 4, halfX = 1, halfZ = 0.5 }
end
expect(
	Math.beamContact(body(0, 1), body(0, 1), -23, 14, 42),
	"A beam crossing between samples hits a stationary standing body"
)
expect(
	not Math.beamContact(body(0, 5), body(0, 5), -23, 14, 42),
	"A body above the entire path remains clear"
)
expect(
	Math.beamContact(body(40, 1), body(40, 1), 32, 41.5, 42),
	"The outward turnaround leg reaches the edge body"
)
expect(
	not Math.beamContact(body(40, 1), body(40, 1), 32, 14, 42),
	"Endpoint shortcut demonstrates why a turnaround must be split"
)
expect(
	Math.beamContact(body(12, 1), body(-12, 1), -12, 12, 42),
	"Opposing body and beam paths intersect at the same instant"
)
expect(
	not Math.beamContact(body(12, 1), body(36, 1), -12, 12, 42),
	"Moving ahead of a beam does not cause an endpoint-only false hit"
)
expect(
	not Math.beamContact(body(0, 1), body(0, 6), -23, 14, 42),
	"A completed ascent before contact clears the moving beam"
)
expect(
	Math.beamContact(body(0, 1), body(0, 3), -23, 14, 42),
	"Elevation reached too late cannot erase earlier contact"
)
local delayed = Math.lerpBody(body(30, 1), body(0, 1), 0.5)
expect(
	not Math.beamContact(body(30, 1), delayed, -23.055555, 13.833333, 42),
	"Entering the swept region after the deadline does not retroactively cause damage"
)
expect(
	not Math.beamContact(body(0 / 0, 1), body(0, 1), -20, 20, 42),
	"Invalid geometry cannot produce a fabricated contact"
)
print(`TraversalMath: {checks} checks passed; geometry only, no native physics acceptance.`)
