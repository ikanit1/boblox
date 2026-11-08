--!strict
-- Pure clock/participant logic for an isolated place. No production rewards or profile writes.
local Session = {}
function Session.new(mathPolicy: any, kind: string, seed: number, ids: { number }, now: number)
	assert(#ids >= 1 and #ids <= 12, "Experimental admission is bounded to 1..12")
	assert(mathPolicy.finite(now), "Invalid start clock")
	local players = {}
	for _, id in ids do
		assert(type(id) == "number" and not players[id], "Duplicate or invalid participant")
		players[id] = { Alive = true, Passed = false, Gate = 0, Previous = nil, Crossed = false }
	end
	local self: any = {
		Kind = kind,
		Beat = 1,
		Stage = "Warning",
		EndsAt = now + mathPolicy.WarningSeconds,
		Plan = mathPolicy.plan(kind, seed, 1),
		Players = players,
		Completed = false,
		Stopped = false,
	}
	local lastNow, activeAt, previousFront = now, now, -44
	local function remaining(): number
		local count = 0
		for _, record in players do
			if record.Alive then
				count += 1
			end
		end
		return count
	end
	local function fail(record)
		record.Alive, record.Passed = false, false
	end
	function self.Leave(id: number)
		if players[id] then
			fail(players[id])
		end
	end
	function self.Stop()
		if self.Completed then
			return
		end
		self.Stopped, self.Completed, self.Stage = true, true, "Stopped"
	end
	function self.Update(clock: number, samples: { [number]: any })
		if self.Completed then
			return
		end
		assert(mathPolicy.finite(clock) and clock >= lastNow, "Clock must be finite and monotonic")
		local dt = clock - lastNow
		local evaluationClock = if self.Stage == "Active" then math.min(clock, self.EndsAt) else clock
		local evaluationDt = math.max(0, evaluationClock - lastNow)
		lastNow = clock
		local evaluatedSamples = {}
		for id, record in players do
			local point = samples[id]
			if record.Alive then
				if not point or not mathPolicy.inside(point) then
					fail(record)
				else
					if self.Stage == "Active" and record.Previous then
						local p = record.Previous
						-- Evaluate only the part of a late sample that precedes the deadline.
						local ratio = if dt > 0 then math.clamp(evaluationDt / dt, 0, 1) else 1
						point = mathPolicy.point(
							p.X + (point.X - p.X) * ratio,
							p.Y + (point.Y - p.Y) * ratio,
							p.Z + (point.Z - p.Z) * ratio
						)
						local distance = math.sqrt((point.X - p.X) ^ 2 + (point.Z - p.Z) ^ 2)
						if distance > 36 * evaluationDt + 3 then
							fail(record)
						end
					end
					evaluatedSamples[id] = point
				end
			end
		end
		if remaining() == 0 then
			self.Completed, self.Stage = true, "Finished"
			return
		end
		if self.Stage == "Warning" and clock >= self.EndsAt then
			self.Stage, activeAt, previousFront = "Active", clock, -44
			self.EndsAt = clock
				+ (if kind == "PressureWave" then mathPolicy.PressureSeconds else mathPolicy.RouteSeconds)
			for id, record in players do
				record.Previous, record.Gate, record.Crossed = samples[id], 0, false
			end
			return
		end
		if self.Stage == "Active" then
			local currentFront = mathPolicy.front((evaluationClock - activeAt) / mathPolicy.PressureSeconds)
			for id, record in players do
				local point = evaluatedSamples[id]
				if record.Alive and record.Previous then
					if kind == "PressureWave" and not record.Crossed then
						local contact = mathPolicy.waveContact(
							record.Previous,
							point,
							previousFront,
							currentFront,
							self.Plan
						)
						if contact then
							record.Crossed = true
							if not mathPolicy.sheltered(contact, self.Plan) then
								fail(record)
							end
						end
					elseif kind == "ChangingWalls" then
						for index = record.Gate + 1, 2 do
							local crossed, valid =
								mathPolicy.crossGate(record.Previous, point, self.Plan, index)
							if crossed then
								if valid then
									record.Gate = index
								else
									fail(record)
									break
								end
							else
								break
							end
						end
					end
					record.Previous = point
				end
			end
			previousFront = currentFront
			self.Front = currentFront
			if clock >= self.EndsAt then
				for id, record in players do
					if record.Alive then
						local p = mathPolicy.localPoint(evaluatedSamples[id], self.Plan.Quarter)
						if
							(kind == "PressureWave" and not record.Crossed)
							or (kind == "ChangingWalls" and (record.Gate ~= 2 or p.Z < 30))
						then
							fail(record)
						end
					end
				end
				if self.Beat >= mathPolicy.Beats or remaining() == 0 then
					self.Stage, self.Completed = "Finished", true
					for _, record in players do
						record.Passed = record.Alive
					end
				else
					self.Stage, self.EndsAt = "Recovery", clock + mathPolicy.RecoverySeconds
				end
			end
		elseif self.Stage == "Recovery" and clock >= self.EndsAt then
			self.Beat += 1
			self.Plan = mathPolicy.plan(kind, seed + (if kind == "ChangingWalls" then 4 else 0), self.Beat)
			self.Stage, self.EndsAt = "Warning", clock + mathPolicy.WarningSeconds
		end
	end
	return self
end
return Session
