--!strict
-- Pure crash rules: no Roblox objects, so they run under Lune in tests.
local Crash = {}

-- Speed lost between two samples, or 0 if the loss is too small to be a crash.
function Crash.impact(previousSpeed: number, currentSpeed: number, minDrop: number): number
	if previousSpeed ~= previousSpeed or currentSpeed ~= currentSpeed then
		return 0
	end
	local drop = previousSpeed - currentSpeed
	if drop < minDrop then
		return 0
	end
	return drop
end

-- Speed lost against the fastest recent sample. A wall stops the bike over several
-- frames, so comparing only two adjacent frames would badly under-count the hit.
function Crash.impactOverWindow(
	recentSpeeds: { number },
	currentSpeed: number,
	minDrop: number
): number
	local peak = 0
	for _, speed in recentSpeeds do
		if speed == speed and speed > peak then
			peak = speed
		end
	end
	return Crash.impact(peak, currentSpeed, minDrop)
end

-- Damage grows with the square of the speed lost, capped at max health.
function Crash.damage(impactSpeed: number, maxSpeed: number, maxHealth: number): number
	if impactSpeed ~= impactSpeed or impactSpeed <= 0 then
		return 0
	end
	local ratio = math.clamp(impactSpeed / maxSpeed, 0, 1)
	return math.floor(ratio * ratio * maxHealth)
end

function Crash.applyDamage(health: number, damage: number): number
	return math.max(health - damage, 0)
end

function Crash.isDead(health: number): boolean
	return health <= 0
end

return Crash
