--!strict
-- Production world-label rendering with local adapters; no native layout or touch evidence.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local source = fs.readFile("src/client/Station.client.luau")
local first = assert(string.find(source, "local function renderPracticeSigns()", 1, true))
local last = assert(string.find(source, "local function render()", first, true))
local production = string.sub(source, first, last - 1)
	.. "\nreturn { Render = renderPracticeSigns, Restore = restorePracticeSigns }"
local values = { LobbyOnly = true, EntryChoiceMade = true }
local function label(text)
	local data = { Text = text }
	return setmetatable({}, {
		__index = data,
		__newindex = function(_, name, value)
			assert(name == "Text", "World-label render must not alter layout, input or visibility")
			data[name] = value
		end,
	})
end
local prompt = { ActionText = "Original action", ObjectText = "Original title" }
local sign = { Heading = label("Original heading"), Detail = label("Original detail") }
local finish = label("02")
local controller = luau.load(production, {
	debugName = "PRODUCTION_StationPracticeSigns",
	environment = {
		player = {
			GetAttribute = function(_, name)
				return values[name]
			end,
		},
		practicePrompt = prompt,
		practiceSign = sign,
		warmupFinishLabel = finish,
		practiceSignDefaults = {
			ActionText = prompt.ActionText,
			ObjectText = prompt.ObjectText,
			Heading = sign.Heading.Text,
			Detail = sign.Detail.Text,
			Finish = finish.Text,
		},
	},
})()
controller.Render()
expect(
	prompt.ObjectText == "ПАРКУР · 7 ТОЧЕК" and sign.Heading.Text == "ПАРКУР / 07",
	"Exploration advertises the full record course"
)
expect(
	finish.Text == "02" and string.find(sign.Detail.Text, "рекорд", 1, true) ~= nil,
	"Full course keeps the second platform as an intermediate checkpoint"
)
values.LobbyOnly = false
values.EntryChoiceMade = false
controller.Render()
expect(sign.Heading.Text == "ПАРКУР / 07", "An unconfirmed newcomer is never described as queued")
values.EntryChoiceMade = true
controller.Render()
expect(
	prompt.ObjectText == "2 ПРЫЖКА · ТЫ В ОЧЕРЕДИ"
		and sign.Heading.Text == "РАЗМИНКА / 02",
	"Queue prompt clearly advertises a short optional warmup"
)
expect(
	string.find(sign.Detail.Text, "Очередь сохранится", 1, true) ~= nil
		and finish.Text == "02\nГОТОВО",
	"The world signs explain queue preservation and the short finish"
)
values.PracticeMode, values.PracticeState, values.PracticeCheckpoint = "Warmup", "Running", 1
controller.Render()
expect(
	string.find(sign.Detail.Text, "1/2", 1, true) ~= nil
		and string.find(sign.Detail.Text, "01 → 02", 1, true) ~= nil,
	"The active warmup gives a concrete ordered landing instruction"
)
values.PracticeState, values.PracticeCheckpoint = "Finished", 2
controller.Render()
expect(
	string.find(sign.Detail.Text, "Готово! Ты в очереди", 1, true) ~= nil
		and string.find(sign.Detail.Text, "автоматически", 1, true) ~= nil,
	"Warmup completion describes automatic admission without a record or reward claim"
)
values.LobbyOnly = true
controller.Render()
expect(
	prompt.ObjectText == "ПАРКУР · 7 ТОЧЕК" and finish.Text == "02",
	"Switching to exploration restores the full course interpretation"
)
controller.Restore()
expect(
	prompt.ActionText == "Original action"
		and prompt.ObjectText == "Original title"
		and sign.Heading.Text == "Original heading"
		and sign.Detail.Text == "Original detail"
		and finish.Text == "02",
	"Destroy cleanup restores authored world labels"
)
print("Station practice presentation: " .. checks .. " checks passed (production labels; no native UI)")
