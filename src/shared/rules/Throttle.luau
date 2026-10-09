--!strict
-- Pure twist-grip control on the mouse wheel. One lever runs from full brake (-1) through
-- closed (0) to full throttle (+1). Rolling toward "slower" closes the throttle, then starts
-- braking; rolling back releases the brake, then opens the throttle. It stays where the rider
-- leaves it.
local Throttle = {}

-- New lever position after a scroll. `notches` is positive for "faster" and negative for
-- "slower"; the client maps the mouse wheel's direction onto that (see config/Controls).
function Throttle.fromScroll(lever: number, notches: number, step: number): number
	if lever ~= lever then
		lever = 0
	end
	if notches ~= notches then
		return math.clamp(lever, -1, 1)
	end
	return math.clamp(lever + notches * step, -1, 1)
end

-- Split the lever into throttle (0..1) and brake (0..1). Only one is ever non-zero.
function Throttle.split(lever: number): (number, number)
	if lever ~= lever then
		return 0, 0
	end
	local l = math.clamp(lever, -1, 1)
	return math.max(l, 0), math.max(-l, 0)
end

return Throttle
