--!strict
-- A local, static appearance sample. No character, profile, remote, physics or asset requests.
-- Viewport geometry approximates the ribbon because engine Trail effects are not used here.
local CollectionPreview = {}

local ROW_HEIGHT = 160
local PREVIEW_HEIGHT = 280
local ACTION_Y = 108
local PREVIEW_ACTION_Y = 228

type Trail = {
	Id: string,
	Name: string,
	Color: Color3,
	ColorEnd: Color3?,
	WidthScale: number?,
	Lifetime: number?,
}

function CollectionPreview.new()
	local activeRow: Frame? = nil
	local activeId: string? = nil
	local objects: { Instance } = {}
	local destroyed = false

	local function layout(row: Frame, expanded: boolean)
		row.Size = UDim2.new(1, -8, 0, if expanded then PREVIEW_HEIGHT else ROW_HEIGHT)
		local action = row:FindFirstChild("Action") :: TextButton?
		local preview = row:FindFirstChild("Preview") :: TextButton?
		local y = if expanded then PREVIEW_ACTION_Y else ACTION_Y
		if action then
			action.Position = UDim2.new(0.5, 4, 0, y)
		end
		if preview then
			preview.Position = UDim2.fromOffset(12, y)
			preview.Text = if expanded then "СКРЫТЬ" else "ПРИМЕРИТЬ"
		end
	end

	local function clear()
		for _, object in objects do
			object:Destroy()
		end
		table.clear(objects)
		if activeRow and activeRow.Parent then
			layout(activeRow, false)
		end
		activeRow = nil
		activeId = nil
	end

	local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
		local object = Instance.new("Part")
		object.Name = name
		object.Size = size
		object.Position = position
		object.Anchored = true
		object.CanCollide = false
		object.CanTouch = false
		object.CanQuery = false
		object.Material = Enum.Material.SmoothPlastic
		object.Color = color
		object.Parent = parent
		return object
	end

	return {
		Toggle = function(row: Frame, trail: Trail): boolean
			if destroyed or not row.Parent then
				return false
			end
			if activeRow == row and activeId == trail.Id then
				clear()
				return false
			end
			clear()
			activeRow = row
			activeId = trail.Id
			layout(row, true)

			local viewport = Instance.new("ViewportFrame")
			viewport.Name = "AppearancePreview"
			viewport.Size = UDim2.new(1, -24, 0, 90)
			viewport.Position = UDim2.fromOffset(12, 105)
			viewport.BackgroundColor3 = Color3.fromRGB(14, 24, 39)
			viewport.BorderSizePixel = 0
			viewport.Ambient = Color3.fromRGB(185, 195, 210)
			viewport.LightColor = Color3.fromRGB(255, 255, 255)
			viewport.LightDirection = Vector3.new(-1, -1, -1)
			viewport.Active = false
			viewport.Selectable = false
			viewport.Parent = row
			table.insert(objects, viewport)
			local camera = Instance.new("Camera")
			camera.Name = "PreviewCamera"
			camera.FieldOfView = 42
			camera.CFrame = CFrame.lookAt(Vector3.new(4, 5, 14), Vector3.new(-2, 1, 0))
			camera.Parent = viewport
			viewport.CurrentCamera = camera
			local model = Instance.new("Model")
			model.Name = "AppearanceSample"
			model.Parent = viewport
			local neutral = Color3.fromRGB(190, 204, 224)
			part(model, "Body", Vector3.new(1.35, 1.5, 0.75), Vector3.new(1, 1.7, 0), neutral)
			local head = part(model, "Head", Vector3.one * 0.85, Vector3.new(1, 2.95, 0), neutral)
			head.Shape = Enum.PartType.Ball
			for _, side in { -1, 1 } do
				part(
					model,
					"Arm",
					Vector3.new(0.45, 1.5, 0.55),
					Vector3.new(1 + side * 0.97, 1.7, 0),
					neutral
				)
				part(
					model,
					"Leg",
					Vector3.new(0.55, 1.35, 0.65),
					Vector3.new(1 + side * 0.37, 0.3, 0),
					neutral
				)
			end
			if trail.Id ~= "None" then
				local lengthScale = (trail.Lifetime or 0.28) / 0.28
				local widthScale = (trail.WidthScale or 0.65) / 0.65
				for index = 1, 12 do
					local t = (index - 1) / 12
					local ribbon = part(
						model,
						"Ribbon_" .. index,
						Vector3.new(0.43 * lengthScale, 0.035, 0.715 * widthScale * (1 - t)),
						Vector3.new(0.1 - index * 0.4 * lengthScale, 0.45 + math.sin(t * math.pi) * 0.3, 0.3),
						trail.Color:Lerp(trail.ColorEnd or trail.Color, t)
					)
					ribbon.Transparency = 0.24 + 0.76 * t
				end
			end
			local caption = (row:FindFirstChild("Detail") :: TextLabel):Clone()
			caption.Name = "PreviewCaption"
			caption.Position = UDim2.fromOffset(12, 198)
			caption.Size = UDim2.new(1, -24, 0, 24)
			caption.Text = "ПРИМЕРКА НА МАНЕКЕНЕ · БЕЗ ПОКУПКИ"
			caption.TextColor3 = Color3.fromRGB(255, 213, 79)
			caption.Parent = row
			table.insert(objects, caption)
			return true
		end,
		Clear = clear,
		CurrentId = function(): string?
			return activeId
		end,
		Destroy = function()
			clear()
			destroyed = true
		end,
	}
end

return CollectionPreview
