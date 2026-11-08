--!strict
-- Production Station reload button and request gates. This is not a cloud or native UI test.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local ProfileStatus = require("../src/shared/ProfileStatus")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local source = fs.readFile("src/client/Station.client.luau")
local first = assert(string.find(source, "-- Reload is an explicit", 1, true))
local last = assert(string.find(source, "-- Archive cleanup", first, true))
local sendFirst = assert(string.find(source, "local function send(action", 1, true))
local sendLast = assert(string.find(source, "\ntable.insert(", sendFirst, true))
local code = string.sub(source, first, last - 1)
	.. string.sub(source, sendFirst, sendLast - 1)
	.. "\n"
	.. [[
return {
	Button = retryProfile, View = retryView, Layout = layoutWelcome, Send = send,
	Render = function(ready) renderRetry(retryView(), ready) end,
	Destroy = function() destroyed = true; for _, item in connections do item:Disconnect() end end,
}
]]
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
		Fire = function(_, ...)
			for _, entry in entries do
				if entry.Active then
					entry.Callback(...)
				end
			end
		end,
	}
end
local function button()
	local b: any = {
		Activated = signal(),
		Selectable = true,
		Position = Roblox.UDim2.new(0, 16, 1, -70),
		Size = Roblox.UDim2.fromOffset(140, 44),
	}
	function b:Clone()
		return button()
	end
	return b
end
local function harness()
	local h: any = {
		Now = 100,
		Calls = {},
		StationCalls = {},
		Attributes = {
			CanRetryProfile = true,
			ProfileRetryAt = 100,
			ProfileRetryRemaining = 3,
			DataStatus = "Busy",
			DataPersistent = false,
		},
	}
	local player = {
		GetAttribute = function(_, key)
			return h.Attributes[key]
		end,
		SetAttribute = function()
			error("Client reload cannot grant consent, admission or profile authority")
		end,
		Character = {
			FindFirstChildOfClass = function()
				return { Health = 100 }
			end,
		},
	}
	h.Welcome = {
		Visible = true,
		Play = button(),
		Explore = button(),
		Eyebrow = {},
		Heading = {},
		Steps = {},
		Detail = {},
	}
	h.Gui = { SelectedObject = nil }
	h.Controller = luau.load(code, {
		environment = {
			welcome = h.Welcome,
			player = player,
			ProfileStatus = ProfileStatus,
			Workspace = {
				GetServerTimeNow = function()
					return h.Now
				end,
			},
			profileRemote = {
				FireServer = function(_, ...)
					table.insert(h.Calls, { ... })
					if h.Throw then
						error("Synthetic transport error")
					end
				end,
			},
			remote = {
				FireServer = function(_, ...)
					table.insert(h.StationCalls, { ... })
				end,
			},
			connections = {},
			GuiService = h.Gui,
			UDim2 = Roblox.UDim2,
			Vector2 = Roblox.Vector2,
			destroyed = false,
			lastRequest = -math.huge,
			waitingChoiceUntil = 0,
			requestedChoice = false,
			closeGuide = function() end,
			os = {
				clock = function()
					return h.Now
				end,
			},
		},
		injectGlobals = true,
	})()
	h.Controller.Render(true)
	return h
end

do
	local h = harness()
	local controller, b = h.Controller, h.Controller.Button
	expect(b.Visible and b.Active and b.Selectable, "Eligible untouched fallback exposes a usable retry")
	expect(
		b.Size.Y.Offset == 44 and h.Welcome.Play.NextSelectionUp == b,
		"Retry has a 44px target and gamepad route"
	)
	h.Gui.SelectedObject = b
	b.Activated:Fire()
	expect(
		#h.Calls == 1 and h.Calls[1][1] == "RetryLoad" and h.Calls[1][2] == "" and #h.Calls[1] == 2,
		"Only the explicit profile reload intent is sent"
	)
	expect(
		not b.Active and not b.Selectable and b.Text == "ЗАГРУЗКА…",
		"Request immediately locks its local button"
	)
	b.Activated:Fire()
	controller.Send("Join")
	controller.Send("Explore")
	expect(
		#h.Calls == 1 and #h.StationCalls == 0,
		"Pending request cannot stack requests or accept temporary play"
	)
	h.Attributes.DataStatus, h.Attributes.CanRetryProfile = "Loading", false
	controller.Render(false)
	h.Now += 20
	controller.Render(false)
	expect(
		b.Visible and b.Text == "ЗАГРУЗКА…",
		"Observed server Loading keeps pending state beyond transport timeout"
	)
	h.Attributes.DataStatus, h.Attributes.CanRetryProfile = "Unavailable", true
	h.Attributes.ProfileRetryRemaining, h.Attributes.ProfileRetryAt = 2, h.Now + 10
	controller.Render(true)
	expect(
		b.Visible and not b.Active and b.Text == "ПОВТОР ЧЕРЕЗ 10 С",
		"Failed load uses the server cooldown and remaining-attempt policy"
	)
	b.Activated:Fire()
	expect(#h.Calls == 1, "Cooldown cannot emit another retry")
	h.Now += 10
	controller.Render(true)
	b.Activated:Fire()
	expect(#h.Calls == 2, "Expiry permits one new deliberate attempt")
	h.Attributes.DataStatus, h.Attributes.CanRetryProfile = "Loading", false
	controller.Render(false)
	h.Attributes.DataStatus, h.Attributes.DataPersistent = "Saved", true
	controller.Render(true)
	expect(not b.Visible and not b.Selectable, "Successful persistence removes retry from the welcome choice")
	controller.Send("Join")
	expect(
		#h.StationCalls == 1 and h.StationCalls[1][2] == false,
		"Ordinary play after load does not grant temporary consent"
	)
	controller.Destroy()
end

do
	local h = harness()
	local b = h.Controller.Button
	b.Activated:Fire()
	h.Now += 3.1
	h.Controller.Render(true)
	expect(b.Active, "Missing server transition releases local pending after a bounded timeout")
	h.Throw = true
	b.Activated:Fire()
	b.Activated:Fire()
	expect(#h.Calls == 2, "Transport exceptions cannot create immediate rapid retry spam")
	h.Attributes.CanRetryProfile = false
	h.Controller.Render(true)
	b.Activated:Fire()
	expect(
		not b.Visible and #h.Calls == 2,
		"Consent, progress or lease loss disabling server eligibility stops retries"
	)
	h.Attributes.CanRetryProfile, h.Attributes.ProfileRetryRemaining = true, 0
	h.Controller.Render(true)
	expect(not b.Visible, "Exhausted retry budget stays hidden")
	for _, malformed in { -1, math.huge, 0 / 0, "soon" } do
		h.Attributes.ProfileRetryRemaining, h.Attributes.ProfileRetryAt = 1, malformed
		h.Controller.Render(true)
		expect(not b.Visible and not b.Active, "Malformed server timing fails closed")
	end
	h.Attributes.ProfileRetryAt, h.Attributes.InRound = 0, true
	h.Now += 1
	b.Activated:Fire()
	expect(#h.Calls == 2, "Admission independently rejects a stale visible activation")
	h.Attributes.InRound, h.Welcome.Visible = false, false
	b.Activated:Fire()
	expect(#h.Calls == 2, "Hidden welcome cannot start a reload")
	h.Controller.Destroy()
	h.Welcome.Visible = true
	b.Activated:Fire()
	expect(#h.Calls == 2, "Destroy disconnects request handler")
end

do
	local h = harness()
	local b = h.Controller.Button
	for _, height in { 234, 260, 284, 320, 600 } do
		h.Controller.Layout(height)
		local panelHeight = h.Welcome.Size.Y.Offset
		local retryTop = panelHeight + b.Position.Y.Offset
		local playTop = panelHeight + h.Welcome.Play.Position.Y.Offset
		expect(
			h.Welcome.Steps.Position.Y.Offset + h.Welcome.Steps.Size.Y.Offset <= retryTop - 8,
			"Warning text stays above the retry row at supported height"
		)
		expect(retryTop + b.Size.Y.Offset <= playTop - 8, "Retry never overlaps Play/Explore")
		expect(not h.Welcome.Detail.Visible, "Secondary detail yields room to the explicit retry warning")
	end
	h.Attributes.CanRetryProfile = false
	h.Controller.Render(true)
	h.Controller.Layout(600)
	expect(h.Welcome.Detail.Visible, "Normal welcome restores its existing detail")
	h.Controller.Destroy()
end

print(string.format("StationRetry: %d checks passed (production request/GUI adapters; no cloud)", checks))
