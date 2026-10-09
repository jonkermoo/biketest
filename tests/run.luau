--!strict
local BikeDynamics = require("../src/shared/rules/BikeDynamics")
local Crash = require("../src/shared/rules/Crash")
local LookSteer = require("../src/shared/rules/LookSteer")
local Throttle = require("../src/shared/rules/Throttle")
local Respawn = require("../src/shared/rules/Respawn")

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
	acceleration = 20,
	brakeDecel = 35,
	drag = 10,
	aeroDrag = 0, -- kept at 0 so speed tests are simple; air drag has its own tests below
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

-- air drag: each throttle opening settles at its own cruising speed
local aero = table.clone(params)
aero.acceleration = 28
aero.drag = 4
aero.aeroDrag = 24 / 14400
aero.maxSpeed = 1000 -- so the cap does not hide the drag balance
local function cruise(t: number): number
	local st = BikeDynamics.newState(0)
	for _ = 1, 60 * 60 do
		st = BikeDynamics.step(st, { throttle = t, brake = 0, steer = 0 }, aero, 1 / 60)
	end
	return st.speed
end
near("full throttle settles at the designed top speed", cruise(1), 120, 0.5)
near("half throttle cruises near 77", cruise(0.5), math.sqrt(10 / aero.aeroDrag), 0.5)
near("quarter throttle cruises near 42", cruise(0.25), math.sqrt(3 / aero.aeroDrag), 0.5)
check("more throttle cruises faster", cruise(0.5) > cruise(0.25), true)
check("too little throttle to beat rolling drag stops the bike", cruise(0.1), 0)
local fast = at(100)
local slowed = run(fast, { throttle = 0.25, brake = 0, steer = 0 }, 0.5)
check("rolling off the throttle at speed slows the bike", slowed.speed < 100, true)

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

-- Throttle.fromScroll
near("scroll down opens the throttle", Throttle.fromScroll(0, -1, 0.05), 0.05, 1e-9)
near("scroll up closes the throttle", Throttle.fromScroll(0.5, 1, 0.05), 0.45, 1e-9)
check("throttle cannot open past full", Throttle.fromScroll(0.98, -3, 0.05), 1)
check("throttle cannot close past shut", Throttle.fromScroll(0.02, 3, 0.05), 0)
near("several notches at once", Throttle.fromScroll(0.2, -4, 0.05), 0.4, 1e-9)
near("no scroll leaves it where it was", Throttle.fromScroll(0.35, 0, 0.05), 0.35, 1e-9)
check("nan wheel leaves it where it was", Throttle.fromScroll(0.35, 0 / 0, 0.05), 0.35)
check("nan current is treated as shut", Throttle.fromScroll(0 / 0, -1, 0.05) > 0, true)

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

if failures > 0 then
	error(`{failures} test(s) failed`)
end
