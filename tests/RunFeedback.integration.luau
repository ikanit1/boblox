--!strict
-- Executes the production client module with local signals/UI adapters, not a native GUI test.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local Hints = require("../src/shared/PlayerHints")
local checks = 0
local scenarios = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

local function signal()
	local entries = {}
	return {
		Connect = function(_, callback)
			local entry = { Active = true, Callback = callback }
			table.insert(entries, entry)
			return {
				Disconnect = function()
					entry.Active = false
				end,
			}
		end,
		Fire = function()
			for _, entry in entries do
				if entry.Active then
					entry.Callback()
				end
			end
		end,
	}
end

local function object(attributes)
	local signals = {}
	return {
		GetAttribute = function(_, name)
			return attributes[name]
		end,
		GetAttributeChangedSignal = function(_, name)
			if not signals[name] then
				signals[name] = signal()
			end
			return signals[name]
		end,
		SetAttribute = function(_, name, value)
			local before = attributes[name]
			attributes[name] = value
			if before ~= value and signals[name] then
				signals[name]:Fire()
			end
		end,
	}
end

local Economy = luau.load(fs.readFile("src/shared/EconomyConfig.luau"), {
	environment = { Color3 = Roblox.Color3 },
	injectGlobals = true,
})()

local function harness(initialSurvived: number?, initialOutcome: string?)
	scenarios += 1
	local player = object({
		RunSurvived = initialSurvived or 0,
		LastTrialOutcome = initialOutcome or "Playing",
		InRound = true,
		LobbyOnly = false,
		RunStars = 0,
	})
	local state = object({ Phase = "Rule", HazardStage = "Active", RuleId = "SafeColor" })
	local gui = object({ StationModal = "", ReducedMotion = true, CompactPlayHUD = false })
	local messages = {}
	local delayed = {}
	local toast: any = {
		Visible = false,
		Pulse = { Scale = 1 },
		Message = setmetatable({}, {
			__newindex = function(_, key, value)
				if key == "Text" then
					table.insert(messages, value)
				end
			end,
		}),
	}
	local shared = {
		WaitForChild = function(_, name)
			return name
		end,
	}
	local services = {
		TweenService = {},
		Workspace = {
			GetServerTimeNow = function()
				return 100
			end,
		},
		ReplicatedStorage = {
			WaitForChild = function()
				return shared
			end,
		},
	}
	local production = luau.load(fs.readFile("src/client/RunFeedback.luau"), {
		debugName = "RunFeedback.production",
		environment = {
			game = {
				GetService = function(_, name)
					return assert(services[name], name)
				end,
			},
			Color3 = Roblox.Color3,
			task = {
				delay = function(_, callback)
					table.insert(delayed, callback)
				end,
			},
			require = function(name)
				return if name == "PlayerHints" then Hints else Economy
			end,
		},
		injectGlobals = true,
	})()
	local feedback = production.new(player, state, gui, toast)
	return {
		Player = player,
		State = state,
		Gui = gui,
		Toast = toast,
		Messages = messages,
		Delayed = delayed,
		Feedback = feedback,
	}
end

do
	local h = harness()
	h.Player:SetAttribute("RunSurvived", 1)
	expect(#h.Messages == 0, "Counter arriving first waits for an authoritative awarded outcome")
	h.Player:SetAttribute("LastTrialOutcome", "Survived")
	expect(#h.Messages == 1, "Counter then outcome produces one success toast")
	expect(
		string.find(h.Messages[1], "ИСПЫТАНИЕ ПРОЙДЕНО", 1, true) ~= nil,
		"Success toast names the award"
	)
	h.Player:SetAttribute("LastTrialOutcome", "Survived")
	h.Player:SetAttribute("RunSurvived", 1)
	expect(#h.Messages == 1, "Repeated values do not replay the award")
	h.Player:SetAttribute("LastTrialOutcome", "Playing")
	h.Player:SetAttribute("LastTrialOutcome", "Survived")
	expect(#h.Messages == 1, "Outcome arriving first waits for the increased survival counter")
	h.Player:SetAttribute("RunSurvived", 2)
	expect(#h.Messages == 2, "Outcome then counter also produces exactly one success toast")
	h.Feedback.Destroy()
end

do
	local h = harness()
	h.Player:SetAttribute("MovementWarning", true)
	h.Player:SetAttribute("LastTrialOutcome", "Forfeited")
	expect(
		#h.Messages == 1 and h.Messages[1] == Hints.Forfeited.Toast,
		"Forfeited emits its own non-reward toast"
	)
	h.Player:SetAttribute("RunSurvived", 0)
	expect(#h.Messages == 1, "No increased survival total and no duplicate forfeited toast")
	h.Player:SetAttribute("MovementWarning", false)
	-- A later successful stage may arrive before its Playing edge is observed locally.
	h.Player:SetAttribute("RunSurvived", 1)
	expect(#h.Messages == 1, "A stale Forfeited edge never announces coins")
	h.Player:SetAttribute("LastTrialOutcome", "Survived")
	expect(#h.Messages == 2, "A later confirmed success is not lost after a forfeited stage")
	expect(
		string.find(h.Messages[2], "ИСПЫТАНИЕ ПРОЙДЕНО", 1, true) ~= nil,
		"Recovered success announces the real award"
	)
	h.Feedback.Destroy()
end

do
	local h = harness(4, "Survived")
	expect(#h.Messages == 0, "Starting the controller never replays an old award")
	h.Player:SetAttribute("RunSurvived", 0)
	h.Player:SetAttribute("LastTrialOutcome", "Pending")
	h.Player:SetAttribute("LastTrialOutcome", "Playing")
	h.Player:SetAttribute("RunSurvived", 1)
	h.Player:SetAttribute("LastTrialOutcome", "Survived")
	expect(#h.Messages == 1, "A new run resets the counter used for deduplication")
	h.Feedback.Destroy()
	expect(h.Toast.Visible == false, "Destroy hides feedback")
	h.Player:SetAttribute("LastTrialOutcome", "Forfeited")
	h.Player:SetAttribute("RunSurvived", 2)
	for _, callback in h.Delayed do
		callback()
	end
	expect(
		#h.Messages == 1 and h.Toast.Visible == false,
		"Disposed signals and pending timers cannot revive feedback"
	)
end

do
	local h = harness()
	h.Gui:SetAttribute("CompactPlayHUD", true)
	h.Player:SetAttribute("LastTrialOutcome", "Forfeited")
	expect(h.Messages[1] == Hints.Forfeited.CompactToast, "Compact feedback uses the short forfeited wording")
	h.Player:SetAttribute("LastTrialOutcome", "Playing")
	h.State:SetAttribute("HazardStage", "Warning")
	expect(h.Toast.Visible == false, "Warning clears compact feedback to preserve hazard readability")
	h.Player:SetAttribute("LastTrialOutcome", "Forfeited")
	expect(#h.Messages == 1, "Warning suppresses compact outcome overlays")
	h.Feedback.Destroy()
end

for _, order in
	{
		{ "RunSurvived", "LastTrialOutcome", "MovementWarning" },
		{ "RunSurvived", "MovementWarning", "LastTrialOutcome" },
		{ "LastTrialOutcome", "RunSurvived", "MovementWarning" },
		{ "LastTrialOutcome", "MovementWarning", "RunSurvived" },
		{ "MovementWarning", "RunSurvived", "LastTrialOutcome" },
		{ "MovementWarning", "LastTrialOutcome", "RunSurvived" },
	}
do
	local h = harness(0, "Forfeited")
	h.Player:SetAttribute("MovementWarning", true)
	local values = { RunSurvived = 1, LastTrialOutcome = "Survived", MovementWarning = false }
	for _, name in order do
		h.Player:SetAttribute(name, values[name])
	end
	expect(#h.Messages == 1, "All outcome/counter/warning delivery orders emit exactly one award")
	expect(
		string.find(h.Messages[1], "ИСПЫТАНИЕ ПРОЙДЕНО", 1, true) ~= nil,
		"Clearing a stale warning recovers pending success"
	)
	h.Feedback.Destroy()
end

print("RunFeedback integration: " .. checks .. " checks passed in " .. scenarios .. " scenarios")
