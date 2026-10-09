--!strict
-- Every tweakable number for the bike lives here. Balance by editing data, not code.
-- Speeds are studs/s, accelerations studs/s^2, angles radians.
return table.freeze({
	-- Motion
	maxSpeed = 90,
	acceleration = 28,
	brakeDecel = 60,
	drag = 8, -- passive slowdown when no throttle
	maxTurnRate = 1.6, -- rad/s at low speed
	turnFalloff = 0.65, -- 0..1, how much turning is reduced at max speed
	syncSlack = 4, -- if physics slows us by more than this, accept the slower speed

	-- Crash
	maxHealth = 100,
	crashMinDrop = 18, -- sudden speed loss below this is not a crash
	crashHitCooldown = 0.5,
	crashSettle = 0.2, -- seconds to watch a collision play out before applying damage
	crashWindow = 0.3, -- seconds of speed history used to measure an impact

	-- Respawn
	respawnCooldown = 3,
})
