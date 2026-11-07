--!strict
-- Production Station.server handlers with local adapters; not a native-client playtest.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local ProfileStatus = require("../src/shared/ProfileStatus")
local PracticeMath = require("../src/shared/PracticeMath")
local Vector3, CFrame = Roblox.Vector3, Roblox.CFrame
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local entry = { active = true, callback = callback }
			table.insert(callbacks, entry)
			return {
				Disconnect = function()
					entry.active = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, entry in callbacks do
				if entry.active then
					entry.callback(...)
				end
			end
		end,
	}
end
local function object(children: any?)
	local result: any = children or {}
	local attributes = {}
	function result:WaitForChild(name)
		return assert(self[name], name)
	end
	function result:FindFirstChild(name)
		return self[name]
	end
	function result:GetAttribute(name)
		return attributes[name]
	end
	function result:SetAttribute(name, value)
		attributes[name] = value
	end
	return result
end

local clock = 0
local players = object({ PlayerAdded = signal(), PlayerRemoving = signal(), list = {} })
function players:GetPlayers()
	return table.clone(self.list)
end
local heartbeat, promptSignal, destroying = signal(), signal(), signal()
local remote = object({ OnServerEvent = signal() })
local course = object({ StartPad = { Position = Vector3.new(-50, 2, 70) } })
for index = 1, 7 do
	course["Checkpoint" .. index] = { Position = Vector3.new(-50, 2, 70 + index * 5) }
end
local lobby = object({ Practice = course })
local arena = object({ Lobby = lobby, LobbySpawn = { Position = Vector3.new(0, 2, 80) } })
local workspace = object({ Arena = arena })
function workspace:GetServerTimeNow()
	return clock
end
local replicated = object({
	RuleRoomShared = object({ PracticeMath = PracticeMath, ProfileStatus = ProfileStatus }),
	RuleRoomRemotes = object({ StationAction = remote }),
})
local services = {
	Players = players,
	ReplicatedStorage = replicated,
	Workspace = workspace,
	ProximityPromptService = { PromptTriggered = promptSignal },
	RunService = { Heartbeat = heartbeat },
}
luau.load(fs.readFile("src/server/Station.server.luau"), {
	debugName = "PRODUCTION_Station",
	environment = {
		game = {
			GetService = function(_, name)
				return assert(services[name], name)
			end,
		},
		script = { Destroying = destroying },
		require = function(module)
			return module
		end,
		Vector3 = Vector3,
		Vector2 = Roblox.Vector2,
		CFrame = CFrame,
		Enum = { HumanoidRigType = { R6 = "R6" } },
		os = {
			clock = function()
				return clock
			end,
		},
	},
})()

local function addPlayer(name: string)
	local root = object({
		Position = Vector3.new(0, 4, 80),
		Size = Vector3.new(2, 2, 1),
		AssemblyLinearVelocity = Vector3.zero,
		AssemblyAngularVelocity = Vector3.zero,
	})
	function root:IsA(class)
		return class == "BasePart"
	end
	local humanoid = { Health = 100, RigType = "R15", HipHeight = 2 }
	local character = object({ HumanoidRootPart = root, Teleports = 0 })
	function character:FindFirstChildOfClass(class)
		return if class == "Humanoid" then humanoid else nil
	end
	function character:PivotTo(cf)
		self.Teleports += 1
		root.Position = cf.Position
	end
	local player = object({ Character = character, DisplayName = name })
	player:SetAttribute("InRound", false)
	player:SetAttribute("DataStatus", "Loading")
	player:SetAttribute("DataPersistent", false)
	player:SetAttribute("TemporaryPlayAccepted", false)
	table.insert(players.list, player)
	players.PlayerAdded:Fire(player)
	return player, root, character
end
local function send(player, action, consent, advance: number?)
	clock += advance or 0.5
	remote.OnServerEvent:Fire(player, action, consent)
end

local player, root, character = addPlayer("Temporary")
expect(
	player:GetAttribute("LobbyOnly") and player:GetAttribute("EntryChoiceMade") == false,
	"Newcomer is not queued"
)
send(player, "Join", true)
expect(player:GetAttribute("LobbyOnly") == true, "Consent cannot bypass profile loading")
player:SetAttribute("DataStatus", "Session")
send(player, "Join", nil)
expect(
	player:GetAttribute("LobbyOnly") == true and player:GetAttribute("TemporaryPlayPrompt") == true,
	"Direct Join opens temporary choice instead of admitting"
)
for _, invalid in { "true", 1, {}, function() end } do
	send(player, "Join", invalid)
	expect(player:GetAttribute("TemporaryPlayAccepted") == false, "Malformed consent is rejected")
end
send(player, "Join", true)
expect(
	player:GetAttribute("LobbyOnly") == false and player:GetAttribute("TemporaryPlayAccepted") == true,
	"Explicit temporary choice admits through production handler"
)
expect(
	player:GetAttribute("EntryChoiceMade") == true and player:GetAttribute("TemporaryPlayPrompt") == false,
	"Successful choice closes the prompt"
)
send(player, "Explore", nil)
send(player, "Join", nil)
expect(player:GetAttribute("LobbyOnly") == false, "Accepted temporary session can rejoin normally")

player:SetAttribute("InRound", true)
player:SetAttribute("DataStatus", "Unavailable")
player:SetAttribute("TemporaryPlayAccepted", false)
root.Position = Vector3.new(0, 4, 0)
local before = character.Teleports
clock += 0.11
heartbeat:Fire(0.11)
expect(
	character.Teleports == before and player:GetAttribute("TemporaryPlayPrompt") == false,
	"Lease loss never interrupts the active trial with a teleport/prompt"
)
player:SetAttribute("InRound", false)
clock += 0.11
heartbeat:Fire(0.11)
expect(
	player:GetAttribute("LobbyOnly") == true and player:GetAttribute("TemporaryPlayPrompt") == true,
	"Safe boundary removes unconsented fallback from queue"
)
expect(
	character.Teleports == before + 1 and root.Position.Z > 43,
	"Retained arena survivor returns to a usable lobby choice"
)
send(player, "Explore", nil)
expect(
	player:GetAttribute("LobbyOnly") == true and player:GetAttribute("TemporaryPlayPrompt") == false,
	"Explore dismisses warning without granting temporary admission"
)

local newcomer, newRoot = addPlayer("Busy")
newcomer:SetAttribute("DataStatus", "Busy")
local joinPart = object({ Position = newRoot.Position })
function joinPart:IsA(class)
	return class == "BasePart"
end
function joinPart:IsDescendantOf(parent)
	return parent == lobby
end
joinPart:SetAttribute("StationAction", "Join")
clock += 0.5
promptSignal:Fire({ Parent = joinPart, Enabled = true }, newcomer)
expect(
	newcomer:GetAttribute("LobbyOnly") == true and newcomer:GetAttribute("TemporaryPlayAccepted") == false,
	"Proximity Join cannot accept temporary mode"
)
send(newcomer, "Join", true, 0.05)
expect(newcomer:GetAttribute("LobbyOnly") == true, "Consent still obeys request cooldown")
newRoot.Position = Vector3.new(1000, 4, 80)
send(newcomer, "Join", true)
expect(newcomer:GetAttribute("LobbyOnly") == true, "Consent cannot bypass station bounds")
newRoot.Position = Vector3.new(0, 4, 80)
newcomer:SetAttribute("DataStatus", "Saved")
newcomer:SetAttribute("DataPersistent", true)
send(newcomer, "Join", nil)
expect(newcomer:GetAttribute("LobbyOnly") == false, "Saved profile joins without temporary consent")
destroying:Fire()
send(newcomer, "Explore", nil)
expect(newcomer:GetAttribute("LobbyOnly") == false, "Destroyed script disconnects admission handlers")
print(
	"Station admission integration: "
		.. checks
		.. " checks passed (production handlers, local adapters; no Studio)"
)
