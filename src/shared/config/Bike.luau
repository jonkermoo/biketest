--!strict
-- Every tweakable number for the bike lives here. Balance by editing data, not code.
-- Units: studs, seconds, radians. One stud is taken as 0.28 m, so 100 studs/s is about 100 km/h.
return table.freeze({
	-- Longitudinal
	maxSpeed = 120, -- studs/s
	acceleration = 28, -- studs/s^2 at full throttle (about 0 to 100 km/h in 3.5 s)
	brakeDecel = 36, -- studs/s^2 at full brake (just over 1 g on sport tyres)
	drag = 4, -- passive slowdown with no throttle

	-- Steering and lean
	maxCurvature = 0.12, -- 1/studs at a standstill (tightest turn, radius ~8 studs)
	curvatureSpeedRef = 25, -- speed at which the tightest available turn has halved
	leanRate = 5, -- how quickly lean follows the demanded lean (1/s)
	gravity = 35, -- studs/s^2 (9.81 m/s^2 at 0.28 m per stud)

	-- Grip. `tyreGrip` is the friction coefficient: lateral plus braking force
	-- must stay below it or the tyres let go. Worn tyres will lower this later.
	tyreGrip = 1.1,
	steerAssist = 0.85, -- full-lock key press uses at most this share of the grip budget

	-- Falling over
	slideDecel = 22, -- studs/s^2 slowdown while sliding on the road
	lyingLean = 1.45, -- how far over the bike lies when fallen (rad)

	-- Respawn
	respawnCooldown = 2,
})
