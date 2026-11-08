--!strict
-- Personal result policy; rewards remain owned by ProfileService and RuleMath.
local RunPresentation = {}
local minimumSurvivals = 4

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
	elseif survived < minimumSurvivals then
		return "NotEnoughTrials"
	end
	return "Won"
end

-- Entering at trial four of six cannot meet the unchanged four-survival rule.
-- Unknown/no participation (zero) is not labelled as a late attempt.
function RunPresentation.isLateEntry(firstTrial: number, trialCount: number): boolean
	return firstTrial >= 1 and firstTrial <= trialCount and trialCount - firstTrial + 1 < minimumSurvivals
end

-- Forfeited confirms admission only; it is not a rewarded survival or an elimination.
function RunPresentation.firstEnteredTrial(outcomes: { string }): number
	for index, outcome in outcomes do
		if
			outcome == "Playing"
			or outcome == "Survived"
			or outcome == "Eliminated"
			or outcome == "Forfeited"
		then
			return index
		end
	end
	return 0
end

-- Essential result rows always exist. Only the secondary trial strip is omitted
-- on short screens; an authored ScrollingFrame provides access below its viewport.
function RunPresentation.resultsLayout(availableHeight: number)
	local viewportHeight = math.clamp(availableHeight, 1, 270)
	local contentHeight = math.max(190, viewportHeight)
	local compact = contentHeight < 240
	return {
		ViewportHeight = viewportHeight,
		ContentHeight = contentHeight,
		Rows = {
			Heading = { Y = if compact then 6 else 8, Height = if compact then 24 else 28, Visible = true },
			Summary = { Y = if compact then 32 else 40, Height = if compact then 18 else 22, Visible = true },
			Personal = { Y = if compact then 52 else 66, Height = if compact then 28 else 32, Visible = true },
			Rewards = { Y = if compact then 82 else 100, Height = if compact then 34 else 38, Visible = true },
			Trials = { Y = 144, Height = 22, Visible = not compact },
			Goal = { Y = if compact then 118 else 172, Height = if compact then 36 else 38, Visible = true },
			Next = {
				Y = if compact then 160 else contentHeight - 26,
				Height = if compact then 24 else 20,
				Visible = true,
			},
		},
	}
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
