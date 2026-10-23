--!strict

-- Pure geometry, deliberately independent of Roblox Instances for repeatable tests.
local RuleMath = {}

export type BodyBounds = {
	x: number,
	z: number,
	feetY: number,
	headY: number,
	halfX: number,
	halfZ: number,
}

function RuleMath.isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function RuleMath.sweptBeamIntersects(
	body: BodyBounds,
	previousZ: number,
	currentZ: number,
	beamY: number,
	beamHalfHeight: number,
	beamHalfDepth: number,
	beamHalfWidth: number
): boolean
	-- Include the complete path between server samples so fast beams do not tunnel.
	local lowZ = math.min(previousZ, currentZ) - beamHalfDepth - body.halfZ
	local highZ = math.max(previousZ, currentZ) + beamHalfDepth + body.halfZ
	return math.abs(body.x) <= beamHalfWidth + body.halfX
		and body.z >= lowZ
		and body.z <= highZ
		and body.feetY <= beamY + beamHalfHeight
		and body.headY >= beamY - beamHalfHeight
end

function RuleMath.pingPong(elapsed: number, traversalSeconds: number, halfRange: number): number
	local cycle = (elapsed / traversalSeconds) % 2
	local alpha = if cycle <= 1 then cycle else 2 - cycle
	return -halfRange + alpha * halfRange * 2
end

function RuleMath.insideZone(
	x: number,
	z: number,
	centerX: number,
	centerZ: number,
	halfSize: number
): boolean
	return RuleMath.isFinite(x)
		and RuleMath.isFinite(z)
		and math.abs(x - centerX) <= halfSize
		and math.abs(z - centerZ) <= halfSize
end

function RuleMath.spinnerIntersects(
	body: BodyBounds,
	angle: number,
	halfLength: number,
	radius: number
): boolean
	local along = body.x * math.cos(angle) - body.z * math.sin(angle)
	local across = body.x * math.sin(angle) + body.z * math.cos(angle)
	return math.abs(along) <= halfLength + body.halfX
		and math.abs(across) <= radius + body.halfZ
		and body.feetY <= 2.4
		and body.headY >= 1.4
end

function RuleMath.spinnerHalfLength(arenaHalfSize: number): number
	-- Cover the diagonal to the square's corners, not only the middle of each edge.
	return arenaHalfSize * math.sqrt(2)
end

function RuleMath.finaleSucceeded(charge: number, goal: number, completed: boolean, alive: number): boolean
	return completed and charge >= goal and alive > 0
end

function RuleMath.runOutcome(
	survived: number,
	survivedFinale: boolean,
	teamSuccess: boolean
): (boolean, boolean)
	return survived >= 1, survived >= 4 and survivedFinale and teamSuccess
end

function RuleMath.teamGoal(players: number): number
	return math.max(5, math.clamp(math.floor(players), 1, 12) * 2)
end

-- Conservative plausibility envelopes, not authoritative character simulation.
-- The minimum observation interval absorbs bursty replication; extra distance
-- allows normal avatar collisions and turn/position correction jitter.
function RuleMath.travelPlausible(distance: number, elapsed: number, walkSpeed: number): boolean
	if
		not RuleMath.isFinite(distance)
		or not RuleMath.isFinite(elapsed)
		or not RuleMath.isFinite(walkSpeed)
		or distance < 0
		or elapsed < 0
		or walkSpeed < 0
	then
		return false
	end
	local allowance = math.max(16, walkSpeed) * 1.5 * math.max(0.75, elapsed) + 12
	return distance <= allowance
end

function RuleMath.airbornePlausible(seconds: number, gravity: number): boolean
	if not RuleMath.isFinite(seconds) or not RuleMath.isFinite(gravity) or seconds < 0 or gravity <= 0 then
		return false
	end
	return seconds <= (if gravity < 100 then 7 else 4)
end

return RuleMath
