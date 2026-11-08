--!strict
local Availability = require("../src/server/RuleAvailability")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local rules = {
	"SafeColor",
	"LaserSweep",
	"LowGravity",
	"RedLight",
	"LavaRise",
	"MeteorRain",
	"DisappearingTiles",
	"SafeZone",
	"Spinner",
	"ReactorRush",
}
local source = { Disabled_SafeColor = true, Disabled_LowGravity = false, Disabled_Untrusted = true }
local disabled, reason = Availability.snapshot(source, rules)
expect(disabled ~= nil and disabled.SafeColor == true and reason == nil, "Known explicit disable is copied")
expect(
	disabled ~= nil and disabled.LowGravity == nil and disabled.Untrusted == nil,
	"False and unknown attributes do not become disabled rules"
)
source.Disabled_SafeColor = false
expect(
	disabled ~= nil and disabled.SafeColor == true,
	"A later control edit cannot mutate an active snapshot"
)
for _, id in rules do
	for _, invalid in { "true", 1, {}, math.huge } do
		local result, failure = Availability.snapshot({ ["Disabled_" .. id] = invalid }, rules)
		expect(result == nil and failure == "InvalidFlag", "Known flags accept booleans only")
	end
end
local finale, finaleReason = Availability.snapshot({ Disabled_ReactorRush = true }, rules)
expect(finale == nil and finaleReason == "FinaleDisabled", "The mandatory finale can only pause new runs")
local defaults = Availability.snapshot({}, rules)
expect(defaults ~= nil and next(defaults) == nil, "Missing flags mean the original catalog")
expect(
	string.find(Availability.message("FinaleDisabled"), "Реактор", 1, true) ~= nil,
	"Finale pause has a readable explanation"
)
expect(
	Availability.message("InvalidFlag") ~= "" and Availability.message(nil) ~= "",
	"Every failure has a player-facing waiting message"
)
print("RuleAvailability: " .. checks .. " checks passed")
