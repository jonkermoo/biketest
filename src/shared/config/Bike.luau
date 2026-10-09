--!strict
-- Every tweakable number for the bike lives here. Balance by editing data, not code.
-- Units in the game: studs, seconds, radians. One stud is 0.28 m. Real-world values are kept
-- in SI below and converted once, so each number can be checked against its source.
local STUD_M = 0.28
local PER_M = 1 / STUD_M -- studs per metre
local G = 9.81 -- m/s^2

-- Longitudinal model: Yamaha YZF-R6, fitted to MOTORRAD's instrumented Top-Test of the 2005
-- model (motorradonline.de, "Top-Test Yamaha YZF-R6 - Spurensuche"): top speed 265 km/h,
-- 0-100 km/h 3.2 s, 0-140 4.9 s, 0-200 9.6 s, braking 100-0 km/h in 38.5 m (mean 10.0 m/s^2,
-- limited by the rear wheel lifting), 188 kg fuelled, 1385 mm wheelbase. The fit reproduces
-- 3.20 s / 4.90 s / 9.53 s, 264.9 km/h and 38.5 m; tests/run.luau checks this.
return table.freeze({
	-- Speed and acceleration
	maxSpeed = 300 / 3.6 * PER_M, -- safety cap only; real top speed comes from drag (265 km/h)
	launchAccel = 9.0 * PER_M, -- 0.92 g: where the front wheel lifts at full throttle
	powerPerMass = 245 * PER_M * PER_M, -- W/kg at the wheel, bike plus rider (fitted)
	rollingResistance = 0.015 * G * PER_M, -- standard value for motorcycle tyres
	-- ESTIMATE, no measured source: deceleration from a fully closed throttle in gear
	engineBraking = 1.0 * PER_M,
	aeroDrag = 0.000587 * STUD_M, -- per stud; fitted so full throttle tops out at 265 km/h

	-- Brakes: full lever. Together with engine braking, rolling and air drag this stops the
	-- bike from 100 km/h in 38.5 m, as measured. Real sportbikes are limited here by the rear
	-- wheel lifting (about 1 g), not by tyre grip.
	brakeDecel = 8.652 * PER_M,

	-- Steering and lean
	maxCurvature = 0.12, -- 1/studs at a standstill (tightest turn, radius ~8 studs)
	curvatureSpeedRef = 25, -- speed at which the tightest available turn has halved
	leanRate = 5, -- how quickly lean follows the demanded lean (1/s)
	gravity = G * PER_M,

	-- Grip. `tyreGrip` is the friction coefficient: lateral plus braking force
	-- must stay below it or the tyres let go. Worn tyres will lower this later.
	tyreGrip = 1.1,
	steerAssist = 0.85, -- full-lock key press uses at most this share of the grip budget
	-- A look target may ask for up to this many times the tyre grip. Above 1 means looking too
	-- sharply can really drop the bike; this is a realism dial.
	lookGripLimit = 1.4,

	-- Falling over
	slideDecel = 22, -- studs/s^2 slowdown while sliding on the road
	lyingLean = 1.45, -- how far over the bike lies when fallen (rad)

	-- Respawn
	respawnCooldown = 2,
})
