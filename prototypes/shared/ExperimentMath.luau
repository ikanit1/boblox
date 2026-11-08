--!strict
-- Isolated CONTENT01 geometry. This module is not mapped into the shipping game.
local Math = {}
Math.HalfSize = 42
Math.BodyRadius = 2
Math.CoverWidth = 16
Math.CoverDepth = 4
Math.CoverHeight = 14
Math.CoverZ = -12
Math.GapHalfWidth = 9
Math.WarningSeconds = 5
Math.PressureSeconds = 6
Math.RouteSeconds = 15
Math.RecoverySeconds = 1
Math.Beats = 2

export type Point = { X: number, Y: number, Z: number }
function Math.finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
function Math.point(x: number, y: number, z: number): Point
	return { X = x, Y = y, Z = z }
end
function Math.validPoint(point: any): boolean
	return type(point) == "table" and Math.finite(point.X) and Math.finite(point.Y) and Math.finite(point.Z)
end
function Math.localPoint(point: Point, quarter: number): Point
	local x, z = point.X, point.Z
	for _ = 1, quarter % 4 do
		x, z = z, -x
	end
	return Math.point(x, point.Y, z)
end
function Math.worldPoint(point: Point, quarter: number): Point
	return Math.localPoint(point, (4 - quarter % 4) % 4)
end
function Math.plan(kind: string, seed: number, beat: number): any
	assert(kind == "PressureWave" or kind == "ChangingWalls", "Unknown experimental rule")
	assert(Math.finite(seed) and seed % 1 == 0 and seed >= 0, "Seed must be a nonnegative integer")
	assert(beat >= 1 and beat <= Math.Beats and beat % 1 == 0, "Beat out of range")
	local quarter = if kind == "PressureWave" then (seed + (beat - 1) * 2) % 4 else (beat - 1) * 2
	local gaps = { -28, 0, 28 }
	return {
		Kind = kind,
		Quarter = quarter,
		-- Alternate lanes as well as direction so no ground position shelters both waves.
		Covers = if kind == "PressureWave" and beat == 2 then { -14, 14 } else { -28, 0, 28 },
		Gates = { { X = gaps[seed % 3 + 1], Z = -14 }, { X = gaps[math.floor(seed / 3) % 3 + 1], Z = 14 } },
	}
end
function Math.inside(point: Point): boolean
	return Math.validPoint(point)
		and math.abs(point.X) <= 41
		and math.abs(point.Z) <= 41
		and point.Y >= 1
		and point.Y <= 24
end
function Math.sheltered(point: Point, plan: any): boolean
	local p = Math.localPoint(point, plan.Quarter)
	if
		p.Z < Math.CoverZ + Math.CoverDepth / 2 + Math.BodyRadius
		or p.Y > Math.CoverHeight - Math.BodyRadius
	then
		return false
	end
	for _, x in plan.Covers do
		if math.abs(p.X - x) <= Math.CoverWidth / 2 - Math.BodyRadius then
			return true
		end
	end
	return false
end
function Math.front(alpha: number): number
	return -44 + math.clamp(alpha, 0, 1) * 88
end
-- Intersect the moving wave with the swept player sample; no endpoint-only tunneling.
function Math.waveContact(previous: Point, current: Point, before: number, after: number, plan: any): Point?
	local p, c = Math.localPoint(previous, plan.Quarter), Math.localPoint(current, plan.Quarter)
	local a, b = p.Z - before, c.Z - after
	if a < 0 or b > 0 or a == b then
		return nil
	end
	local t = math.clamp(a / (a - b), 0, 1)
	return Math.worldPoint(
		Math.point(p.X + (c.X - p.X) * t, p.Y + (c.Y - p.Y) * t, p.Z + (c.Z - p.Z) * t),
		plan.Quarter
	)
end
function Math.crossGate(previous: Point, current: Point, plan: any, index: number): (boolean, boolean)
	local p, c = Math.localPoint(previous, plan.Quarter), Math.localPoint(current, plan.Quarter)
	local gate = plan.Gates[index]
	if p.Z >= gate.Z or c.Z < gate.Z or p.Z == c.Z then
		return false, false
	end
	local t = (gate.Z - p.Z) / (c.Z - p.Z)
	local x = p.X + (c.X - p.X) * t
	return true, math.abs(x - gate.X) <= Math.GapHalfWidth - Math.BodyRadius
end
function Math.route(plan: any): { Point }
	local points = { Math.point(0, 5, -35) }
	for _, gate in plan.Gates do
		table.insert(points, Math.point(gate.X, 5, gate.Z - 4))
		table.insert(points, Math.point(gate.X, 5, gate.Z + 4))
	end
	table.insert(points, Math.point(plan.Gates[2].X, 5, 35))
	for index, point in points do
		points[index] = Math.worldPoint(point, plan.Quarter)
	end
	return points
end
function Math.shelterRoute(start: Point, plan: any): { Point }
	local p = Math.localPoint(start, plan.Quarter)
	local x = plan.Covers[1]
	for _, value in plan.Covers do
		if math.abs(p.X - value) < math.abs(p.X - x) then
			x = value
		end
	end
	local points = { p }
	if p.Z < -8 then
		local side = x + (if p.X < x then -10.5 else 10.5)
		local approach = math.min(p.Z, -18)
		table.insert(points, Math.point(p.X, 5, approach))
		table.insert(points, Math.point(side, 5, approach))
		table.insert(points, Math.point(side, 5, -6))
		table.insert(points, Math.point(x, 5, -6))
	else
		table.insert(points, Math.point(x, 5, p.Z))
	end
	for index, point in points do
		points[index] = Math.worldPoint(point, plan.Quarter)
	end
	return points
end
return Math
