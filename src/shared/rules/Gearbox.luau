--!strict
-- Pure gearbox and engine: rpm from road speed, drive force from the power curve and gear
-- ratio, engine braking from rpm, and which shifts are allowed. No Roblox objects.
local Gearbox = {}

export type Params = {
	gearRatios: { number }, -- 1st..top
	primaryRatio: number,
	finalRatio: number,
	wheelRadius: number, -- studs
	peakPowerRpm: number,
	redlineRpm: number,
	clutchSlipRpm: number, -- below this the rider slips the clutch (pulling away)
	peakPowerPerMass: number, -- at the wheel, studs^2/s^3
	launchAccel: number, -- front-wheel-lift limit
	engineBraking: number, -- at redline with the throttle closed
}

local TWO_PI = 2 * math.pi

-- Engine rpm in a gear at a road speed (no clutch slip).
function Gearbox.rpm(speed: number, gear: number, p: Params): number
	local ratio = p.gearRatios[gear] * p.primaryRatio * p.finalRatio
	return math.max(speed, 0) / p.wheelRadius * 60 / TWO_PI * ratio
end

-- Share of peak power at an rpm (a standard cubic fit for petrol engines, 1 at the peak).
function Gearbox.powerShape(rpm: number, peakRpm: number): number
	local x = rpm / peakRpm
	return math.max(x + x * x - x * x * x, 0)
end

-- Forward acceleration from the engine at full throttle scaled by `throttle`. At the rev
-- limiter the ignition cuts, so there is no drive. Below the clutch-slip rpm the rider slips
-- the clutch, so the engine runs at that rpm while the bike pulls away.
function Gearbox.driveAccel(speed: number, throttle: number, gear: number, p: Params): number
	if throttle <= 0 then
		return 0
	end
	local rpm = Gearbox.rpm(speed, gear, p)
	if rpm >= p.redlineRpm then
		return 0
	end
	local engineRpm = math.max(rpm, p.clutchSlipRpm)
	local omega = engineRpm * TWO_PI / 60
	local torquePerMass = p.peakPowerPerMass * Gearbox.powerShape(engineRpm, p.peakPowerRpm) / omega
	local ratio = p.gearRatios[gear] * p.primaryRatio * p.finalRatio
	return throttle * math.min(torquePerMass * ratio / p.wheelRadius, p.launchAccel)
end

-- Engine braking with the throttle closed: stronger at high rpm, so a lower gear slows the
-- bike harder. Fades in as the throttle closes.
function Gearbox.engineBraking(speed: number, throttle: number, gear: number, p: Params): number
	if speed <= 0 then
		return 0
	end
	local share = math.min(Gearbox.rpm(speed, gear, p) / p.redlineRpm, 1)
	return p.engineBraking * share * (1 - math.clamp(throttle, 0, 1))
end

-- Gear after asking to shift up (+1) or down (-1). A downshift that would send the engine
-- past the redline is refused, like an ECU protecting the engine. Returns the gear and
-- whether the shift happened.
function Gearbox.shift(gear: number, direction: number, speed: number, p: Params): (number, boolean)
	local target = gear + (if direction > 0 then 1 else -1)
	if target < 1 or target > #p.gearRatios then
		return gear, false
	end
	if direction < 0 and Gearbox.rpm(speed, target, p) > p.redlineRpm then
		return gear, false
	end
	return target, true
end

-- Automatic gearbox: which way to shift this frame (+1, -1 or 0).
-- Up: at `upRpm`, or earlier if the next gear already pulls harder (past the power peak).
-- Down: when rpm falls below `downRpm`, and only if the lower gear lands well under `upRpm`,
-- so it can never bounce between two gears or over-rev.
function Gearbox.autoShift(
	speed: number,
	gear: number,
	throttle: number,
	p: Params,
	upRpm: number,
	downRpm: number
): number
	local rpm = Gearbox.rpm(speed, gear, p)
	local top = #p.gearRatios
	if gear < top then
		local nextPullsHarder = throttle > 0
			and Gearbox.driveAccel(speed, 1, gear + 1, p)
				> Gearbox.driveAccel(speed, 1, gear, p)
		if rpm >= upRpm or nextPullsHarder then
			return 1
		end
	end
	if gear > 1 and rpm < downRpm and Gearbox.rpm(speed, gear - 1, p) <= upRpm * 0.92 then
		return -1
	end
	return 0
end

return Gearbox
