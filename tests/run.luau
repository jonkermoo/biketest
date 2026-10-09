--!strict
local BikeMotion = require("../src/shared/rules/BikeMotion")
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

local cfg = {
	maxSpeed = 100,
	acceleration = 20,
	brakeDecel = 50,
	drag = 10,
	maxTurnRate = 2,
	turnFalloff = 0.5,
}

-- sanitizeAxis
check("axis nan is 0", BikeMotion.sanitizeAxis(0 / 0), 0)
check("axis string is 0", BikeMotion.sanitizeAxis("1"), 0)
check("axis clamps high", BikeMotion.sanitizeAxis(5), 1)
check("axis clamps low", BikeMotion.sanitizeAxis(-5), -1)

-- step
check("throttle accelerates", BikeMotion.step(0, 1, 0, 1, cfg), 20)
check("no throttle applies drag", BikeMotion.step(50, 0, 0, 1, cfg), 40)
check("brake slows", BikeMotion.step(50, 0, 1, 1, cfg), 0)
check("speed never negative", BikeMotion.step(5, 0, 1, 1, cfg), 0)
check("speed capped at max", BikeMotion.step(95, 1, 0, 1, cfg), 100)
check("nan throttle treated as none", BikeMotion.step(50, 0 / 0, 0, 1, cfg), 40)
check("half throttle accelerates less", BikeMotion.step(0, 0.5, 0, 1, cfg), 10)

-- turnRate
check("no steer no turn", BikeMotion.turnRate(50, 0, cfg), 0)
check("full steer standing still", BikeMotion.turnRate(0, 1, cfg), 2)
check("full steer at max speed is reduced", BikeMotion.turnRate(100, 1, cfg), 1)
check("left steer is negative", BikeMotion.turnRate(0, -1, cfg), -2)
check("over-max speed is clamped for turning", BikeMotion.turnRate(500, 1, cfg), 1)

-- syncSpeed
check("small slowdown ignored", BikeMotion.syncSpeed(50, 48, 4), 50)
check("big slowdown trusted", BikeMotion.syncSpeed(50, 10, 4), 10)
check("negative actual floors at 0", BikeMotion.syncSpeed(50, -20, 4), 0)

-- Crash.impact
check("small drop is not a crash", Crash.impact(50, 45, 18), 0)
check("big drop is a crash", Crash.impact(50, 10, 18), 40)
check("speeding up is not a crash", Crash.impact(10, 50, 18), 0)
check("nan sample is not a crash", Crash.impact(0 / 0, 0, 18), 0)

-- Crash.impactOverWindow
check("gradual wall stop measured from peak", Crash.impactOverWindow({ 80, 70, 50, 30 }, 5, 18), 75)
check("empty history is no crash", Crash.impactOverWindow({}, 0, 18), 0)
check("steady speed is no crash", Crash.impactOverWindow({ 50, 50, 50 }, 50, 18), 0)
check("nan sample ignored", Crash.impactOverWindow({ 0 / 0, 40 }, 0, 18), 40)
check("small slowdown ignored", Crash.impactOverWindow({ 50, 45 }, 40, 18), 0)

-- Crash.damage
check("no impact no damage", Crash.damage(0, 100, 100), 0)
check("negative impact no damage", Crash.damage(-10, 100, 100), 0)
check("full-speed impact is lethal", Crash.damage(100, 100, 100), 100)
check("half-speed impact is a quarter", Crash.damage(50, 100, 100), 25)
check("over max is clamped", Crash.damage(500, 100, 100), 100)
check("nan impact no damage", Crash.damage(0 / 0, 100, 100), 0)

-- Crash.applyDamage / isDead
check("health reduced", Crash.applyDamage(100, 30), 70)
check("health floors at 0", Crash.applyDamage(10, 30), 0)
check("zero health is dead", Crash.isDead(0), true)
check("positive health is alive", Crash.isDead(1), false)

-- Respawn.check
local ok1 = Respawn.check(0, true, 10, 0, 3)
check("dead player past cooldown may respawn", ok1, true)
local ok2, why2 = Respawn.check(0, false, 10, 0, 3)
check("living player may not respawn", ok2, false)
check("living player reason", why2, "not dead")
local ok3, why3 = Respawn.check(0, true, 10, 9, 3)
check("cooldown blocks respawn", ok3, false)
check("cooldown reason", why3, "cooldown")
local ok4, why4 = Respawn.check(2, true, 10, 0, 3)
check("payload blocks respawn", ok4, false)
check("payload reason", why4, "unexpected payload")

if failures > 0 then
	error(`{failures} test(s) failed`)
end
