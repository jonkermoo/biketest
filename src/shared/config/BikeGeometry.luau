--!strict
-- Placeholder bike layout, in studs (1 stud = 0.28 m), modelled on a road sport bike.
-- Origin is the ground point midway between the tyre contact patches. -Z is forward,
-- +Y is up, X is the wheel axle direction. Every part has an id so real Blender meshes can
-- replace placeholders one at a time and the damage model can address parts by id.
export type PartSpec = {
	id: string,
	shape: "Block" | "Cylinder",
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	motor: boolean?, -- moved by a Motor6D (wheels spin, fork steers later)
}

local wheelRadius = 1.125 -- 0.63 m tyre, matches the Blender 180/55 R17 tyre
local halfWheelbase = 2.5 -- 1.4 m wheelbase

return table.freeze({
	wheelRadius = wheelRadius,
	halfWheelbase = halfWheelbase,
	parts = {
		{
			id = "rear_wheel",
			shape = "Cylinder",
			size = Vector3.new(0.64, wheelRadius * 2, wheelRadius * 2),
			position = Vector3.new(0, wheelRadius, halfWheelbase),
			color = Color3.fromRGB(20, 20, 22),
			material = Enum.Material.Rubber,
			motor = true,
		},
		{
			id = "front_wheel",
			shape = "Cylinder",
			size = Vector3.new(0.43, wheelRadius * 2, wheelRadius * 2),
			position = Vector3.new(0, wheelRadius, -halfWheelbase),
			color = Color3.fromRGB(20, 20, 22),
			material = Enum.Material.Rubber,
			motor = true,
		},
		{
			id = "frame",
			shape = "Block",
			size = Vector3.new(0.9, 1.3, 3.6),
			position = Vector3.new(0, 2.0, 0),
			color = Color3.fromRGB(60, 60, 66),
			material = Enum.Material.Metal,
		},
		{
			id = "engine",
			shape = "Block",
			size = Vector3.new(1.1, 1.2, 1.5),
			position = Vector3.new(0, 1.45, -0.2),
			color = Color3.fromRGB(45, 45, 48),
			material = Enum.Material.DiamondPlate,
		},
		{
			id = "front_fork",
			shape = "Block",
			size = Vector3.new(0.7, 2.4, 0.3),
			position = Vector3.new(0, 2.1, -2.2),
			color = Color3.fromRGB(170, 170, 175),
			material = Enum.Material.Metal,
		},
		{
			id = "fuel_tank",
			shape = "Block",
			size = Vector3.new(1.1, 0.7, 1.4),
			position = Vector3.new(0, 2.95, -0.7),
			color = Color3.fromRGB(150, 25, 25),
			material = Enum.Material.SmoothPlastic,
		},
		{
			id = "fairing",
			shape = "Block",
			size = Vector3.new(1.3, 1.3, 1.0),
			position = Vector3.new(0, 2.8, -2.0),
			color = Color3.fromRGB(150, 25, 25),
			material = Enum.Material.SmoothPlastic,
		},
		{
			id = "handlebars",
			shape = "Block",
			size = Vector3.new(2.2, 0.15, 0.15),
			position = Vector3.new(0, 3.35, -1.55),
			color = Color3.fromRGB(30, 30, 30),
			material = Enum.Material.Metal,
		},
	} :: { PartSpec },
	seat = {
		size = Vector3.new(1.0, 0.3, 1.4),
		position = Vector3.new(0, 3.0, 0.75),
	},
})
