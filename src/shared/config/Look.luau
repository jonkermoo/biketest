--!strict
-- First-person camera, screen cursor dot, world marker and look-steering settings.
-- Studs and radians; colours are 0..255.
return table.freeze({
	-- Camera: the rider's head, relative to the bike's ground pivot (-Z forward)
	headOffset = Vector3.new(0, 4.9, 0.55),
	fieldOfView = 80,
	-- How much of the bike's lean the head follows (real riders keep their head nearer level)
	cameraLeanFollow = 0.45,

	-- Screen cursor: a faint dot that shows where the mouse is. It does not move the camera.
	cursorSize = 7, -- pixels
	cursorTransparency = 0.55,

	-- World marker: placed where the look ray hits the world
	markerDiameter = 1.6,
	markerColor = Color3.fromRGB(255, 140, 30),
	markerTransparency = 0.15,
	maxLookDistance = 600,
	-- If the look ray hits nothing (sky), steer toward this far point along the ray
	skyLookDistance = 250,

	-- Look target closer than this ahead is pushed out, so tiny mouse moves near the front
	-- wheel do not demand violent turns
	minLookAhead = 12,

	-- Target fixation: off by default (0). 1 = very sticky on hazards. Hazards are parts
	-- tagged "Hazard" with CollectionService.
	fixationStrength = 0,
	hazardTag = "Hazard",
})
