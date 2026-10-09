--!strict
local BikeDynamics = require("../src/shared/rules/BikeDynamics")
local Crash = require("../src/shared/rules/Crash")
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
	maxCurvature = 0.1,
	curvatureSpeedRef = 20,
	leanRate = 5,
	gravity = 35,
	tyreGrip = 1.0,
	steerAssist = 0.8,
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
near("throttle accelerates about 20 in 1 s", s.speed, 20, 0.5)
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
local steady = run(at(30), { throttle = 0.3, brake = 0, steer = 0.5 }, 3)
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
