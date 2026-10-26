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

-- A server position sample can skip the brief contact between two native jumps.
-- Only a descent-to-ascent reversal close to the same supporting floor can be
-- consistent with a missed landing. This does not accept a midair jump/hover.
function RuleMath.missedLanding(
	previousFeetHeight: number,
	feetHeight: number,
	previousVelocity: number,
	velocity: number,
	elapsed: number,
	gravity: number,
	jumpSpeed: number
): boolean
	for _, value in
		{ previousFeetHeight, feetHeight, previousVelocity, velocity, elapsed, gravity, jumpSpeed }
	do
		if not RuleMath.isFinite(value) then
			return false
		end
	end
	if
		elapsed <= 0
		or elapsed > 0.25
		or gravity <= 0
		or jumpSpeed <= 0
		or previousFeetHeight < -0.25
		or feetHeight < -0.25
		or previousVelocity >= -1
		or velocity <= 1
		or velocity > jumpSpeed * 1.1
	then
		return false
	end
	-- A single replicated frame may differ from the server sample by ~100ms.
	-- Bound that uncertainty by one stud of positional error, and never infer a
	-- landing from an impulse above the maximum height of this character's jump.
	local maximumHeight = jumpSpeed * jumpSpeed / (2 * gravity)
	if previousFeetHeight > maximumHeight + 1 or feetHeight > maximumHeight + 1 then
		return false
	end
	local fallTime = (
		previousVelocity + math.sqrt(previousVelocity ^ 2 + 2 * gravity * math.max(0, previousFeetHeight))
	) / gravity
	local riseTime = math.max(0, (jumpSpeed - velocity) / gravity)
	local expectedHeight = jumpSpeed * riseTime - gravity * riseTime * riseTime / 2
	return fallTime <= elapsed + 0.1
		and math.abs(fallTime + riseTime - elapsed) <= 0.1
		and math.abs(feetHeight - expectedHeight) <= 1
end

return RuleMath
