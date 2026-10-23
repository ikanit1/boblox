-- Install as a LocalScript in StarterPlayerScripts so clients added later also receive it.
-- Sends bounded INVALID ProfileAction requests only. Never changes movement/input/camera/settings.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio(), "QALifecycle client is restricted to Studio")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local qa = ReplicatedStorage:WaitForChild("QALifecycle", 30)
assert(qa, "QALifecycle server is missing")
local command = qa:WaitForChild("ClientCommand", 10)
local report = qa:WaitForChild("ClientReport", 10)
local remote = ReplicatedStorage:WaitForChild("RuleRoomRemotes"):WaitForChild("ProfileAction")
assert(command and report and remote:IsA("RemoteEvent"), "QA/profile remotes are missing")
local stopped, busy, lastSequence = false, false, 0
local connections = {}

local function cleanup()
	if stopped then
		return
	end
	stopped = true
	for _, connection in connections do
		connection:Disconnect()
	end
end

-- No entry is a valid purchase, equip, or quest claim, even for an established profile.
local malformed = {
	{ action = "Purchase", id = "__QA_MISSING_TRAIL" },
	{ action = "Equip", id = "__QA_MISSING_TRAIL" },
	{ action = "ClaimQuest", id = "__QA_MISSING_QUEST" },
	{ action = false, id = "Cyan" },
	{ action = "Purchase", id = false },
	{ action = "Purchase", id = { Id = "Cyan", Price = -1 } },
	{ action = "Equip", id = 0 / 0 },
	{ action = "Equip", id = math.huge },
	{ action = "Equip", id = ReplicatedStorage },
	{ action = string.rep("X", 64), id = "None" },
	{ action = "ClaimQuest", id = string.rep("Z", 4096) },
	{},
}
table.insert(
	connections,
	command.OnClientEvent:Connect(function(sequence, kind, count, interval)
		if
			stopped
			or busy
			or kind ~= "SpamProfile"
			or type(sequence) ~= "number"
			or sequence ~= sequence
			or sequence <= lastSequence
		then
			return
		end
		if type(count) ~= "number" or count ~= count or count % 1 ~= 0 or count < 12 or count > 48 then
			return
		end
		if interval == nil then
			interval = 0.02
		end
		if type(interval) ~= "number" or interval ~= interval or interval < 0.02 or interval > 0.5 then
			return
		end
		lastSequence, busy = sequence, true
		local sent, errors, firstError = 0, 0, ""
		for index = 1, count do
			if stopped or qa:GetAttribute("Complete") or not qa.Parent then
				break
			end
			local payload = malformed[(index - 1) % #malformed + 1]
			local ok, failure = pcall(function()
				remote:FireServer(payload.action, payload.id)
			end)
			sent += 1
			if not ok then
				errors += 1
				if firstError == "" then
					firstError = string.sub(tostring(failure), 1, 200)
				end
			end
			task.wait(interval)
		end
		if not stopped and qa.Parent then
			report:FireServer("SpamDone", sequence, sent, errors, firstError, interval)
		end
		busy = false
	end)
)
table.insert(
	connections,
	qa:GetAttributeChangedSignal("Complete"):Connect(function()
		if qa:GetAttribute("Complete") then
			cleanup()
		end
	end)
)
script.Destroying:Connect(cleanup)
if qa:GetAttribute("Complete") then
	cleanup()
else
	-- Server connects the listener before Ready; wait for that explicit installation boundary.
	local deadline = os.clock() + 15
	while not stopped and not qa:GetAttribute("Ready") and os.clock() < deadline do
		task.wait(0.05)
	end
	assert(qa:GetAttribute("Ready"), "QALifecycle server initialization timed out")
	if not stopped then
		report:FireServer("Ready")
	end
end
