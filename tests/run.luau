--!strict
local BikeDynamics = require("../src/shared/rules/BikeDynamics")
local Crash = require("../src/shared/rules/Crash")
local Gearbox = require("../src/shared/rules/Gearbox")
local LookSteer = require("../src/shared/rules/LookSteer")
local Throttle = require("../src/shared/rules/Throttle")
local Respawn = require("../src/shared/rules/Respawn")
local RiderSettings = require("../src/shared/rules/RiderSettings")

local failures = 0
local function check(name: string, got: any, want: any)
	if got ~= want then
		failures += 1
		print(`FAIL {name}: got {got}, want {want}`)
	else
		print(`ok   {name}`)
	end
end
local function near(name: string, got: number, want: number, tol: number)
	if math.abs(got - want) > tol or got ~= got then
		failures += 1
		print(`FAIL {name}: got {got}, want {want} ± {tol}`)
	else
		print(`ok   {name}`)
	end
end

local params: BikeDynamics.Params = {
	maxSpeed = 100,
	-- Simple numbers for the generic tests: one huge-power gear so the push is a constant 20
	-- (the launch limit), constant rolling drag of 10, no engine braking or air drag. The
	-- real R6 numbers are tested against measured data further down.
	gearRatios = { 1 },
	primaryRatio = 1,
	finalRatio = 1,
	wheelRadius = 1,
	peakPowerRpm = 1e9,
	redlineRpm = 1e12,
	clutchSlipRpm = 1,
	peakPowerPerMass = 1e15,
	launchAccel = 20,
	engineBraking = 0,
	shiftCutTime = 0,
	rollingResistance = 10,
	aeroDrag = 0,
	frontBrakeDecel = 35,
	rearBrakeDecel = 10,
	maxBrakeDecel = 1e9,
	maxCurvature = 0.1,
	curvatureSpeedRef = 20,
	leanRate = 5,
	gravity = 35,
	tyreGrip = 1.0,
	steerAssist = 0.8,
	lookGripLimit = 1.5,
	slideDecel = 20,
	lyingLean = 1.4,
}

local function run(state, input, seconds)
	local events
	local dt = 1 / 60
	for _ = 1, math.floor(seconds / dt) do
		state, events = BikeDynamics.step(state, input, params, dt)
	end
	return state, events
end

local function at(speed: number)
	local s = BikeDynamics.newState(0)
	s.speed = speed
	return s
end

-- sanitize
check("sanitize nan is 0", BikeDynamics.sanitize(0 / 0, -1, 1), 0)
check("sanitize string is 0", BikeDynamics.sanitize("1", -1, 1), 0)
check("sanitize clamps high", BikeDynamics.sanitize(5, -1, 1), 1)
check("sanitize clamps low", BikeDynamics.sanitize(-5, 0, 1), 0)

-- speed
local s = run(BikeDynamics.newState(0), { throttle = 1, brake = 0, steer = 0 }, 1)
near("full throttle gains acceleration minus rolling drag", s.speed, 10, 0.5)
s = run(at(50), { throttle = 0, brake = 0, steer = 0 }, 1)
near("no throttle applies drag", s.speed, 40, 0.5)
s = run(at(50), { throttle = 0, brake = 1, steer = 0 }, 1)
near("brake slows", s.speed, 5, 0.5)
s = run(at(10), { throttle = 0, brake = 1, steer = 0 }, 2)
check("speed never negative", s.speed, 0)
s = run(at(95), { throttle = 1, brake = 0, steer = 0 }, 2)
check("speed capped at max", s.speed, 100)
s = run(at(50), { throttle = 0 / 0, brake = 0 / 0, steer = 0 / 0 }, 1)
near("nan input behaves like no input", s.speed, 40, 0.5)

-- Real bike: the game config must reproduce MOTORRAD's measured 2005 Yamaha YZF-R6 figures.
local R6 = require("../src/shared/config/Bike")
local KMH = 1 / 3.6 / 0.28 -- km/h to studs/s
local M = 1 / 0.28 -- metres to studs

-- Ride with a perfect rider: full throttle, upshift at the redline. Returns the time to reach
-- `kmh` (or the speed after `seconds` if kmh is nil).
local function ride(kmh: number?, seconds: number, throttle: number): (number, BikeDynamics.State)
	local st, t, dt = BikeDynamics.newState(0), 0, 1 / 240
	while t < seconds and (kmh == nil or st.speed < kmh * KMH) do
		-- shift up at the redline, or as soon as the next gear pulls harder
		local atRedline = Gearbox.rpm(st.speed, st.gear, R6) >= R6.redlineRpm * 0.995
		local nextPullsHarder = st.gear < #R6.gearRatios
			and Gearbox.driveAccel(st.speed, 1, st.gear + 1, R6)
				> Gearbox.driveAccel(st.speed, 1, st.gear, R6)
		local shift = if atRedline or nextPullsHarder then 1 else 0
		st = BikeDynamics.step(
			st,
			{ throttle = throttle, brake = 0, steer = 0, shift = shift },
			R6,
			dt
		)
		t += dt
	end
	return t, st
end
local function stoppingDistance(kmh: number, front: number, rear: number, gear: number): number
	local st, travelled, dt = at(kmh * KMH), 0, 1 / 1000
	st.gear = gear
	while st.speed > 0 do
		travelled += st.speed * dt
		st = BikeDynamics.step(
			st,
			{ throttle = 0, brake = front, rearBrake = rear, steer = 0 },
			R6,
			dt
		)
	end
	return travelled
end

near("R6: 0-100 km/h in 3.2 s (measured)", (ride(100, 60, 1)), 3.2, 0.1)
near("R6: 0-140 km/h in 4.9 s (measured)", (ride(140, 60, 1)), 4.9, 0.15)
near("R6: 0-200 km/h in 9.6 s (measured)", (ride(200, 60, 1)), 9.6, 0.3)
local _, flatOut = ride(nil, 90, 1)
near("R6: top speed 265 km/h (measured)", flatOut.speed / KMH, 265, 3)
check("R6: the safety cap does not set the top speed", flatOut.speed < R6.maxSpeed - 1, true)
check("R6: top speed is reached in 6th", flatOut.gear, 6)
near(
	"R6: full front brake 100-0 km/h in 2nd: 38.5 m (measured)",
	stoppingDistance(100, 1, 0, 2) / M,
	38.5,
	1
)
local meanDecel = (100 / 3.6) ^ 2 / (2 * stoppingDistance(100, 1, 0, 2) / M)
near("R6: mean braking deceleration 10.0 m/s^2 (measured)", meanDecel, 10.0, 0.3)
check(
	"R6: half brake stops in a longer distance",
	stoppingDistance(100, 0.5, 0, 2) > stoppingDistance(100, 1, 0, 2),
	true
)
check(
	"R6: stopping distance grows with the square of speed",
	stoppingDistance(140, 1, 0, 3) > 1.8 * stoppingDistance(100, 1, 0, 2),
	true
)
check(
	"R6: power fades with speed in a gear (less push at 150 than at 100 km/h in 2nd)",
	BikeDynamics.driveAccel(150 * KMH, 1, 2, R6) < BikeDynamics.driveAccel(100 * KMH, 1, 2, R6),
	true
)
near(
	"R6: launch limited to 0.92 g (front wheel lift)",
	BikeDynamics.driveAccel(1, 1, 1, R6) / R6.gravity,
	0.92,
	0.01
)
check(
	"R6: closing the throttle adds engine braking",
	BikeDynamics.resistance(100 * KMH, 0, 2, R6) > BikeDynamics.resistance(100 * KMH, 1, 2, R6),
	true
)
check(
	"R6: resistance is zero when stopped (no rolling backwards)",
	BikeDynamics.resistance(0, 0, 1, R6),
	0
)

-- Gearbox
local function gearTopSpeed(gear: number): number
	return R6.redlineRpm / Gearbox.rpm(1, gear, R6) / KMH
end
near("R6: 1st gear runs out at about 110 km/h", gearTopSpeed(1), 110, 2)
near("R6: 2nd gear runs out at about 161 km/h", gearTopSpeed(2), 161, 2)
check(
	"R6: each gear is taller than the last",
	gearTopSpeed(3) > gearTopSpeed(2) and gearTopSpeed(6) > gearTopSpeed(5),
	true
)
near("R6: about 14,200 rpm at 265 km/h in 6th", Gearbox.rpm(265 * KMH, 6, R6), 14200, 150)
check("R6: no drive at the rev limiter", Gearbox.driveAccel(115 * KMH, 1, 1, R6), 0)
check(
	"R6: 6th gear pulls much weaker than 2nd at 80 km/h",
	Gearbox.driveAccel(80 * KMH, 1, 6, R6) < 0.6 * Gearbox.driveAccel(80 * KMH, 1, 2, R6),
	true
)
check(
	"R6: a lower gear gives more engine braking",
	Gearbox.engineBraking(80 * KMH, 0, 2, R6) > Gearbox.engineBraking(80 * KMH, 0, 5, R6),
	true
)
check("R6: no engine braking with the throttle open", Gearbox.engineBraking(80 * KMH, 1, 2, R6), 0)
local g1, ok1s = Gearbox.shift(3, 1, 100 * KMH, R6)
check("upshift goes up one gear", g1 == 4 and ok1s, true)
local g2, ok2s = Gearbox.shift(6, 1, 100 * KMH, R6)
check("no gear above top", g2 == 6 and not ok2s, true)
local g3, ok3s = Gearbox.shift(1, -1, 10 * KMH, R6)
check("no gear below 1st", g3 == 1 and not ok3s, true)
local g4, ok4s = Gearbox.shift(3, -1, 170 * KMH, R6)
check("a downshift that would over-rev is refused", g4 == 3 and not ok4s, true)
local g5, ok5s = Gearbox.shift(3, -1, 100 * KMH, R6)
check("a safe downshift goes through", g5 == 2 and ok5s, true)
local cutState = at(60 * KMH)
cutState.gear = 2
local afterShift, shiftEvents =
	BikeDynamics.step(cutState, { throttle = 1, brake = 0, steer = 0, shift = 1 }, R6, 1 / 240)
check("shifting up reports the shift", shiftEvents.shifted and afterShift.gear == 3, true)
check("an upshift briefly cuts the drive", afterShift.shiftCut > 0, true)
local _, refused = BikeDynamics.step(
	at(150 * KMH),
	{ throttle = 0, brake = 0, steer = 0, shift = -1 },
	R6,
	1 / 240
)
check("a refused downshift is reported", refused.shiftRefused, true)

-- Brakes: front, rear, combined
check(
	"rear brake alone is far weaker than the front",
	R6.rearBrakeDecel < 0.5 * R6.frontBrakeDecel,
	true
)
check(
	"rear alone stops in a much longer distance",
	stoppingDistance(100, 0, 1, 2) > 2 * stoppingDistance(100, 1, 0, 2),
	true
)
check(
	"adding rear brake to full front helps only a little (pitch-over cap)",
	stoppingDistance(100, 1, 1, 2) > 0.95 * stoppingDistance(100, 1, 0, 2),
	true
)
near(
	"front and rear together are capped at 0.98 g",
	BikeDynamics.brakeDecel(1, 1, R6) / R6.gravity,
	0.98,
	1e-6
)
check(
	"partial front plus rear adds up below the cap",
	BikeDynamics.brakeDecel(0.3, 0.5, R6) < R6.maxBrakeDecel,
	true
)

-- straight line
s = run(at(40), { throttle = 0.5, brake = 0, steer = 0 }, 2)
near("no steer keeps heading", s.heading, 0, 1e-9)
near("no steer keeps upright", s.lean, 0, 1e-9)

-- turning and lean
s = run(at(30), { throttle = 0, brake = 0, steer = 1 }, 0.5)
check("right steer leans right", s.lean > 0, true)
check("right steer turns right (heading decreases)", s.heading < 0, true)
s = run(at(30), { throttle = 0, brake = 0, steer = -1 }, 0.5)
check("left steer leans left", s.lean < 0, true)
check("left steer turns left (heading increases)", s.heading > 0, true)

-- steady lean matches cornering physics: tan(lean) = v^2 * k / g
-- throttle 0.5 exactly balances rolling drag in these params, so the speed really is steady
local steady = run(at(30), { throttle = 0.5, brake = 0, steer = 0.5 }, 3)
local k = 0.5 * BikeDynamics.maxCurvatureAt(steady.speed, params)
local expected = math.atan(steady.speed * steady.speed * k / params.gravity)
near("steady lean matches v^2k/g", steady.lean, expected, 0.01)

-- assisted (keyboard) steering stays inside the grip budget at every speed
local worst = 0
for speed = 5, 100, 5 do
	local _, ev = run(at(speed), { throttle = 0, brake = 0, steer = 1 }, 0.05)
	local held, ev2 = run(at(speed), { throttle = 1, brake = 0, steer = 1 }, 3)
	worst = math.max(worst, ev.gripUsed, ev2.gripUsed)
	check(`full lock at {speed} does not fall`, held.fallen, false)
end
check("full lock never uses more than the assist share", worst <= params.steerAssist + 1e-6, true)

-- grip: braking hard while leaned over exceeds the budget
local leaned = run(at(40), { throttle = 0.4, brake = 0, steer = 1 }, 2)
local after, ev = BikeDynamics.step(leaned, { throttle = 0, brake = 1, steer = 1 }, params, 1 / 60)
check("hard brake mid-corner loses grip", ev.lostGrip, true)
check("losing grip means falling", after.fallen, true)

-- worn tyres: the same corner is safe on good tyres and unsafe on bad ones
check("gripUsed within budget on good tyres", BikeDynamics.gripUsed(0.8, 0, 1.0) <= 1, true)
check("same corner over budget on worn tyres", BikeDynamics.gripUsed(0.8, 0, 0.6) > 1, true)
near("friction circle combines forces", BikeDynamics.gripUsed(0.6, 0.8, 1.0), 1.0, 1e-9)

-- fallen bike slides to a stop and lies over, ignoring controls
local fallen = at(30)
fallen.fallen = true
fallen.lean = 0.3
local slid = run(fallen, { throttle = 1, brake = 0, steer = -1 }, 3)
check("fallen bike ignores throttle and stops", slid.speed, 0)
near("fallen bike lies over on its side", slid.lean, params.lyingLean, 0.05)
check("fallen bike stays fallen", slid.fallen, true)

-- curvature
check(
	"tighter turns possible when slow",
	BikeDynamics.maxCurvatureAt(5, params) > BikeDynamics.maxCurvatureAt(50, params),
	true
)
near("standstill curvature is the geometric max", BikeDynamics.maxCurvatureAt(0, params), 0.1, 1e-9)

-- LookSteer.curvatureTo
check("look straight ahead: no turn", LookSteer.curvatureTo(0, 50), 0)
check("look right: turn right", LookSteer.curvatureTo(5, 50) > 0, true)
check("look left: turn left", LookSteer.curvatureTo(-5, 50) < 0, true)
near(
	"left and right are symmetric",
	LookSteer.curvatureTo(5, 50),
	-LookSteer.curvatureTo(-5, 50),
	1e-12
)
near("pure pursuit arc k = 2x/d^2", LookSteer.curvatureTo(3, 4), 2 * 3 / 25, 1e-12)
check(
	"looking further ahead asks for a gentler turn",
	LookSteer.curvatureTo(5, 100) < LookSteer.curvatureTo(5, 30),
	true
)
check("target behind on the right: tightest right", LookSteer.curvatureTo(5, -10), math.huge)
check("target behind on the left: tightest left", LookSteer.curvatureTo(-5, -10), -math.huge)
check("target straight behind: no turn", LookSteer.curvatureTo(0, -10), 0)
check("nan look is no turn", LookSteer.curvatureTo(0 / 0, 10), 0)

-- looking: a gentle look is safe, a sharp look at speed drops the bike
local gentle = run(
	at(40),
	{ throttle = 0.3, brake = 0, steer = 0, curvature = LookSteer.curvatureTo(2, 120) },
	3
)
check("gentle look at speed does not fall", gentle.fallen, false)
local sharp = run(
	at(60),
	{ throttle = 0.3, brake = 0, steer = 0, curvature = LookSteer.curvatureTo(15, 30) },
	3
)
check("sharp look at speed falls", sharp.fallen, true)
local slowSharp =
	run(at(8), { throttle = 0, brake = 0, steer = 0, curvature = LookSteer.curvatureTo(15, 30) }, 2)
check("same sharp look at walking pace is fine", slowSharp.fallen, false)
local turned = run(
	at(30),
	{ throttle = 0.3, brake = 0, steer = 0, curvature = LookSteer.curvatureTo(4, 80) },
	1
)
check("look right makes the bike turn right", turned.heading < 0 and turned.lean > 0, true)
local _, capped = BikeDynamics.step(
	at(60),
	{ throttle = 0, brake = 0, steer = 0, curvature = math.huge },
	params,
	1
)
check(
	"an infinite look demand is capped by lookGripLimit",
	capped.gripUsed <= params.lookGripLimit + 1e-6,
	true
)
check(
	"look demand is not limited by the keyboard assist",
	BikeDynamics.lookCurvatureCap(40, params) > BikeDynamics.maxCurvatureAt(40, params),
	true
)
check(
	"look demand never exceeds steering lock",
	BikeDynamics.lookCurvatureCap(1, params) <= params.maxCurvature,
	true
)
local nanLook = run(at(30), { throttle = 0, brake = 0, steer = 0, curvature = 0 / 0 }, 1)
near("nan look demand keeps straight", nanLook.heading, 0, 1e-9)

-- LookSteer.fixate
local prev = { x = 0, z = 0 }
local raw = { x = 10, z = 0 }
local off = LookSteer.fixate(prev, raw, true, 0, 1 / 60)
check("fixation off follows the look exactly", off.x, 10)
local notHazard = LookSteer.fixate(prev, raw, false, 1, 1 / 60)
check("fixation ignores non-hazards", notHazard.x, 10)
local sticky = LookSteer.fixate(prev, raw, true, 1, 1 / 60)
check("fixation on a hazard lets go slowly", sticky.x > 0 and sticky.x < 1, true)
local mild = LookSteer.fixate(prev, raw, true, 0.3, 1 / 60)
check("stronger fixation is stickier", mild.x > sticky.x, true)

-- Throttle lever: -1 full brake, 0 closed, +1 full throttle
local function scroll(lever: number, notches: number): number
	return Throttle.fromScroll(lever, notches, 0.05, 0.10) -- throttle 5%, brake 10% per notch
end
near("a notch toward faster opens the throttle by the throttle step", scroll(0, 1), 0.05, 1e-9)
near("a notch toward slower closes the throttle by the throttle step", scroll(0.5, -1), 0.45, 1e-9)
near("from closed, slower brakes by the brake step", scroll(0, -1), -0.10, 1e-9)
near("rolling off then braking: 0.05 -> closed -> two brake notches", scroll(0.05, -3), -0.20, 1e-9)
near("from braking, faster releases by the brake step", scroll(-0.3, 1), -0.20, 1e-9)
check("a notch stops at closed instead of crossing into brake", scroll(0.02, -1), 0)
check("a notch stops at closed instead of crossing into throttle", scroll(-0.04, 1), 0)
near("releasing the brake then opening the throttle", scroll(-0.1, 3), 0.10, 1e-9)
check("lever cannot pass full throttle", scroll(0.98, 3), 1)
check("lever cannot pass full brake", scroll(-0.95, -3), -1)
near("no scroll leaves it where it was", scroll(0.35, 0), 0.35, 1e-9)
check("nan scroll leaves it where it was", scroll(0.35, 0 / 0), 0.35)
check("nan lever is treated as closed", scroll(0 / 0, 1) > 0, true)
near("half a notch (trackpad) moves half a step", scroll(0.2, 0.5), 0.225, 1e-9)

local t1, b1 = Throttle.split(0.6)
check("positive lever is throttle only", t1 == 0.6 and b1 == 0, true)
local t2, b2 = Throttle.split(-0.4)
check("negative lever is brake only", t2 == 0 and b2 == 0.4, true)
local t3, b3 = Throttle.split(0)
check("closed lever is neither", t3 == 0 and b3 == 0, true)
local t4, b4 = Throttle.split(0 / 0)
check("nan lever is neither", t4 == 0 and b4 == 0, true)
local t5, b5 = Throttle.split(5)
check("split clamps to full", t5 == 1 and b5 == 0, true)

-- braking from the lever really slows the bike, and harder braking slows it faster
local soft = run(at(60), { throttle = 0, brake = 0.3, steer = 0 }, 1)
local hard = run(at(60), { throttle = 0, brake = 0.9, steer = 0 }, 1)
check("lever braking slows the bike", soft.speed < 60, true)
check("harder lever braking slows it more", hard.speed < soft.speed, true)

-- Crash.impact / impactOverWindow / damage (kept for the part damage model)
check("small drop is not a crash", Crash.impact(50, 45, 18), 0)
check("big drop is a crash", Crash.impact(50, 10, 18), 40)
check("gradual wall stop measured from peak", Crash.impactOverWindow({ 80, 70, 50, 30 }, 5, 18), 75)
check("full-speed impact is lethal", Crash.damage(100, 100, 100), 100)
check("nan impact no damage", Crash.damage(0 / 0, 100, 100), 0)

-- Respawn.check
local ok1 = Respawn.check(0, 10, 0, 3)
check("respawn past cooldown allowed", ok1, true)
local ok3, why3 = Respawn.check(0, 10, 9, 3)
check("cooldown blocks respawn", ok3, false)
check("cooldown reason", why3, "cooldown")
local ok4, why4 = Respawn.check(2, 10, 0, 3)
check("payload blocks respawn", ok4, false)
check("payload reason", why4, "unexpected payload")
local ok5 = Respawn.check(0, 10, -math.huge, 3)
check("first respawn always allowed", ok5, true)

-- RiderSettings: defaults, ranges, bindings
local d = RiderSettings.defaults()
check("default upshift is R", d.bindings.upshift, "R")
check("default downshift is E", d.bindings.downshift, "E")
check("default threshold brake is left click", d.bindings.thresholdBrake, "MouseButton1")
check("default rear brake is right click", d.bindings.rearBrake, "MouseButton2")
check("respawn moved off R", d.bindings.respawn ~= "R", true)
local d2 = RiderSettings.defaults()
d2.bindings.upshift = "T"
check("defaults are fresh copies", RiderSettings.defaults().bindings.upshift, "R")

local clean = RiderSettings.sanitize({
	throttleStep = 0.123,
	brakeStep = 5,
	thresholdBrake = -1,
	rearBrakeGrowth = 0 / 0,
	scrollFasterSign = 7,
	hacked = "yes",
	bindings = { upshift = "Q", downshift = "Escape", respawn = 42 },
})
near("values snap to their increment", clean.throttleStep, 0.12, 1e-9)
check("values above range clamp to max", clean.brakeStep, 0.25)
check("values below range clamp to min", clean.thresholdBrake, 0.05)
check("nan falls back to the default", clean.rearBrakeGrowth, 2.5)
check("invalid scroll sign falls back to default", clean.scrollFasterSign, 1)
check("unknown fields are dropped", (clean :: any).hacked, nil)
check("a valid binding is kept", clean.bindings.upshift, "Q")
check("a Roblox-reserved key is refused", clean.bindings.downshift, "E")
check("a non-string binding is refused", clean.bindings.respawn, "Backspace")
check("steering keys cannot be bound", RiderSettings.isBindable("A"), false)
check("mouse buttons can be bound", RiderSettings.isBindable("MouseButton2"), true)
check("garbage becomes defaults", RiderSettings.sanitize("nope").throttleStep, 0.05)

local dup = RiderSettings.sanitize({ bindings = { upshift = "R", downshift = "R" } })
check("duplicate binding: first keeps it", dup.bindings.upshift, "R")
check("duplicate binding: second is unbound", dup.bindings.downshift, "None")

local swapped = RiderSettings.rebind(d.bindings, "upshift", "E")
check("rebinding to a used key gives it to the new action", swapped.upshift, "E")
check("the other action takes the old key", swapped.downshift, "R")
check("rebind does not change the original", d.bindings.upshift, "R")
local reservedKey = RiderSettings.rebind(d.bindings, "upshift", "Escape")
check("rebinding to a reserved key is ignored", reservedKey.upshift, "R")
local fresh = RiderSettings.rebind(d.bindings, "respawn", "X")
check("rebinding to a free key just sets it", fresh.respawn, "X")

-- profiles
local p = RiderSettings.sanitizeProfiles(nil)
check("no data gives 5 slots", #p.slots, 5)
check("no data makes profile 1 active", p.active, 1)
check("the active slot always has settings", type(p.slots[1]), "table")
check("other slots start empty", p.slots[2], false)
local p2 = RiderSettings.sanitizeProfiles({
	active = 9,
	slots = { false, { throttleStep = 0.2 }, "x", false, false, {}, {} },
})
check("an out-of-range active slot resets to 1", p2.active, 1)
check("only 5 slots are kept", #p2.slots, 5)
check("a stored profile is sanitized", (p2.slots[2] :: any).throttleStep, 0.2)
check("a junk slot becomes empty", p2.slots[3], false)
local p3 =
	RiderSettings.sanitizeProfiles({ active = 4, slots = { false, false, false, false, false } })
check("an empty active slot is filled with defaults", type(p3.slots[4]), "table")

-- rear brake grows exponentially while held, and releases instantly
check("rear brake is off when not held", RiderSettings.rearBrakePressure(nil, 0.05, 2.5), 0)
near(
	"rear brake starts at the start pressure",
	RiderSettings.rearBrakePressure(0, 0.05, 2.5),
	0.05,
	1e-9
)
near(
	"rear brake grows exponentially",
	RiderSettings.rearBrakePressure(0.5, 0.05, 2.5),
	0.05 * math.exp(1.25),
	1e-9
)
check(
	"rear brake doubles in a fixed time (exponential)",
	math.abs(
		RiderSettings.rearBrakePressure(0.3, 0.05, 2)
				/ RiderSettings.rearBrakePressure(0.1, 0.05, 2)
			- math.exp(0.4)
	) < 1e-9,
	true
)
check("rear brake never exceeds full", RiderSettings.rearBrakePressure(30, 0.05, 2.5), 1)
check(
	"faster growth reaches full sooner",
	RiderSettings.rearBrakeTimeToFull(0.05, 5) < RiderSettings.rearBrakeTimeToFull(0.05, 2.5),
	true
)
near(
	"time to full at defaults",
	RiderSettings.rearBrakeTimeToFull(0.05, 2.5),
	math.log(20) / 2.5,
	1e-9
)
check("nan hold time is off", RiderSettings.rearBrakePressure(0 / 0, 0.05, 2.5), 0)

-- Automatic gearbox
local function autoRide(throttleAt: (number) -> number, seconds: number)
	local st, t, dt = BikeDynamics.newState(0), 0, 1 / 240
	local shifts, maxRpm, timeTo100 = 0, 0, nil
	while t < seconds do
		local throttle = throttleAt(t)
		local shift = Gearbox.autoShift(
			st.speed,
			st.gear,
			throttle,
			R6,
			R6.autoUpshiftRpm,
			R6.autoDownshiftRpm
		)
		local events
		st, events = BikeDynamics.step(
			st,
			{ throttle = throttle, brake = 0, steer = 0, shift = shift },
			R6,
			dt
		)
		if events.shifted then
			shifts += 1
		end
		maxRpm = math.max(maxRpm, events.rpm)
		if not timeTo100 and st.speed >= 100 * KMH then
			timeTo100 = t
		end
		t += dt
	end
	return st, shifts, maxRpm, timeTo100
end
local flat, _, flatMaxRpm, auto100 = autoRide(function()
	return 1
end, 90)
check("auto: flat out ends in 6th", flat.gear, 6)
near("auto: flat out reaches the measured top speed", flat.speed / KMH, 265, 3)
near("auto: 0-100 km/h close to the measured 3.2 s", auto100 or 99, 3.2, 0.15)
check("auto: never over-revs", flatMaxRpm <= R6.redlineRpm + 1, true)
local _, cruiseShifts = autoRide(function(t)
	return if t < 8 then 1 else 0.3
end, 40)
local cruising, settledShifts = autoRide(function(t)
	return if t < 8 then 1 else 0.3
end, 60)
check("auto: steady cruising does not keep shifting", settledShifts - cruiseShifts, 0)
check("auto: cruising stays in a sensible gear", cruising.gear >= 4, true)
local slowing = at(200 * KMH)
slowing.gear = 6
for _ = 1, 240 * 12 do
	local shift = Gearbox.autoShift(
		slowing.speed,
		slowing.gear,
		0,
		R6,
		R6.autoUpshiftRpm,
		R6.autoDownshiftRpm
	)
	slowing = BikeDynamics.step(
		slowing,
		{ throttle = 0, brake = 0.6, steer = 0, shift = shift },
		R6,
		1 / 240
	)
end
check("auto: braking to a stop changes down to 1st", slowing.gear, 1)
check(
	"auto: no downshift that would over-rev",
	Gearbox.autoShift(150 * KMH, 2, 0, R6, R6.autoUpshiftRpm, R6.autoDownshiftRpm) ~= -1,
	true
)
check("auto setting defaults to off", RiderSettings.defaults().autoShift, false)
check(
	"auto setting is kept when valid",
	RiderSettings.sanitize({ autoShift = true }).autoShift,
	true
)
check(
	"auto setting rejects non-booleans",
	RiderSettings.sanitize({ autoShift = "yes" }).autoShift,
	false
)

if failures > 0 then
	error(`{failures} test(s) failed`)
end
