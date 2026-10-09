# biketest

A realistic motorbike game for Roblox: build and maintain your bike, then ride it. The code is a Rojo project, so scripts live in files here and sync into Studio.

## Layout

```
src/shared/config/   every tunable number (speeds, crash, respawn)
src/shared/rules/    pure Luau game rules, no Roblox objects, tested under Lune
src/shared/Remotes.luau   every client/server message name
src/server/, src/client/  the Roblox-facing scripts
tests/run.luau       tests for the rules
scripts/check.ps1    runs all four checks
```

## Requirements

[Aftman](https://github.com/LPGhatguy/aftman) installs the pinned tools listed in `aftman.toml`: Rojo, selene, StyLua and Lune.

```powershell
aftman install
```

Aftman asks you to trust each tool the first time it is installed.

## Checks

Run before syncing anything into Studio. All four must pass.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check.ps1
```

This runs `rojo build`, the Lune tests, `selene` and `stylua --check`. Fix formatting with `stylua src tests`.

## Syncing into Studio

```powershell
rojo serve
```

Then open the Rojo plugin in Studio and click Connect.

## Rules

- Code lives in files, never typed into Studio.
- Numbers go in `src/shared/config/`, message names in `src/shared/Remotes.luau`.
- Game rules stay pure so they can be tested without Roblox.
- API keys live in environment variables, never in files.
