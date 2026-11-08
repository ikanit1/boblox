--!strict
-- Production ledger with Lune JSON adapters; no Roblox replication evidence.
local Ledger = require("../src/server/ContributionLedger")
local View = require("../src/shared/ContributionView")
local serde = require("@lune/serde")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function encode(value)
	return serde.encode("json", value)
end
local function decode(value)
	return serde.decode("json", value)
end

local ledger = Ledger.new(72, 6)
for _, invalid in { 0, 0 / 0, math.huge, -math.huge, 1.5, 1e12 + 1, -1e12 - 1 } do
	expect(ledger.Admit(invalid, "Invalid") == nil, "Malformed identities are not admitted")
end
ledger.Update(999, 1, 10, 1, 1, "Won")
expect(#ledger.Snapshot(1).Players == 0, "Updating a spectator never creates a row")
local first = assert(ledger.Admit(1, "Первый"))
expect(ledger.Admit(1, "Duplicate") == first, "Repeated admission in the same segment is idempotent")
ledger.Update(1, first, 15, 1, 0, nil)
ledger.Update(1, first, 15, 1, 0, nil)
local original = ledger.Snapshot(1)
expect(
	#original.Players == 1 and original.Players[1].Score == 15,
	"Cumulative segment counters are not summed twice"
)
original.Players[1].Score = 99
expect(ledger.Snapshot(1).Players[1].Score == 15, "Snapshots cannot mutate the authoritative social ledger")
ledger.Leave(1, first)
ledger.Leave(1, first)
local departed = ledger.Snapshot(1).Players[1]
expect(
	departed.Left and departed.Outcome == "Left" and departed.Survived == 1,
	"Departed contribution remains visible"
)
local second = assert(ledger.Admit(1, "Вернулся"))
expect(
	second ~= first and #ledger.Snapshot(1).Players == 1,
	"Returning identity has a fresh segment in the same row"
)
ledger.Update(1, first, 999, 6, 999, "Won")
ledger.Leave(1, first)
ledger.Update(1, second, 25, 2, 1, "NotEnoughTrials")
local joined = ledger.Snapshot(1).Players[1]
expect(
	joined.Name == "Вернулся"
		and not joined.Left
		and joined.Score == 40
		and joined.Survived == 3
		and joined.Energy == 1
		and joined.Outcome == "NotEnoughTrials",
	"Rejoin sums contributions while retaining the latest segment's personal result"
)
ledger.Update(1, second, 25, 2, 1, "NotEnoughTrials")
expect(ledger.Snapshot(1).Players[1].Score == 40, "Repeated finalization never doubles rejoin contribution")
local localIdentity = assert(ledger.Admit(-1, "Local client"))
ledger.Update(-1, localIdentity, 1e12, 100, math.huge, "Unknown")
local bounded = ledger.Snapshot(1).Players[2]
expect(
	bounded.Score == 1e9 and bounded.Survived == 6 and bounded.Energy == 0 and bounded.Outcome == "Aborted",
	"Counters and outcomes are bounded and validated"
)
ledger.Reset()
expect(
	#ledger.Snapshot(2).Players == 0 and not ledger.Snapshot(2).Truncated,
	"New run clears all presentation-only history"
)
local newRunToken = assert(ledger.Admit(1, "New run"))
ledger.Update(1, second, 999, 6, 99, "Won")
expect(
	newRunToken ~= second and ledger.Snapshot(2).Players[1].Score == 0,
	"Old run tokens cannot modify a later run"
)

local capacity = Ledger.new(1000, 6)
for userId = 1, 72 do
	local token = assert(capacity.Admit(userId, string.rep("Ж", 50)))
	capacity.Update(userId, token, 1e9, 6, 1e9, "Won")
	if userId <= 60 then
		capacity.Leave(userId, token)
	end
end
local full = decode(capacity.Encode(7, encode))
local clientRows = View.read(full, 7, 7)
expect(
	clientRows ~= nil and #clientRows == 72,
	"Actual shared client validator accepts the maximum production snapshot"
)
expect(
	#full.Players == 72 and not full.Truncated and full.Round == 7 and full.Version == 1,
	"All 72 unique boundary admissions fit in one versioned run snapshot"
)
expect(
	full.Players[1].Left and not full.Players[72].Left,
	"Earlier departed participants are retained beside the final cohort"
)
expect(utf8.len(full.Players[1].Name) == 24, "Display labels truncate at a Unicode character boundary")
expect(
	#capacity.Encode(7, encode) <= Ledger.MaxBytes,
	"Maximum ordinary snapshot remains below the fixed byte budget"
)
expect(
	capacity.Admit(73, "Overflow") == nil,
	"Unexpected admissions above the proof bound cannot grow memory"
)
expect(
	capacity.Snapshot(7).Truncated and #capacity.Snapshot(7).Players == 72,
	"Exceptional overflow is explicit instead of silently hiding rows"
)

local names = Ledger.new(3, 6)
names.Admit(1, "\0\n\tName\r")
names.Admit(2, string.char(255))
names.Admit(3, "")
local cleaned = decode(names.Encode(1, encode)).Players
expect(
	cleaned[1].Name == "Name" and cleaned[2].Name == "Игрок" and cleaned[3].Name == "Игрок",
	"Controls, invalid UTF-8 and empty names use safe presentation labels"
)
local calls = 0
local budgeted = decode(capacity.Encode(7, function(value)
	calls += 1
	return if #value.Players > 12 then string.rep(" ", Ledger.MaxBytes + 1) else encode(value)
end))
expect(
	#budgeted.Players == 12 and budgeted.Truncated and calls == 61,
	"Byte-budget fallback removes tail rows and announces truncation with bounded work"
)
local failed = decode(capacity.Encode(7, function()
	error("Injected serializer failure")
end))
expect(
	View.read(failed, 7, 7) ~= nil,
	"Actual client validator accepts the explicit serialization-failure fallback"
)
expect(
	failed.Round == 7 and #failed.Players == 0 and failed.Truncated,
	"Presentation serialization failure returns a bounded explicit fallback"
)
expect(#capacity.Snapshot(7).Players == 72, "Serialization fallback never mutates the retained ledger")

print("ContributionLedger: " .. checks .. " checks passed (pure ledger/serialization adapters)")
