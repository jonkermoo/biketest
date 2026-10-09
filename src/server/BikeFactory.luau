--!strict
-- Builds a placeholder bike: one body part plus a seat. Replace with a real model later.
local BikeFactory = {}

function BikeFactory.build(spawnCFrame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Bike"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2, 6)
	body.Material = Enum.Material.Metal
	body.Color = Color3.fromRGB(35, 35, 40)
	body.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.02, 0, 1, 1)
	body.CFrame = spawnCFrame
	body.Parent = model
	model.PrimaryPart = body

	local seat = Instance.new("Seat")
	seat.Name = "BikeSeat"
	seat.Size = Vector3.new(1.5, 0.4, 1.5)
	seat.Transparency = 0.6
	seat.CFrame = spawnCFrame * CFrame.new(0, 1.2, 0.5)
	seat.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = seat
	weld.Parent = body

	return model
end

return BikeFactory
