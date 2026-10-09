--!strict
-- Pure twist-grip throttle. The grip stays where the rider leaves it.
local Throttle = {}

-- New throttle opening (0..1) after a scroll. `wheel` is the mouse wheel delta as Roblox
-- reports it: +1 per notch scrolled up, -1 per notch scrolled down. Scrolling down twists the
-- grip open (more throttle); scrolling up rolls it closed.
function Throttle.fromScroll(current: number, wheel: number, step: number): number
	if current ~= current then
		current = 0
	end
	if wheel ~= wheel then
		return math.clamp(current, 0, 1)
	end
	return math.clamp(current - wheel * step, 0, 1)
end

return Throttle
