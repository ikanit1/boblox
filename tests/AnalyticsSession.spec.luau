--!strict
local AnalyticsSession = require("../src/server/AnalyticsSession")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function harness()
	local events = {}
	local session = AnalyticsSession.new(function(event)
		table.insert(events, event)
	end)
	local snapshot = {
		Round = 1,
		InRound = false,
		ResultReady = false,
		RunResult = "None",
		DataStatus = "Session",
		DataPersistent = false,
	}
	local function count(name: string, category: string?): number
		local found = 0
		for _, event in events do
			if event.Name == name and (category == nil or event.Category == category) then
				found += 1
			end
		end
		return found
	end
	return session, snapshot, events, count
end

for _, result in { "NoSurvival", "FinaleMissed", "Won", "Aborted" } do
	local s, snapshot, events, count = harness()
	s.Intent("Join")
	expect(count("RepeatIntent") == 0, "Initial Play is not a repeat")
	s.Observe(snapshot)
	expect(count("FirstTrialStarted") == 0, "Exploring is not trial admission")
	snapshot.InRound = true
	s.Observe(snapshot)
	s.Observe(snapshot)
	expect(
		count("FirstTrialStarted") == 1 and count("RRV2_RunStarted", "First") == 1,
		"Admission deduplicates"
	)
	snapshot.InRound = false
	snapshot.ResultReady = true
	snapshot.RunResult = result
	s.Observe(snapshot)
	s.Observe(snapshot)
	expect(count("FirstResultsAvailable") == 1, "Results include zero survivals, forfeited finale and abort")
	expect(
		count("RRV2_ResultsAvailable", result) == 1,
		"Personal outcome stays distinct from results availability"
	)
	snapshot.ResultReady = false
	s.Observe(snapshot)
	snapshot.ResultReady = true
	s.Observe(snapshot)
	expect(count("RRV2_ResultsAvailable") == 1, "Repeated Ready edge does not duplicate results")
	s.Intent("Vote")
	s.Intent("Join")
	expect(
		count("RepeatIntent") == 1 and count("RRV2_RepeatIntent", "Vote") == 1,
		"Explicit choices deduplicate before entry"
	)
	snapshot.ResultReady = false
	snapshot.Round = 2
	snapshot.InRound = true
	s.Observe(snapshot)
	expect(
		count("IntentionalNextRunStarted") == 1,
		"Only later admission after explicit intent advances funnel"
	)
	expect(count("RRV2_RunStarted", "AfterIntent") == 1, "Intent and admission are separate events")
	local previous = 0
	for _, event in events do
		if event.Step then
			expect(event.Step == previous + 1, "Funnel has no optional skipped survival step")
			previous = event.Step
		end
	end
	s.Close()
	local before = #events
	s.Intent("Join")
	snapshot.Round = 3
	s.Observe(snapshot)
	expect(#events == before, "Closed sessions emit nothing")
end

do
	local s, snapshot, _, count = harness()
	snapshot.Round = 7
	snapshot.InRound = true
	s.Observe(snapshot)
	snapshot.InRound = false
	snapshot.ResultReady = true
	snapshot.RunResult = "NoSurvival"
	s.Observe(snapshot)
	snapshot.ResultReady = false
	snapshot.Round = 8
	snapshot.InRound = true
	s.Observe(snapshot)
	expect(count("RRV2_RunStarted", "Automatic") == 1, "Automatic next run is observable separately")
	expect(
		count("RepeatIntent") == 0 and count("IntentionalNextRunStarted") == 0,
		"AFK admission is not interest"
	)
	s.Intent("scripted")
	expect(count("RepeatIntent") == 0, "Unknown intent source is rejected")
	s.Intent("Join")
	s.Observe(snapshot)
	expect(
		count("IntentionalNextRunStarted") == 0,
		"Late choice never retroactively changes an automatic run"
	)
	snapshot.Round = 9
	s.Observe(snapshot)
	expect(count("IntentionalNextRunStarted") == 1, "Late explicit choice applies to a later run")
end

do
	local s, snapshot, _, count = harness()
	for _, value in { 0, -1, 0.5, math.huge, 0 / 0, "1", true } do
		local invalid: any = table.clone(snapshot)
		invalid.Round = value
		invalid.InRound = true
		invalid.ResultReady = true
		s.Observe(invalid)
	end
	expect(
		count("FirstTrialStarted") == 0 and count("FirstResultsAvailable") == 0,
		"Invalid rounds cannot forge milestones"
	)
	snapshot.ResultReady = true
	s.Observe(snapshot)
	expect(
		count("FirstResultsAvailable") == 0,
		"Unadmitted observer does not acquire another player's results"
	)
	snapshot.ResultReady = false
	snapshot.DataStatus = "Saved"
	snapshot.DataPersistent = true
	s.Observe(snapshot)
	snapshot.DataStatus = "Unavailable"
	s.Observe(snapshot)
	s.Observe(snapshot)
	expect(
		count("RRV2_ProfileState", "SaveDelayed") == 1,
		"Save delay is bounded and does not imply lease loss"
	)
	expect(count("RRV2_ProfileState", "PersistenceLost") == 0, "Live lease remains persistent during retry")
	snapshot.DataStatus = "Saved"
	s.Observe(snapshot)
	expect(count("RRV2_ProfileState", "SaveRecovered") == 1, "Recovery is distinct")
	snapshot.DataStatus = "Unavailable"
	snapshot.DataPersistent = false
	s.Observe(snapshot)
	expect(
		count("RRV2_ProfileState", "PersistenceLost") == 1,
		"Persistent-to-temporary transition is observed"
	)
	for _ = 1, 100 do
		s.Observe(snapshot)
	end
	expect(count("RRV2_ProfileState", "PersistenceLost") == 1, "Repeated errors cannot flood status events")
	snapshot.DataStatus = "raw user text"
	s.Observe(snapshot)
	expect(count("RRV2_ProfileState", "raw user text") == 0, "Custom fields use only fixed categories")
end
print("AnalyticsSession: " .. checks .. " checks passed")
