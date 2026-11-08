--!strict
-- Authoritative swept geometry shared by the two traversal hazards; no Roblox services.
local TraversalMath = {}

export type Point = { X: number, Y: number, Z: number }
export type Plan = { Quarter: number, Covers: { number }, GapX: number }
export type Body = { x: number, z: number, feetY: number, headY: number, halfX: number, halfZ: number }

function TraversalMath.finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function TraversalMath.valid(point: Point): boolean
	return TraversalMath.finite(point.X) and TraversalMath.finite(point.Y) and TraversalMath.finite(point.Z)
end

function TraversalMath.localPoint(point: Point, quarter: number): Point
	local x, z = point.X, point.Z
	for _ = 1, quarter % 4 do
		x, z = z, -x
	end
	return { X = x, Y = point.Y, Z = z }
end

function TraversalMath.worldPoint(point: Point, quarter: number): Point
	return TraversalMath.localPoint(point, -quarter)
end

function TraversalMath.plan(quarter: number, beat: number, halfSize: number, gapX: number): Plan
	return {
		Quarter = (quarter + (beat - 1) * 2) % 4,
		Covers = if beat % 2 == 1
			then { -halfSize * 2 / 3, 0, halfSize * 2 / 3 }
			else { -halfSize / 3, halfSize / 3 },
		GapX = gapX,
	}
end

function TraversalMath.lerp(before: Point, after: Point, alpha: number): Point
	return {
		X = before.X + (after.X - before.X) * alpha,
		Y = before.Y + (after.Y - before.Y) * alpha,
		Z = before.Z + (after.Z - before.Z) * alpha,
	}
end

-- A delayed callback cannot use a position reached after the active deadline.
function TraversalMath.clip(
	before: Point,
	after: Point,
	previousElapsed: number,
	elapsed: number,
	duration: number
): Point?
	if
		not TraversalMath.valid(before)
		or not TraversalMath.valid(after)
		or not TraversalMath.finite(elapsed)
		or elapsed < previousElapsed
	then
		return nil
	end
	if elapsed <= duration then
		return after
	end
	local span = elapsed - previousElapsed
	return TraversalMath.lerp(
		before,
		after,
		if span > 0 then math.clamp((duration - previousElapsed) / span, 0, 1) else 0
	)
end

function TraversalMath.front(alpha: number, halfSize: number, radius: number): number
	local edge = halfSize + radius + 1
	return -edge + math.clamp(alpha, 0, 1) * edge * 2
end

-- Return the complete overlapping interval, not just its entry point. A player
-- cannot enter through a gap and then sidestep into the same moving wall for free.
function TraversalMath.contactInterval(
	before: Point,
	after: Point,
	frontBefore: number,
	frontAfter: number,
	quarter: number,
	radius: number
): (number?, number?)
	if not TraversalMath.valid(before) or not TraversalMath.valid(after) then
		return nil, nil
	end
	local start = TraversalMath.localPoint(before, quarter).Z - frontBefore
	local finish = TraversalMath.localPoint(after, quarter).Z - frontAfter
	local delta = finish - start
	if math.abs(delta) < 0.000001 then
		return if math.abs(start) <= radius then 0 else nil, if math.abs(start) <= radius then 1 else nil
	end
	local a, b = (-radius - start) / delta, (radius - start) / delta
	local enter, leave = math.max(0, math.min(a, b)), math.min(1, math.max(a, b))
	if enter > leave then
		return nil, nil
	end
	return enter, leave
end

function TraversalMath.shelterIndex(
	point: Point,
	plan: Plan,
	width: number,
	depth: number,
	z: number,
	height: number,
	radius: number
): number?
	if not TraversalMath.valid(point) then
		return nil
	end
	local localPoint = TraversalMath.localPoint(point, plan.Quarter)
	if localPoint.Z < z + depth / 2 + radius or localPoint.Y + radius > height then
		return nil
	end
	for index, x in plan.Covers do
		if math.abs(localPoint.X - x) <= width / 2 - radius then
			return index
		end
	end
	return nil
end

function TraversalMath.inGap(point: Point, plan: Plan, halfWidth: number, radius: number): boolean
	return TraversalMath.valid(point)
		and math.abs(TraversalMath.localPoint(point, plan.Quarter).X - plan.GapX) <= halfWidth - radius
end

function TraversalMath.lerpBody(before: Body, after: Body, alpha: number): Body
	return {
		x = before.x + (after.x - before.x) * alpha,
		z = before.z + (after.z - before.z) * alpha,
		feetY = before.feetY + (after.feetY - before.feetY) * alpha,
		headY = before.headY + (after.headY - before.headY) * alpha,
		halfX = before.halfX + (after.halfX - before.halfX) * alpha,
		halfZ = before.halfZ + (after.halfZ - before.halfZ) * alpha,
	}
end

-- Intersect linear body/beam motion in time, including jump clearance. The six
-- inequalities must overlap at the same instant; unrelated endpoint hits do not count.
function TraversalMath.beamContact(
	before: Body,
	after: Body,
	frontBefore: number,
	frontAfter: number,
	halfWidth: number
): boolean
	local lower, upper = 0, 1
	local function within(a: number, b: number): boolean
		if not TraversalMath.finite(a) or not TraversalMath.finite(b) then
			return false
		end
		if a > 0 and b > 0 then
			return false
		elseif a > 0 then
			lower = math.max(lower, a / (a - b))
		elseif b > 0 then
			upper = math.min(upper, a / (a - b))
		end
		return lower <= upper
	end
	return within(before.x - halfWidth - before.halfX, after.x - halfWidth - after.halfX)
		and within(-before.x - halfWidth - before.halfX, -after.x - halfWidth - after.halfX)
		and within(before.z - frontBefore - 0.5 - before.halfZ, after.z - frontAfter - 0.5 - after.halfZ)
		and within(frontBefore - before.z - 0.5 - before.halfZ, frontAfter - after.z - 0.5 - after.halfZ)
		and within(before.feetY - 2.4, after.feetY - 2.4)
		and within(1.4 - before.headY, 1.4 - after.headY)
end

return TraversalMath
