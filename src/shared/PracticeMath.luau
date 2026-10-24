--!strict
-- Pure acceptance policy. Practice has no economic rewards.
local PracticeMath = {}

function PracticeMath.canCheckpoint(
	current: number,
	target: number,
	dx: number,
	dz: number,
	feetAbove: number,
	verticalSpeed: number,
	sinceCheckpoint: number
): boolean
	return target == current + 1
		and target >= 1
		and target <= 7
		and math.abs(dx) <= 6.15
		and math.abs(dz) <= 6.15
		and feetAbove >= -0.5
		and feetAbove <= 0.65
		and math.abs(verticalSpeed) <= 3
		and sinceCheckpoint >= 0.65
end

function PracticeMath.canInteract(
	action: any,
	inRound: boolean,
	distance: number,
	sinceRequest: number
): boolean
	return typeof(action) == "string"
		and (action == "Explore" or action == "Join" or action == "Practice")
		and not inRound
		and distance >= 0
		and distance <= 13
		and sinceRequest >= 0.4
end

return PracticeMath
