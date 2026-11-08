--!strict
local View = require("../src/shared/ContributionView")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function payload()
	return {
		Version = 1,
		Round = 2,
		Players = {
			{
				UserId = 1,
				Name = "Игрок",
				Score = 120,
				Survived = 4,
				Energy = 2,
				Outcome = "Won",
				Left = false,
			},
		},
		Truncated = false,
	}
end
local data = payload()
local rows = assert(View.read(data, 2, 2))
expect(#rows == 1 and string.find(rows[1].Detail, "4/6", 1, true) ~= nil, "Personal contribution is explicit")
expect(rows[1].Outcome == "ПОБЕДА", "Only an accepted outcome receives a victory label")
data.Players[1].Left = true
expect(
	assert(View.read(data, 2, 2))[1].Outcome == "ВЫШЕЛ ИЗ ИГРЫ",
	"Departure cannot be disguised as current presence"
)
expect(
	View.read(data, 3, 2) == nil and View.read(data, 2, 3) == nil,
	"Stale payload and both barrier orders are rejected"
)
for _, invalid in { -1, 0 / 0, math.huge, "4", 1.5 } do
	local bad: any = payload()
	bad.Players[1].Survived = invalid
	expect(View.read(bad, 2, 2) == nil, "Malformed count is rejected")
end
for _, field in { "Score", "Energy", "UserId" } do
	local bad: any = payload()
	bad.Players[1][field] = math.huge
	expect(View.read(bad, 2, 2) == nil, "Unbounded values are rejected")
end
for _, invalid in { "", string.rep("a", 201), string.char(255) } do
	local bad = payload()
	bad.Players[1].Name = invalid
	expect(View.read(bad, 2, 2) == nil, "Invalid display name is rejected")
end
local bad: any = payload()
bad.Players[1].Outcome = "ForgedWin"
expect(View.read(bad, 2, 2) == nil, "Unknown outcome is not a victory")
bad = payload()
table.insert(bad.Players, table.clone(bad.Players[1]))
expect(View.read(bad, 2, 2) == nil, "Duplicate UserId is not a second contribution")
bad = payload()
bad.Players.Extra = bad.Players[1]
expect(View.read(bad, 2, 2) == nil, "Dictionary entries are rejected")
bad = payload()
for index = 2, 73 do
	local entry = table.clone(bad.Players[1])
	entry.UserId = index
	table.insert(bad.Players, entry)
end
expect(View.read(bad, 2, 2) == nil, "More than 72 contributions are rejected")
table.remove(bad.Players)
expect(#assert(View.read(bad, 2, 2)) == 72, "Every possible twelve-player trial cohort fits")
bad.Version = 2
expect(View.read(bad, 2, 2) == nil, "Future protocol does not guess a result")
expect(View.read(nil, 2, 2) == nil, "Missing attributes are tolerated")
print(string.format("ContributionView: %d checks passed", checks))
