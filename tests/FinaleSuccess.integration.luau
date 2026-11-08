--!strict
-- Execute the actual Main finale block (survivor award + FinaleSuccess decision) without
-- running the server loop. Roster eligibility and personal rewards are covered by
-- PlayerRoster.integration; here only the production decision around them is exercised.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local source = fs.readFile("src/server/Main.server.luau")
local block =
	source:match('(local awarded, forfeitedAlive%s*=.-\n%s*if ruleId == "ReactorRush" then.-\n%s*end)')
assert(block, "Locate the production Main finale decision; do not substitute a copied formula")

local checks = 0
local cases = {
	{
		name = "charged forfeited survivor keeps team success",
		charged = true,
		completed = true,
		awarded = 0,
		forfeited = 1,
		expected = true,
	},
	{
		name = "multiple forfeited survivors keep team success",
		charged = true,
		completed = true,
		awarded = 0,
		forfeited = 3,
		expected = true,
	},
	{
		name = "ordinary survivor keeps team success",
		charged = true,
		completed = true,
		awarded = 1,
		forfeited = 0,
		expected = true,
	},
	{
		name = "mixed survivors keep team success",
		charged = true,
		completed = true,
		awarded = 1,
		forfeited = 1,
		expected = true,
	},
	{
		name = "full charge with nobody living fails",
		charged = true,
		completed = true,
		awarded = 0,
		forfeited = 0,
		expected = false,
	},
	{
		name = "uncharged reactor fails with forfeited survivor",
		charged = false,
		completed = true,
		awarded = 0,
		forfeited = 1,
		expected = false,
	},
	{
		name = "uncharged reactor fails with ordinary survivor",
		charged = false,
		completed = true,
		awarded = 1,
		forfeited = 0,
		expected = false,
	},
	{
		name = "cancelled finale fails despite living forfeited player",
		charged = true,
		completed = false,
		awarded = 0,
		forfeited = 1,
		expected = false,
	},
	{
		name = "cancelled finale cannot use a stale awarded count",
		charged = true,
		completed = false,
		awarded = 1,
		forfeited = 0,
		expected = false,
	},
}
for _, case in cases do
	local finale: any = case.charged
	local run = luau.load(block, {
		debugName = "PRODUCTION_MainFinaleDecision",
		environment = {
			ruleId = "ReactorRush",
			completed = case.completed,
			state = {
				GetAttribute = function(_, name)
					assert(name == "FinaleSuccess", "Read only the reactor's charged result")
					return finale
				end,
				SetAttribute = function(_, name, value)
					assert(name == "FinaleSuccess", "Write only the finale result")
					finale = value
				end,
			},
			roster = {
				AwardSurvivors = function(ruleId)
					assert(ruleId == "ReactorRush", "Survivors are awarded for the finale rule")
					return case.awarded, case.forfeited
				end,
			},
		},
	})
	run()
	assert(finale == case.expected, case.name)
	checks += 1
end
print("Main finale decision: " .. checks .. " checks passed (production expression; no native server loop)")
