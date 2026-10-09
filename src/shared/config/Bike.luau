--!strict
-- Every tweakable number for the bike lives here. Balance by editing data, not code.
-- Units in the game: studs, seconds, radians. One stud is 0.28 m. Real-world values are kept
-- in SI below and converted once, so each number can be checked against its source.
local STUD_M = 0.28
local PER_M = 1 / STUD_M -- studs per metre
local G = 9.81 -- m/s^2

-- Yamaha YZF-R6, 2005. Fitted to MOTORRAD's instrumented Top-Test (motorradonline.de,
-- "Top-Test Yamaha YZF-R6 - Spurensuche"): top speed 265 km/h, 0-100 km/h 3.2 s, 0-140 4.9 s,
-- 0-200 9.6 s, braking 100-0 km/h in 38.5 m (mean 10.0 m/s^2, limited by the rear wheel
-- lifting), 188 kg fuelled. Shifting at the redline, the fit reproduces 3.20 / 4.95 / 9.54 s,
-- 265 km/h and 38.5 m; tests/run.luau checks this.
return table.freeze({
	-- Gearbox (2005-era R6 spec listing: totalmotorcycle.com model history)
	gearRatios = { 2.846, 1.947, 1.560, 1.333, 1.190, 1.083 },
	primaryRatio = 1.955,
	finalRatio = 3.0,
	wheelRadius = 0.315 * PER_M, -- 180/55 R17 rear tyre
	peakPowerRpm = 13000, -- manufacturer rating quoted by MOTORRAD (120 PS at 13,000/min)
	redlineRpm = 15500, -- ESTIMATE: no confirmed 2005 figure found
	clutchSlipRpm = 9000, -- ESTIMATE: rpm held while slipping the clutch to pull away
	shiftCutTime = 0.12, -- ESTIMATE: power cut per upshift
	-- Automatic gearbox (optional, in the settings panel)
	autoUpshiftRpm = 15000, -- just under the redline
	autoDownshiftRpm = 8000,

	-- Engine and resistance (fitted)
	peakPowerPerMass = 264 * PER_M * PER_M, -- W/kg at the wheel, bike plus rider
	launchAccel = 9.0 * PER_M, -- 0.92 g: where the front wheel lifts at full throttle
	rollingResistance = 0.015 * G * PER_M, -- standard value for motorcycle tyres
	aeroDrag = 0.0006234 * STUD_M, -- per stud; drag balances drive in 6th at exactly 265 km/h
	-- ESTIMATE, no measured source: engine braking at the redline with the throttle closed;
	-- it scales with rpm, so lower gears slow the bike harder
	engineBraking = 1.0 * PER_M,
	maxSpeed = 300 / 3.6 * PER_M, -- safety cap only; real top speed comes from drag

	-- Brakes
	-- Full front lever: with engine braking in 2nd, rolling and air drag, stops the bike from
	-- 100 km/h in 38.5 m, as measured.
	frontBrakeDecel = 9.229 * PER_M,
	-- ESTIMATE: rear brake alone. A braking-dynamics model gives 0.29 g rear-only at tyre grip
	-- 0.8 (dynamotion.it); sport tyres grip more, so 0.35 g.
	rearBrakeDecel = 0.35 * G * PER_M,
	-- Front and rear together cannot exceed sportbike pitch-over: ~0.98 g (engrxiv preprint,
	-- citing Fatzinger et al. 2019).
	maxBrakeDecel = 0.98 * G * PER_M,

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
