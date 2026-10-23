-- Scratch client observer; writes only PlayerScripts.QATimerEvidence.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Http = game:GetService("HttpService")
assert(RunService:IsStudio() and RunService:IsClient(), "Studio client only")
local player = Players.LocalPlayer
local scripts = player:WaitForChild("PlayerScripts", 15)
local state = RS:WaitForChild("RuleRoomState", 15)
assert(scripts and state, "Client game not ready")
assert(not scripts:FindFirstChild("QATimerEvidence"), "Timer observer already installed")
local output = Instance.new("Folder")
output.Name = "QATimerEvidence"
output:SetAttribute("SchemaVersion", 1)
output:SetAttribute("UserId", player.UserId)
output:SetAttribute("StartedAt", Workspace:GetServerTimeNow())
output:SetAttribute("Complete", false)
output:SetAttribute("Stop", false)
output:SetAttribute("CaseCount", 0)
output.Parent = scripts
local current, connection, lastDeadline, deadlineChangedAt, mismatchAt
local active, count, elapsed = true, 0, 0
local lastPhase = state:GetAttribute("Phase")
local installedMidRule = lastPhase == "Rule"
local expires = os.clock() + 1200
local mismatchReported = false
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function rendered(label)
	if not label or not label:IsA("TextLabel") or label.TextTransparency >= 1 then
		return false
	end
	local p, s = label.AbsolutePosition, label.AbsoluteSize
	local camera = Workspace.CurrentCamera
	if not camera or s.X <= 0 or s.Y <= 0 then
		return false
	end
	local left, top = math.max(0, p.X), math.max(0, p.Y)
	local right, bottom =
		math.min(camera.ViewportSize.X, p.X + s.X), math.min(camera.ViewportSize.Y, p.Y + s.Y)
	local ancestor = label
	while ancestor and ancestor ~= player.PlayerGui do
		if ancestor:IsA("GuiObject") then
			if not ancestor.Visible then
				return false
			end
			if ancestor.ClipsDescendants then
				local ap, az = ancestor.AbsolutePosition, ancestor.AbsoluteSize
				left, top = math.max(left, ap.X), math.max(top, ap.Y)
				right, bottom = math.min(right, ap.X + az.X), math.min(bottom, ap.Y + az.Y)
			end
		elseif ancestor:IsA("ScreenGui") and not ancestor.Enabled then
			return false
		end
		ancestor = ancestor.Parent
	end
	return right > left and bottom > top
end
local function range(target, key, value)
	target[key .. "Min"] = math.min(target[key .. "Min"] or value, value)
	target[key .. "Max"] = math.max(target[key .. "Max"] or value, value)
end
local function issue(kind, now, expected, observed, duration)
	current.issueCount += 1
	if #current.issues < 64 then
		table.insert(
			current.issues,
			{ kind = kind, at = now, expected = expected, observed = observed, duration = duration }
		)
	else
		current.truncated = true
	end
end
local function closeCase(reason)
	if not current then
		return
	end
	current.closedAt = Workspace:GetServerTimeNow()
	current.closedReason = reason
	current.noNegativeObserved = current.negativeSamples == 0
	current.status = if current.sampleCount == 0 or current.evaluatedSamples == 0
		then "no_evaluable_samples"
		elseif current.issueCount > 0 then "observed_mismatch"
		elseif
			current.startedMidRule
			or current.truncated
			or (reason ~= "trial_boundary" and reason ~= "coverage_complete")
		then "partial_observation"
		else "observed_within_tolerance"
	local item = Instance.new("StringValue")
	item.Name = string.format("Case_%03d", count)
	item.Value = Http:JSONEncode(current)
	item.Parent = output
	output:SetAttribute("CaseCount", count)
	current, lastDeadline, deadlineChangedAt, mismatchAt = nil, nil, nil, nil
	mismatchReported = false
end
local function finish(reason, err)
	if not active then
		return
	end
	active = false
	if connection then
		connection:Disconnect()
	end
	closeCase(reason)
	output:SetAttribute("EndReason", reason)
	if err then
		output:SetAttribute("Error", tostring(err))
	end
	output:SetAttribute("Complete", true)
end
local function step(frameDt, sampleDt)
	if output:GetAttribute("Stop") == true then
		finish("requested_stop")
		return
	end
	if os.clock() > expires then
		finish("time_limit")
		return
	end
	local coverage = RS:FindFirstChild("QARuleCoverage")
	local phase = state:GetAttribute("Phase")
	local now = Workspace:GetServerTimeNow()
	if phase ~= "Rule" then
		if current then
			closeCase("trial_boundary")
		end
		lastPhase = phase
		installedMidRule = false
		if coverage and coverage:GetAttribute("Complete") == true then
			finish("coverage_complete")
		end
		return
	end
	local entry = coverage and coverage:GetAttribute("EntryIndex")
	local rule = if coverage then coverage:GetAttribute("Current") else state:GetAttribute("RuleId")
	local key = if entry
		then "coverage:" .. tostring(entry) .. ":" .. tostring(rule)
		else "main:" .. tostring(state:GetAttribute("Round")) .. ":" .. tostring(
			state:GetAttribute("RuleIndex")
		) .. ":" .. tostring(rule)
	if current and key ~= current.key then
		closeCase("case_changed_without_break")
	end
	if not current then
		if count >= 64 then
			finish("case_limit")
			return
		end
		count += 1
		current = {
			schemaVersion = 1,
			key = key,
			entryIndex = entry,
			rule = rule,
			userId = player.UserId,
			behavior = coverage and coverage:GetAttribute("Behavior"),
			openedAt = now,
			startedMidRule = installedMidRule or lastPhase == "Rule",
			sampleCount = 0,
			renderedSamples = 0,
			evaluatedSamples = 0,
			settlingSamples = 0,
			missingDeadlineSamples = 0,
			nonNumericSamples = 0,
			negativeSamples = 0,
			mismatchSamples = 0,
			issueCount = 0,
			maxDifference = 0,
			maxMismatchDuration = 0,
			samples = {},
			sampleColumns = {
				"at",
				"deadline",
				"expected",
				"observed",
				"renderEligible",
				"frameDt",
				"sampleDt",
				"settling",
			},
			deadlineChanges = {},
			issues = {},
			truncated = false,
			tolerance = { settleSeconds = 0.2, sustainedMismatchSeconds = 0.25, immediateDifferenceAbove = 1 },
			limits = "Client replicated deadline and render eligibility; not pixel/occlusion evidence. Partial cases and zero evaluated samples are never full acceptance.",
		}
		installedMidRule = false
	end
	lastPhase = phase
	current.sampleCount += 1
	current.earliestAt = current.earliestAt or now
	current.latestAt = now
	range(current, "frameDt", frameDt)
	range(current, "sampleDt", sampleDt)
	local deadline = state:GetAttribute("PhaseEndsAt")
	if not finite(deadline) or deadline <= 0 then
		current.missingDeadlineSamples += 1
		return
	end
	if deadline ~= lastDeadline then
		if #current.deadlineChanges < 64 then
			table.insert(current.deadlineChanges, { at = now, previous = lastDeadline, value = deadline })
		else
			current.truncated = true
		end
		lastDeadline, deadlineChangedAt, mismatchAt = deadline, now, nil
		mismatchReported = false
	end
	local settle = now - deadlineChangedAt < 0.2
	local expected = math.max(0, math.ceil(deadline - now))
	local pg = player:FindFirstChild("PlayerGui")
	local gui = pg and pg:FindFirstChild("RuleRoomHUD")
	local root = gui and gui:FindFirstChild("Root")
	local panel = root and root:FindFirstChild("RulePanel")
	local timer = panel and panel:FindFirstChild("Timer")
	local label = timer and timer:FindFirstChild("Countdown")
	local visible = rendered(label)
	local text = if label and label:IsA("TextLabel") then label.Text else ""
	local observed = tonumber(text)
	if visible then
		current.renderedSamples += 1
	end
	if settle then
		current.settlingSamples += 1
	end
	range(current, "expected", expected)
	if finite(observed) then
		range(current, "observed", observed)
	end
	if #current.samples < 1200 then
		table.insert(current.samples, {
			now,
			deadline,
			expected,
			if finite(observed) then observed else text,
			visible,
			frameDt,
			sampleDt,
			settle,
		})
	else
		current.truncated = true
	end
	if visible and finite(observed) and observed < 0 then
		current.negativeSamples += 1
		if current.negativeSamples == 1 then
			issue("negative_visible_countdown", now, expected, observed, 0)
		end
	end
	if not visible or settle then
		mismatchAt = nil
		mismatchReported = false
		return
	end
	if not finite(observed) then
		current.nonNumericSamples += 1
	else
		current.evaluatedSamples += 1
		local difference = math.abs(expected - observed)
		current.maxDifference = math.max(current.maxDifference, difference)
		if difference == 0 then
			mismatchAt = nil
			mismatchReported = false
			return
		end
	end
	current.mismatchSamples += 1
	mismatchAt = mismatchAt or now
	local duration = now - mismatchAt
	current.maxMismatchDuration = math.max(current.maxMismatchDuration, duration)
	local huge = finite(observed) and math.abs(expected - observed) > 1
	if not mismatchReported and (huge or duration > 0.25) then
		issue(
			if huge then "difference_above_one" else "sustained_mismatch",
			now,
			expected,
			if finite(observed) then observed else text,
			duration
		)
		mismatchReported = true
	end
	if coverage and coverage:GetAttribute("Complete") == true then
		finish("coverage_complete")
	end
end
connection = RunService.RenderStepped:Connect(function(delta)
	elapsed += delta
	if elapsed < 0.05 then
		return
	end
	local sampleDt = elapsed
	elapsed = 0
	local ok, err = xpcall(function()
		step(delta, sampleDt)
	end, debug.traceback)
	if not ok then
		finish("observer_error", err)
	end
end)
return "QATimerEvidence active on client " .. player.UserId
