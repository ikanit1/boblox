--!strict
-- Prototype geometry budgets, not native avatar/physics acceptance or released rules.
local Math = require("../prototypes/shared/ExperimentMath")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function distance(a, b): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end
for seed = 0, 35 do
	for beat = 1, 2 do
		local pressure = Math.plan("PressureWave", seed, beat)
		for _, x in { -40, 40 } do
			for _, z in { -40, 40 } do
				local route = Math.shelterRoute(Math.point(x, 5, z), pressure)
				local length = 0
				for index, p in route do
					expect(Math.inside(p), "Cover route stays on the grid")
					if index > 1 then
						length += distance(route[index - 1], p)
					end
				end
				expect(
					length / 16 + 0.75 <= Math.WarningSeconds,
					"Corner route includes reaction budget before a wave"
				)
				expect(Math.sheltered(route[#route], pressure), "Route ends behind the shield, not on top")
			end
		end
		local walls = Math.plan("ChangingWalls", seed, beat)
		local route, length, gates = Math.route(walls), 0, 0
		for index, p in route do
			expect(Math.inside(p), "Door route fits inside the grid")
			if index > 1 then
				length += distance(route[index - 1], p)
				if gates < 2 then
					local crossed, valid = Math.crossGate(route[index - 1], p, walls, gates + 1)
					if crossed then
						expect(valid, "Route crosses an opening with body clearance")
						gates += 1
					end
				end
			end
		end
		expect(
			gates == 2 and length / 16 + 2 <= Math.RouteSeconds,
			"Two-door route has at least two seconds of spare movement budget"
		)
	end
end
for seed = 0, 3 do
	local first = Math.plan("PressureWave", seed, 1)
	local second = Math.plan("PressureWave", seed, 2)
	for x = -40, 40 do
		for z = -40, 40 do
			local point = Math.point(x, 5, z)
			expect(
				not (Math.sheltered(point, first) and Math.sheltered(point, second)),
				"No stationary ground position shelters both waves in any direction"
			)
			if Math.sheltered(point, first) then
				local route = Math.shelterRoute(point, second)
				local length = 0
				for index, waypoint in route do
					expect(Math.inside(waypoint), "The second shelter route stays within the arena")
					if index > 1 then
						length += distance(route[index - 1], waypoint)
					end
				end
				expect(Math.sheltered(route[#route], second), "The second route reaches a new shelter lane")
				expect(
					length / 16 + 0.75 <= Math.WarningSeconds,
					"Every first-wave shelter has time to reach the next with reaction allowance"
				)
			end
		end
	end
end
local p = Math.plan("PressureWave", 0, 1)
expect(Math.sheltered(Math.point(28, 5, 30), p), "Behind cover is safe")
expect(not Math.sheltered(Math.point(28, 5, -20), p), "Front of cover does not protect")
expect(not Math.sheltered(Math.point(28, 17, 30), p), "Standing on a shield is not safe")
expect(not Math.sheltered(Math.point(18, 5, 30), p), "Outside the projected width does not protect")
local hit = Math.waveContact(Math.point(0, 5, 0), Math.point(0, 5, 2), -10, 10, p)
expect(hit ~= nil, "Swept crossing catches a wave between endpoint samples")
expect(
	Math.waveContact(Math.point(0, 5, -20), Math.point(0, 5, -22), -10, 10, p) == nil,
	"Already behind the wave is not hit again"
)
local walls = Math.plan("ChangingWalls", 0, 1)
local crossed, valid = Math.crossGate(Math.point(28, 5, -20), Math.point(28, 5, -8), walls, 1)
expect(crossed and not valid, "Crossing a solid wall is not a valid checkpoint")
expect(
	not Math.inside(Math.point(0, 0, 0)) and not Math.inside(Math.point(100, 5, 0)),
	"Falling/outside samples are rejected"
)
print(string.format("ExperimentMath: %d checks passed (isolated prototypes only)", checks))
