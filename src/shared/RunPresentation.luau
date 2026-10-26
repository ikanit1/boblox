--!strict
-- Personal result policy; rewards remain owned by ProfileService and RuleMath.
local RunPresentation = {}

function RunPresentation.resultCode(
	survived: number,
	survivedFinale: boolean,
	teamSuccess: boolean,
	aborted: boolean?
): string
	if aborted then
		return "Aborted"
	elseif survived < 1 then
		return "NoSurvival"
	elseif not teamSuccess then
		return "FinaleFailed"
	elseif not survivedFinale then
		return "FinaleMissed"
	elseif survived < 4 then
		return "NotEnoughTrials"
	end
	return "Won"
end

function RunPresentation.rewardDelta(before: any, after: any): number
	if
		type(before) ~= "number"
		or type(after) ~= "number"
		or before ~= before
		or after ~= after
		or math.abs(before) == math.huge
		or math.abs(after) == math.huge
	then
		return 0
	end
	return math.max(0, after - before)
end

return RunPresentation
