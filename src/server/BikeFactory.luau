--!strict
-- Builds the bike from the part layout in config/BikeGeometry. Every visible part carries a
-- `PartId` attribute. An invisible `Root` part at the ground contact centre is the model's
-- pivot, so leaning rotates the bike about its tyre contact line like a real bike.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Geometry = require(ReplicatedStorage.Shared.config.BikeGeometry)

local BikeFactory = {}

local function newRoot(): Part
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	return root
end

function BikeFactory.build(groundCFrame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Bike"

	local root = newRoot()
	root.CFrame = groundCFrame
	root.Parent = model
	model.PrimaryPart = root

	-- Rigid align constraints hold the bike exactly where the riding model says. The owning
	-- client updates their targets every frame. Moving the parts directly instead let
	-- stray physics forces accumulate (the bike drifted hundreds of studs at zero speed).
	local anchor = Instance.new("Attachment")
	anchor.Name = "Anchor"
	anchor.Parent = root
	local hold = Instance.new("AlignPosition")
	hold.Name = "Hold"
	hold.Mode = Enum.PositionAlignmentMode.OneAttachment
	hold.Attachment0 = anchor
	hold.RigidityEnabled = true
	hold.Position = groundCFrame.Position
	hold.Parent = root
	local turn = Instance.new("AlignOrientation")
	turn.Name = "Turn"
	turn.Mode = Enum.OrientationAlignmentMode.OneAttachment
	turn.Attachment0 = anchor
	turn.RigidityEnabled = true
	turn.CFrame = groundCFrame.Rotation
	turn.Parent = root

	for _, spec in Geometry.parts do
		local part = Instance.new("Part")
		part.Name = spec.id
		part.Shape = if spec.shape == "Cylinder"
			then Enum.PartType.Cylinder
			else Enum.PartType.Block
		part.Size = spec.size
		part.Color = spec.color
		part.Material = spec.material
		-- The riding model, not physics collisions, places the bike. Collisions on the
		-- bike would fight it every frame.
		part.CanCollide = false
		part.Massless = true
		part.CFrame = groundCFrame * CFrame.new(spec.position)
		part:SetAttribute("PartId", spec.id)
		part:SetAttribute("Health", 100)
		part.Parent = model

		if spec.motor then
			local motor = Instance.new("Motor6D")
			motor.Name = spec.id .. "_motor"
			motor.Part0 = root
			motor.Part1 = part
			motor.C0 = CFrame.new(spec.position)
			motor.Parent = root
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local seat = Instance.new("Seat")
	seat.Name = "BikeSeat"
	seat.Size = Geometry.seat.size
	seat.Color = Color3.fromRGB(25, 25, 25)
	seat.Material = Enum.Material.Fabric
	seat.CanCollide = false
	seat.CFrame = groundCFrame * CFrame.new(Geometry.seat.position)
	seat:SetAttribute("PartId", "seat")
	seat:SetAttribute("Health", 100)
	seat.Parent = model
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = root
	seatWeld.Part1 = seat
	seatWeld.Parent = seat

	return model
end

return BikeFactory
