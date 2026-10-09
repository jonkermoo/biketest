--!strict
-- Input settings.
return table.freeze({
	-- Mouse-wheel lever: share of full throttle (or full brake) per wheel notch
	throttleStep = 0.05,
	-- Which wheel direction means "faster": notches = wheel delta * this sign. The first
	-- version used -1, and on the user's mouse that felt backwards (rolling the wheel down
	-- toward you slowed the bike), so it was flipped on 2026-10-09. If it ever feels backwards
	-- on another mouse, flip it again.
	scrollFasterSign = 1,
})
