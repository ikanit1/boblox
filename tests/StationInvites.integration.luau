--!strict
-- Executes the production invite block with local async adapters, not SocialService or native UI.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local checks = 0
local scenarios = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end

local source = fs.readFile("src/client/Station.client.luau")
local stateStart = assert(string.find(source, "local canInvite =", 1, true))
local stateEnd = assert(string.find(source, "local waitingChoiceUntil", stateStart, true))
local blockStart = assert(string.find(source, "-- Invites are optional:", 1, true))
local blockEnd = assert(string.find(source, "refreshInvite(true)", blockStart, true))
	+ #"refreshInvite(true)"
	- 1
local production = string.sub(source, stateStart, stateEnd - 1)
	.. "\n"
	.. string.sub(source, blockStart, blockEnd)
	.. [[
return {
	Refresh = refreshInvite,
	Destroy = function() destroyed = true end,
	State = function() return canInvite, invitePromptOpen, inviteCheckPending end,
}
]]

local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			table.insert(listeners, callback)
			return { Disconnect = function() end }
		end,
		Fire = function(_, ...)
			for _, callback in listeners do
				callback(...)
			end
		end,
	}
end

local function harness(slowCheck: boolean?)
	scenarios += 1
	local h: any = {
		Now = 0,
		Checks = 0,
		Prompts = 0,
		Destroyed = false,
		Allowed = true,
		FailPrompt = false,
		Tasks = {},
		Timeouts = {},
		Attributes = {},
		Player = {},
		Invite = { Visible = true, Activated = signal() },
		Bar = { Visible = true },
		Closed = signal(),
	}
	local social = {
		GameInvitePromptClosed = h.Closed,
		CanSendGameInviteAsync = function()
			h.Checks += 1
			if slowCheck then
				coroutine.yield()
			end
			return h.Allowed
		end,
		PromptGameInvite = function()
			h.Prompts += 1
			if h.FailPrompt then
				error("Simulated unavailable invite service")
			end
		end,
	}
	h.Controller = luau.load(production, {
		debugName = "Station.invites.production",
		environment = {
			player = h.Player,
			invite = h.Invite,
			bar = h.Bar,
			gui = {
				SetAttribute = function(_, name, value)
					assert(not h.Destroyed, "A delayed check tried to write to a destroyed GUI")
					h.Attributes[name] = value
				end,
			},
			connections = {},
			lastRequest = -math.huge,
			SocialService = social,
			os = {
				clock = function()
					return h.Now
				end,
			},
			task = {
				spawn = function(callback)
					local thread = coroutine.create(callback)
					table.insert(h.Tasks, thread)
					local ok, message = coroutine.resume(thread)
					assert(ok, message)
				end,
				delay = function(_, callback)
					table.insert(h.Timeouts, callback)
				end,
			},
		},
		injectGlobals = true,
	})()
	return h
end

do
	local h = harness()
	expect(
		h.Checks == 1 and h.Attributes.InviteAvailable == true,
		"Availability check enables optional invites"
	)
	h.Invite.Activated:Fire()
	expect(h.Prompts == 1, "Visible available invite opens one prompt")
	h.Now = 1
	h.Invite.Activated:Fire()
	expect(h.Prompts == 1, "Repeated activation cannot stack open prompts")
	h.Closed:Fire(h.Player)
	h.Invite.Activated:Fire()
	expect(h.Prompts == 2, "Closing a prompt allows another explicit activation")
	h.Timeouts[1]()
	h.Now = 2
	h.Invite.Activated:Fire()
	expect(h.Prompts == 2, "An old timeout cannot unlock a newer open prompt")
	h.Timeouts[2]()
	h.Invite.Activated:Fire()
	expect(h.Prompts == 3, "The current prompt timeout provides the intended fallback")
end

do
	local h = harness(true)
	h.Now = 31
	h.Controller.Refresh(false)
	expect(h.Checks == 1, "A slow availability request cannot accumulate additional requests")
	h.Destroyed = true
	h.Controller.Destroy()
	local ok, message = coroutine.resume(h.Tasks[1])
	expect(ok, "A completed availability request ignores destroyed GUI: " .. tostring(message))
	expect(h.Attributes.InviteAvailable == nil, "No stale availability is published after destruction")
	h.Controller.Refresh(true)
	expect(h.Checks == 1, "Destroyed controller never starts another check")
end

do
	local h = harness()
	h.Invite.Visible = false
	h.Invite.Activated:Fire()
	expect(h.Prompts == 0, "Hidden invite cannot open a prompt")
	h.Invite.Visible = true
	h.Bar.Visible = false
	h.Invite.Activated:Fire()
	expect(h.Prompts == 0, "Leaving the lobby prevents prompt activation")
	h.Bar.Visible = true
	h.FailPrompt = true
	h.Invite.Activated:Fire()
	local available, open = h.Controller.State()
	expect(
		not available and not open and h.Attributes.InviteAvailable == false,
		"Prompt failures close and hide invites"
	)
	h.Now = 1
	h.Invite.Activated:Fire()
	expect(h.Prompts == 1, "Unavailable invites remain inert")
end

print("StationInvites integration: " .. checks .. " checks passed in " .. scenarios .. " scenarios")
