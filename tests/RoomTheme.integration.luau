--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Themes = require("../src/shared/RoomThemes")
local Display = require("../src/shared/RoomDisplay")
local checks = 0
local function expect(value: boolean, message: string)
	assert(value, message)
	checks += 1
end
local function signal()
	local callbacks = {}
	local event = {}
	function event:Connect(callback)
		local connection = { Connected = true }
		function connection.Disconnect(link)
			link.Connected = false
		end
		table.insert(callbacks, { connection, callback })
		return connection
	end
	function event:Fire()
		for _, pair in callbacks do
			if pair[1].Connected then
				pair[2]()
			end
		end
	end
	function event:Count()
		local count = 0
		for _, pair in callbacks do
			count += if pair[1].Connected then 1 else 0
		end
		return count
	end
	return event
end
local function node(className, children, attributes)
	local object: any = { Parent = true }
	function object:IsA(class)
		return class == className
	end
	function object:FindFirstChild(name)
		return children and children[name]
	end
	object.WaitForChild = object.FindFirstChild
	function object:GetAttribute(name)
		return attributes and attributes[name]
	end
	return object
end
local values = { Phase = "Waiting", Round = 1 }
local state = node("Folder", nil, values)
state.AttributeChanged = signal()
local heading, detail = node("TextLabel"), node("TextLabel")
local board = node("Part", { Display = node("SurfaceGui", { Heading = heading, Detail = detail }) })
local reactor = node("Folder", { StatusBoard = board })
local panel = node("BasePart", nil, { ThemeRole = "Panel" })
local orbit = node("BasePart", nil, { ThemeRole = "Orbit" })
local unknown = node("BasePart", nil, { ThemeRole = "Tile" })
panel.CanCollide, orbit.CanCollide, unknown.Color = false, false, "GAMEPLAY_COLOR"
local atmosphere = node("Folder")
function atmosphere:GetDescendants()
	return { panel, orbit, unknown }
end
local arena = node("Model", { Atmosphere = atmosphere, Lobby = node("Folder", { ReactorExhibit = reactor }) })
local shared = node("Folder", { RoomDisplay = Display, RoomThemes = Themes })
local storage: any = node("ReplicatedStorage", { RuleRoomState = state, RuleRoomShared = shared })
storage.RuleRoomShared = shared
local destroyed = signal()
local pending = {}
luau.load(fs.readFile("src/client/RoomDisplay.client.luau"), {
	debugName = "PRODUCTION_RoomDisplay_Theme",
	environment = {
		game = {
			GetService = function(_, name)
				assert(name == "ReplicatedStorage", "Presentation requests only its replicated state")
				return storage
			end,
		},
		workspace = node("Workspace", { Arena = arena }),
		script = { Destroying = destroyed },
		require = function(module)
			return module
		end,
		Color3 = roblox.Color3,
		task = {
			defer = function(callback)
				table.insert(pending, callback)
			end,
		},
	},
})()
local function drain()
	local work = pending
	pending = {}
	for _, callback in work do
		callback()
	end
end
expect(
	panel.Color == roblox.Color3.fromRGB(36, 53, 73) and orbit.Transparency == 1,
	"First render matches authored laboratory"
)
expect(
	unknown.Color == "GAMEPLAY_COLOR" and not panel.CanCollide,
	"Theme does not touch gameplay roles or collision"
)
values.Round = 2
state.AttributeChanged:Fire()
state.AttributeChanged:Fire()
expect(#pending == 1, "Replicated attributes coalesce to one render")
drain()
expect(
	orbit.Transparency == 0.15 and panel.Color == roblox.Color3.fromRGB(25, 31, 54),
	"Second run displays orbital variant"
)
values.Phase, values.RuleIndex = "Rule", 1
state.AttributeChanged:Fire()
drain()
expect(
	orbit.Transparency == 0.15 and unknown.Color == "GAMEPLAY_COLOR",
	"Changing hazards preserves theme and original gameplay palette"
)
values.Round = 3
state.AttributeChanged:Fire()
destroyed:Fire()
drain()
expect(state.AttributeChanged:Count() == 0, "Destruction disconnects the state subscription")
expect(orbit.Transparency == 0.15, "Deferred render cannot mutate the scene after destruction")
print(
	"RoomTheme integration: " .. checks .. " checks passed (production renderer adapters, not native visuals)"
)
