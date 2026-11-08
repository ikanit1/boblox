--!strict
-- Actual isolated state machine with deterministic positions; no physics/network claim.
local Math = require("../prototypes/shared/ExperimentMath")
local Session = require("../prototypes/server/ExperimentSession")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function samples(ids, point)
	local result = {}
	for _, id in ids do
		result[id] = point
	end
	return result
end
for _, count in { 1, 2, 12 } do
	local ids = {}
	for index = 1, count do
		table.insert(ids, index)
	end
	for _, kind in { "PressureWave", "ChangingWalls" } do
		local run, now = Session.new(Math, kind, 2, ids, 0), 0
		while not run.Completed do
			if run.Stage == "Warning" then
				now = run.EndsAt
				local point = if kind == "PressureWave"
					then Math.worldPoint(
						Math.point(run.Plan.Covers[#run.Plan.Covers], 5, 30),
						run.Plan.Quarter
					)
					else Math.route(run.Plan)[1]
				run.Update(now, samples(ids, point))
			elseif run.Stage == "Active" then
				local route = if kind == "ChangingWalls"
					then Math.route(run.Plan)
					else {
						Math.worldPoint(
							Math.point(run.Plan.Covers[#run.Plan.Covers], 5, 30),
							run.Plan.Quarter
						),
					}
				for index = 2, #route do
					local a, b = route[index - 1], route[index]
					local distance = math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
					local steps = math.max(1, math.ceil(distance / (12 * 0.05)))
					for step = 1, steps do
						now += 0.05
						local t = step / steps
						run.Update(
							now,
							samples(ids, Math.point(a.X + (b.X - a.X) * t, 5, a.Z + (b.Z - a.Z) * t))
						)
					end
				end
				while run.Stage == "Active" do
					now += 0.05
					run.Update(now, samples(ids, route[#route]))
				end
			elseif run.Stage == "Recovery" then
				now = run.EndsAt
				run.Update(now, samples(ids, Math.worldPoint(Math.point(28, 5, 35), run.Plan.Quarter)))
			end
		end
		for _, id in ids do
			expect(run.Players[id].Passed, "Every admitted participant can solve both experimental beats")
		end
		expect(
			run.Completed and run.Beat == 2 and not run.Stopped,
			"Both beats finish without production rewards"
		)
	end
end
do
	local run = Session.new(Math, "PressureWave", 0, { 1 }, 0)
	local survivedFirst = false
	for tick = 0, 500 do
		run.Update(tick * 0.05, { [1] = Math.point(0, 5, 0) })
		if run.Beat == 1 and run.Stage == "Recovery" then
			survivedFirst = run.Players[1].Alive
		end
	end
	expect(survivedFirst, "The central first-wave shelter is a legitimate starting solution")
	expect(
		run.Completed and run.Beat == 2 and not run.Players[1].Alive and not run.Players[1].Passed,
		"Staying in the first central shelter fails the second wave"
	)
end
do
	local run = Session.new(Math, "PressureWave", 0, { 1, 2 }, 0)
	run.Update(5, { [1] = Math.point(14, 5, 20), [2] = Math.point(28, 5, 20) })
	for step = 1, 121 do
		run.Update(
			5 + step * 0.05,
			{ [1] = Math.point(14, 5, 20), [2] = Math.point(28, 5, 20), [3] = Math.point(28, 5, 20) }
		)
	end
	expect(
		not run.Players[1].Alive and run.Players[2].Alive,
		"A wave rejects exposure but accepts an actual shelter"
	)
	expect(run.Players[3] == nil, "Late spectator cannot gain a participant record")
	run.Leave(2)
	run.Update(12, {})
	expect(run.Completed and not run.Players[2].Passed, "Departure cannot become a pass")
end
do
	local run = Session.new(Math, "ChangingWalls", 0, { 1 }, 0)
	run.Update(5, { [1] = Math.point(28, 5, -20) })
	run.Update(5.5, { [1] = Math.point(28, 5, -8) })
	expect(not run.Players[1].Alive, "A solid-wall crossing cannot satisfy a route")
	run.Update(6, {})
	expect(run.Completed and not run.Players[1].Passed, "Invalid route never becomes a result win")
end
for _, kind in { "PressureWave", "ChangingWalls" } do
	for _, phase in { "Warning", "Active" } do
		local run = Session.new(Math, kind, 0, { 1 }, 0)
		if phase == "Active" then
			run.Update(5, { [1] = Math.point(0, 5, -35) })
		end
		run.Stop()
		run.Stop()
		run.Update(100, { [1] = Math.point(28, 5, 35) })
		expect(
			run.Completed and run.Stopped and not run.Players[1].Passed,
			"Cancellation is idempotent and grants no pass"
		)
	end
end
do
	local run = Session.new(Math, "ChangingWalls", 0, { 1 }, 0)
	run.Update(5, { [1] = Math.point(0, 5, -35) })
	run.Update(5.05, { [1] = Math.point(0, 5, 35) })
	expect(not run.Players[1].Alive, "Teleporting through the course is rejected")
end
expect(not pcall(Session.new, Math, "Unknown", 0, { 1 }, 0), "Unknown kind cannot start")
do
	local run = Session.new(Math, "ChangingWalls", 0, { 1 }, 0)
	run.Update(5, { [1] = Math.point(-28, 5, -35) })
	run.Update(19.9, { [1] = Math.point(-28, 5, -35) })
	run.Update(23, { [1] = Math.point(-28, 5, 35) })
	expect(
		run.Completed and not run.Players[1].Alive and run.Players[1].Gate == 0,
		"A delayed frame cannot grant gates crossed after the route deadline"
	)
end
for _, finishAt in { 19, 20 } do
	local run = Session.new(Math, "ChangingWalls", 0, { 1 }, 0)
	run.Update(5, { [1] = Math.point(-28, 5, -35) })
	run.Update(finishAt, { [1] = Math.point(-28, 5, 35) })
	if finishAt < 20 then
		run.Update(23, { [1] = Math.point(-28, 5, 35) })
	end
	expect(
		run.Stage == "Recovery" and run.Players[1].Alive and run.Players[1].Gate == 2,
		"A route finished before or exactly at its deadline remains accepted"
	)
	expect(
		run.EndsAt == (if finishAt < 20 then 24 else 21),
		"Late processing does not consume the next recovery or warning"
	)
end
do
	local run = Session.new(Math, "PressureWave", 0, { 1 }, 0)
	run.Update(5, { [1] = Math.point(20, 5, 35) })
	run.Update(10, { [1] = Math.point(20, 5, 35) })
	run.Update(12, { [1] = Math.point(28, 5, 35) })
	expect(
		run.Completed and run.Players[1].Crossed and not run.Players[1].Alive,
		"Movement after the wave deadline cannot retroactively turn an exposed contact into cover"
	)
end
for _, missing in { false, true } do
	local run = Session.new(Math, "ChangingWalls", 0, { 1 }, 0)
	run.Update(5, { [1] = Math.point(-28, 5, -35) })
	run.Update(19, { [1] = Math.point(-28, 5, 35) })
	run.Update(23, if missing then {} else { [1] = Math.point(0 / 0, 5, 35) })
	expect(
		run.Completed and not run.Players[1].Alive and not run.Players[1].Passed,
		"A late missing or invalid sample cannot inherit a previous successful position"
	)
end
for _, clock in { 4, math.huge, 0 / 0 } do
	local run = Session.new(Math, "PressureWave", 0, { 1 }, 0)
	run.Update(5, { [1] = Math.point(28, 5, 35) })
	expect(
		not pcall(run.Update, clock, { [1] = Math.point(28, 5, 35) }),
		"Backwards or nonfinite clocks cannot advance an active experiment"
	)
	run.Update(11, { [1] = Math.point(28, 5, 35) })
	expect(
		run.Stage == "Recovery" and run.Players[1].Alive,
		"Rejected clocks do not corrupt the next valid update"
	)
end
for _, kind in { "PressureWave", "ChangingWalls" } do
	local run = Session.new(Math, kind, 0, { 1 }, 0)
	if kind == "PressureWave" then
		run.Update(5, { [1] = Math.point(28, 5, 35) })
		run.Update(11, { [1] = Math.point(28, 5, 35) })
	else
		run.Update(5, { [1] = Math.point(-28, 5, -35) })
		run.Update(20, { [1] = Math.point(-28, 5, 35) })
	end
	expect(run.Stage == "Recovery", "Recovery cancellation exercises the gap between beats")
	run.Stop()
	run.Stop()
	run.Update(100, { [1] = Math.point(28, 5, 35), [2] = Math.point(28, 5, 35) })
	expect(
		run.Stopped and run.Completed and not run.Players[1].Passed and run.Players[2] == nil,
		"Recovery cancellation is terminal, admits nobody, and never grants a pass"
	)
end
print(string.format("ExperimentSession: %d checks passed (local state machine only)", checks))
