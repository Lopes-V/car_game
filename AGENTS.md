# AGENTS.md

## Project

This repository contains the Godot 4 MVP for a two-player local arcade racing game where the players extend and sabotage one persistent linear track between rounds.

The binding product specification is:

- `docs/superpowers/specs/2026-08-24-mvp-v0.1-design.md`

The implementation sequence is:

- `docs/superpowers/plans/2026-08-24-corrida-construcao-mvp.md`

When the plan and implementation disagree, follow the specification. Do not expand the MVP without explicit user approval.

## MVP boundaries

- Exactly two local players in split-screen.
- Godot 4 and GDScript only.
- Strictly linear track: `TrackStart -> TrackPieces[] -> TrackEndConnector -> Finish`.
- Allowed build variants: `straight`, `curve_left`, `curve_right`, and `uphill`.
- Persistent modifications: ice and dynamite in predefined trap slots.
- Three lives and one non-rechargeable boost per player per round.
- Maximum five rounds; target score is 20 and is evaluated only after round results.
- No online mode, bots, branches, loops, bridges, ramps, vehicle customization, inventory, progression, or external art pipeline in v0.1.

## Architecture

- Keep deterministic rules in pure `RefCounted` domain classes under `scripts/domain/`.
- Runtime Godot nodes bind domain state to scenes; they must not duplicate domain geometry or scoring rules.
- `RaceState` owns phase transitions and timing.
- `TrackLayout` owns ordered pieces, valid build options, collision validation, checkpoint cadence, and progress lengths.
- `TrackManager` owns runtime piece instances and one persistent movable `Finish` node.
- Managers communicate through narrow public methods and signals. UI reads state and emits intent; it does not recompute gameplay rules.
- Track progress uses path distance in meters, never Euclidean proximity or mixed normalized units.

## Development workflow

Use strict RED-GREEN-REFACTOR for every gameplay behavior:

1. Add a behavioral test that fails for the intended missing behavior.
2. Run it and record the expected nonzero result.
3. Implement the smallest production change.
4. Run the full headless suite once and keep its output clean.
5. Run editor import/parsing and `git diff --check` before committing.

Tests use the project-owned runner. On PowerShell:

```powershell
$godot = & .\tools\find_godot.ps1
& $godot --headless --path . -s "$PWD\tests\test_runner.gd"
& $godot --headless --path . --editor --quit
git diff --check
```

`tools/find_godot.ps1` resolves the official console wrapper so failing suites return a nonzero process exit code. The portable engine lives under ignored `.tools/`; never commit engine archives, executables, imports, or agent workspaces.

## Test rules

- Tests must exercise real domain or scene behavior, not mocks of the component under test.
- Every suite implements `run() -> bool` and is registered in `tests/test_runner.gd`.
- Derive expected values independently with literal fixtures.
- Do not add production methods used only by tests.
- Scene tests attach nodes to a temporary active `SceneTree` root and free that root afterward.
- Preserve all earlier suites when adding a new one.

## Git rules

- Preserve unrelated work and stage exact paths.
- Inspect `git diff --cached --check` before every commit.
- Keep commits scoped by responsibility.
- Do not commit `.godot/`, `.tools/`, `.superpowers/`, or `.worktrees/`.
- Do not rewrite published history or force-push unless the user explicitly requests it.
