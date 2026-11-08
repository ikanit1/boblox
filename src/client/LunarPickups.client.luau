--!strict
-- Personal lunar visibility only. The server owns admission, collection and rewards.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("RuleRoomState")
local arena = Workspace:WaitForChild("Arena")
local connections: { RBXScriptConnection } = {}
local watched: { [BasePart]: { RBXScriptConnection } } = {}

local function integer(value: any, maximum: number): number?
	return if typeof(value) == "number"
			and value >= 0
			and value <= maximum
			and value % 1 == 0
		then value
		else nil
end

local function show(part: BasePart, visible: boolean)
	part.LocalTransparencyModifier = if visible then 0 else 1
	local label = part:FindFirstChild("PickupLabel")
	if label and label:IsA("BillboardGui") then
		label.Enabled = visible
	end
end

local function refresh(part: BasePart)
	local index = integer(part:GetAttribute("LunarStarIndex"), 9)
	if not index or index == 0 then
		return
	end
	local mask = integer(player:GetAttribute("LunarStarMask"), 511)
	local count = integer(player:GetAttribute("LunarStarCount"), 3)
	local goal = player:GetAttribute("LunarStarGoal")
	local active = state:GetAttribute("Phase") == "Rule"
		and state:GetAttribute("RuleId") == "LowGravity"
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("MovementWarning") ~= true
	show(
		part,
		active
			and goal == 3
			and count ~= nil
			and count < goal
			and mask ~= nil
			and bit32.band(mask, bit32.lshift(1, index - 1)) == 0
	)
end

local function refreshAll()
	for part in watched do
		refresh(part)
	end
end

local function unwatch(part: BasePart)
	local listeners = watched[part]
	if not listeners then
		return
	end
	watched[part] = nil
	for _, connection in listeners do
		connection:Disconnect()
	end
end

local function watch(instance: Instance)
	local parent = instance.Parent
	if
		not instance:IsA("BasePart")
		or not string.match(instance.Name, "^Star%d+$")
		or not parent
		or parent.Name ~= "RuleEffects"
		or parent.Parent ~= arena
		or watched[instance]
	then
		return
	end
	local part = instance :: BasePart
	-- Parts can replicate before their index and label. Observe both arrivals instead
	-- of assuming DescendantAdded implies that all server metadata is available.
	watched[part] = {
		part:GetAttributeChangedSignal("LunarStarIndex"):Connect(function()
			refresh(part)
		end),
		part.ChildAdded:Connect(function()
			refresh(part)
		end),
		part.AncestryChanged:Connect(function()
			if not part:IsDescendantOf(arena) then
				unwatch(part)
			end
		end),
	}
	refresh(part)
end

for _, name in { "LunarStarMask", "LunarStarCount", "LunarStarGoal", "InRound", "MovementWarning" } do
	table.insert(connections, player:GetAttributeChangedSignal(name):Connect(refreshAll))
end
for _, name in { "Phase", "RuleId" } do
	table.insert(connections, state:GetAttributeChangedSignal(name):Connect(refreshAll))
end
table.insert(connections, arena.DescendantAdded:Connect(watch))
for _, instance in arena:GetDescendants() do
	watch(instance)
end
table.insert(
	connections,
	script.Destroying:Connect(function()
		for part in watched do
			if part:GetAttribute("LunarStarIndex") ~= nil then
				show(part, true)
			end
			unwatch(part)
		end
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
)
