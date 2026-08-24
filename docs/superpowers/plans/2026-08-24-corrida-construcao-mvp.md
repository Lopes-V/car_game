# Corrida Construcao MVP v0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a two-player local Godot 4 arcade racer where the linear track grows by one valid piece and one persistent trap between rounds.

**Architecture:** Keep race rules in pure `RefCounted` domain classes that run in headless tests. Bind them to Godot `Node3D`, `Area3D`, `CharacterBody3D`, cameras, and UI only in focused runtime controllers. `RaceState` owns phase transitions; managers communicate through typed signals rather than reaching into each other's state.

**Tech Stack:** Godot 4, GDScript, native `CharacterBody3D`, `Path3D`, `Area3D`, `SubViewport`, and a project-owned headless GDScript test runner. No addons or online networking.

**Spec:** `docs/superpowers/specs/2026-08-24-mvp-v0.1-design.md`

## Global Constraints

- Support exactly two local players in split-screen.
- Preserve the strict linear chain `TrackStart -> TrackPieces[] -> TrackEndConnector -> Finish`.
- Use only `straight`, `curve_left`, `curve_right`, and `uphill` build variants; no free rotation, bridge, crossing, branch, online, bot, loop, ramp, or customization feature.
- The match lasts at most five rounds; evaluate the 20-point winner only after `RESULTS` scoring.
- One player builds and the other modifies each round; roles alternate every round.
- The build system must never accept an option that later fails geometric validation. `TRACK_BUILD_BLOCKED` is the controlled terminal fallback.
- One boost charge starts every round and cannot be refilled in that round.
- Ice and dynamite persist in their occupied slots between rounds; dynamite rearms at the start of every `RACING` phase.
- All domain-rule changes start with a failing headless test, then minimal implementation, then a full headless test run.

---

## Target file structure

```text
project.godot
scenes/main/main.tscn
scenes/track/track_piece.tscn
scenes/track/finish.tscn
scenes/car/car.tscn
scenes/ui/hud.tscn
scripts/domain/race_constants.gd
scripts/domain/race_state.gd
scripts/domain/track_layout.gd
scripts/domain/build_choice.gd
scripts/domain/player_round_state.gd
scripts/domain/progress_tracker.gd
scripts/domain/score_manager.gd
scripts/track/track_piece.gd
scripts/track/track_manager.gd
scripts/build/build_manager.gd
scripts/car/car_controller.gd
scripts/traps/trap_controller.gd
scripts/game/game_controller.gd
scripts/ui/split_screen_manager.gd
tests/test_runner.gd
tests/test_race_state.gd
tests/test_track_layout.gd
tests/test_build_manager.gd
tests/test_round_rules.gd
tools/find_godot.ps1
```

### Task 1: Bootstrap the Godot project and deterministic test harness

**Files:**
- Create: `project.godot`
- Create: `scenes/main/main.tscn`
- Create: `scripts/game/game_controller.gd`
- Create: `tests/test_runner.gd`
- Create: `tools/find_godot.ps1`
- Create: `.gitignore`

**Interfaces:**
- Produces: `GameController.start_match() -> void` and a test runner that exits 0 only when every named test succeeds.
- Consumes: no earlier project code.

- [ ] **Step 1: Write the initial failing test runner expectation**

Create `tests/test_runner.gd` with a suite list that deliberately references the missing first suite:

```gdscript
extends SceneTree

const SUITES := ["res://tests/test_race_state.gd"]

func _init() -> void:
    for suite_path in SUITES:
        var suite = load(suite_path).new()
        suite.run()
    quit(0)
```

- [ ] **Step 2: Run the runner and verify the expected failure**

Run:

```powershell
$godot = & .\tools\find_godot.ps1
& $godot --headless --path . -s res://tests/test_runner.gd
```

Expected: failure because `test_race_state.gd` does not exist.

- [ ] **Step 3: Add the minimal project bootstrap**

Create `project.godot` with `run/main_scene="res://scenes/main/main.tscn"`, renderer `gl_compatibility`, and input actions `p1_accelerate`, `p1_brake`, `p1_left`, `p1_right`, `p1_boost`, plus matching `p2_` actions. Create a `Node3D` main scene with `GameController`. Make the initial suite executable:

```gdscript
# tests/test_race_state.gd
extends RefCounted

func run() -> void:
    assert(true)
```

Implement `tools/find_godot.ps1` to return `$env:GODOT_BIN` when it exists, otherwise the first existing executable in `C:\Program Files\Godot\Godot*.exe` or `C:\Program Files\Godot Engine\Godot*.exe`, and throw if none exists. Ignore `.godot/` in `.gitignore`.

- [ ] **Step 4: Run the test runner and the project import**

Run:

```powershell
$godot = & .\tools\find_godot.ps1
& $godot --headless --path . --editor --quit
& $godot --headless --path . -s res://tests/test_runner.gd
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit the bootstrap**

```powershell
git add project.godot scenes/main/main.tscn scripts/game/game_controller.gd tests/test_runner.gd tests/test_race_state.gd tools/find_godot.ps1 .gitignore
git commit -m "chore: bootstrap Godot racing project"
```

### Task 2: Implement round state and match-ending rules as pure domain logic

**Files:**
- Create: `scripts/domain/race_constants.gd`
- Create: `scripts/domain/race_state.gd`
- Modify: `tests/test_race_state.gd`

**Interfaces:**
- Produces: `RaceState.begin_round(round_number: int)`, `RaceState.begin_racing(now_seconds: float)`, `RaceState.record_finish(player_id: int, now_seconds: float)`, `RaceState.should_end_race(now_seconds: float)`, and `RaceState.resolve_match(scores: Dictionary) -> int`.
- Consumes: `RaceConstants.MAX_ROUNDS`, `RaceConstants.TARGET_SCORE`, `RaceConstants.ROUND_TIME_SECONDS`, and `RaceConstants.FINAL_WINDOW_SECONDS`.

- [ ] **Step 1: Write failing phase and score tests**

```gdscript
func test_first_finish_caps_final_window_at_hard_limit() -> void:
    var state := RaceState.new()
    state.begin_racing(110.0)
    state.record_finish(1, 119.0)
    assert(state.phase == RaceState.Phase.FINAL_WINDOW)
    assert(state.race_end_time == 120.0)

func test_target_score_is_evaluated_only_after_results() -> void:
    var state := RaceState.new()
    state.begin_round(3)
    assert(state.resolve_match({1: 21, 2: 22}) == 2)
```

- [ ] **Step 2: Run and verify the expected missing-class failure**

Run:

```powershell
$godot = & .\tools\find_godot.ps1
& $godot --headless --path . -s res://tests/test_runner.gd
```

Expected: `RaceState` is not defined.

- [ ] **Step 3: Implement the minimal state machine**

```gdscript
class_name RaceState
extends RefCounted

enum Phase { BUILD_SECRET, REVEAL, APPLY_BUILD, COUNTDOWN, RACING, FINAL_WINDOW, RESULTS, NEXT_ROUND, MATCH_END }
var phase: Phase = Phase.BUILD_SECRET
var round_number := 0
var race_end_time := 0.0
var finish_times: Dictionary = {}

func begin_racing(now_seconds: float) -> void:
    phase = Phase.RACING
    race_end_time = now_seconds + RaceConstants.ROUND_TIME_SECONDS

func record_finish(player_id: int, now_seconds: float) -> void:
    if player_id in finish_times:
        return
    finish_times[player_id] = now_seconds
    if phase == Phase.RACING:
        phase = Phase.FINAL_WINDOW
        race_end_time = min(race_end_time, now_seconds + RaceConstants.FINAL_WINDOW_SECONDS)
```

Add `resolve_match` so it returns 0 when neither score reached target, otherwise the id with highest score, with round-result tie comparison supplied by `ScoreManager` in Task 8.

- [ ] **Step 4: Run all tests**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: phase, 120-second cap, and post-results target tests pass.

- [ ] **Step 5: Commit the state model**

```powershell
git add scripts/domain/race_constants.gd scripts/domain/race_state.gd tests/test_race_state.gd
git commit -m "feat: add deterministic race state"
```

### Task 3: Implement linear track layout, valid build options, and checkpoint placement

**Files:**
- Create: `scripts/domain/track_layout.gd`
- Modify: `tests/test_runner.gd`
- Create: `tests/test_track_layout.gd`

**Interfaces:**
- Produces: `TrackLayout.get_valid_options() -> Array[BuildOption]`, `TrackLayout.append(option: BuildOption) -> void`, `TrackLayout.next_checkpoint_index() -> int`, and `TrackLayout.global_progress(piece_index: int, local_distance: float) -> float`.
- Consumes: `BuildOption`, AABB geometry and discrete variants from `race_constants.gd`.

- [ ] **Step 1: Write failing layout tests**

```gdscript
func test_option_that_intersects_existing_piece_is_not_offered() -> void:
    var layout := TrackLayout.with_initial_straight()
    layout.debug_add_piece("curve_left", Transform3D.IDENTITY)
    assert(not layout.get_valid_option_ids().has("curve_right_back_into_start"))

func test_checkpoint_waits_for_first_allowed_new_piece_after_threshold() -> void:
    var layout := TrackLayout.with_initial_straight()
    layout.append(BuildOption.new("curve_left", false))
    assert(layout.next_checkpoint_index() == -1)
    layout.append(BuildOption.new("uphill", true))
    assert(layout.next_checkpoint_index() == 2)

func test_global_progress_uses_distance_units_only() -> void:
    var layout := TrackLayout.with_initial_straight()
    layout.append(BuildOption.new("straight", true))
    assert(is_equal_approx(layout.global_progress(1, 4.0), 24.0))
```

- [ ] **Step 2: Run and verify the layout test failure**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: `TrackLayout` and `BuildOption` are not defined.

- [ ] **Step 3: Implement the smallest pure layout API**

Create `BuildOption` as a `RefCounted` with `variant_id`, `allows_checkpoint`, `transform`, `length_meters`, and `footprint: AABB`. `TrackLayout` stores ordered piece records and accumulated lengths. Its `get_valid_options()` transforms the four allowed variants at the current end connector, rejects candidates whose expanded `AABB` intersects any existing footprint, and returns only valid candidates. If that list is empty, test the straight candidate once; if still empty return an empty list so the caller can enter `TRACK_BUILD_BLOCKED`.

```gdscript
func global_progress(piece_index: int, local_distance: float) -> float:
    return _length_before_piece(piece_index) + clampf(local_distance, 0.0, pieces[piece_index].length_meters)
```

Increment `pieces_since_last_checkpoint` on each append. Create a checkpoint only on the appended piece when the counter is at least two and that piece allows it; otherwise preserve the counter.

- [ ] **Step 4: Run tests and static parsing**

Run:

```powershell
& $godot --headless --path . -s res://tests/test_runner.gd
& $godot --headless --path . --editor --quit
```

Expected: collision filtering, checkpoint deferral, fallback-empty result, and distance-unit tests pass.

- [ ] **Step 5: Commit track domain logic**

```powershell
git add scripts/domain/build_choice.gd scripts/domain/track_layout.gd tests/test_runner.gd tests/test_track_layout.gd
git commit -m "feat: add validated linear track layout"
```

### Task 4: Build the runtime modular track and movable finish

**Files:**
- Create: `scenes/track/track_piece.tscn`
- Create: `scenes/track/finish.tscn`
- Create: `scripts/track/track_piece.gd`
- Create: `scripts/track/track_manager.gd`
- Create: `tests/test_track_manager.gd`
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Produces: `TrackManager.apply_extension(option: BuildOption) -> bool`, `TrackManager.move_finish(connector: Transform3D) -> void`, and `TrackManager.get_existing_trap_slots() -> Array`.
- Consumes: `TrackLayout`, `TrackPiece`, and one persistent `Finish` node.

- [ ] **Step 1: Write a failing scene-level finish test**

```gdscript
func test_extension_moves_the_same_finish_node_to_new_end() -> void:
    var manager := TrackManager.new()
    manager.create_initial_track()
    var original_finish := manager.finish
    manager.apply_extension(BuildOption.straight())
    assert(manager.finish == original_finish)
    assert(manager.finish.global_transform == manager.current_end_connector)
```

- [ ] **Step 2: Run and verify the expected failure**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: `TrackManager` is not defined.

- [ ] **Step 3: Implement standardized scenes and manager binding**

Give `track_piece.tscn` an `InputConnector`, `OutputConnector`, `ProgressPath`, `SafeRespawnZone`, `TrapSlots`, static collision, and a forward `Area3D` piece gate. Use identical connector width and height conventions for all three pieces. `TrackManager` instantiates the matching scene from a variant catalogue, snaps input to the prior end, updates `TrackLayout`, adds checkpoint/respawn children when instructed by the layout, and calls:

```gdscript
func move_finish(connector: Transform3D) -> void:
    finish.global_transform = connector
    current_end_connector = connector
```

Do not free and recreate `finish`.

- [ ] **Step 4: Run scene tests and launch smoke test**

Run:

```powershell
& $godot --headless --path . -s res://tests/test_runner.gd
& $godot --headless --path . --quit-after 3
```

Expected: finish identity test passes and the main scene starts without parser or missing-node errors.

- [ ] **Step 5: Commit runtime track construction**

```powershell
git add scenes/track scripts/track tests/test_track_manager.gd tests/test_runner.gd
git commit -m "feat: add snapped modular track runtime"
```

### Task 5: Implement secret build choices and persistent trap placement

**Files:**
- Create: `scripts/build/build_manager.gd`
- Create: `scripts/traps/trap_controller.gd`
- Create: `scenes/traps/ice.tscn`
- Create: `scenes/traps/dynamite.tscn`
- Create: `tests/test_build_manager.gd`
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Produces: `BuildManager.begin_secret_phase(round_number: int)`, `submit_extension(player_id: int, option_id: String)`, `submit_modification(player_id: int, trap_id: String, preferred_slot_ids: Array[String])`, and `reveal_and_apply() -> bool`.
- Consumes: `RaceState`, `TrackManager`, existing-slot snapshot, and `TrapController.reset_for_round()`.

- [ ] **Step 1: Write failing secret-choice tests**

```gdscript
func test_modifier_cannot_submit_slot_from_extension_not_present_at_phase_start() -> void:
    manager.begin_secret_phase(1)
    assert(not manager.submit_modification(2, "ice", ["future_piece_slot", "a", "b"]))

func test_dynamite_persists_but_rearms_for_new_racing_phase() -> void:
    var trap := TrapController.new("dynamite")
    trap.trigger()
    assert(not trap.is_armed)
    trap.reset_for_round()
    assert(trap.is_armed)
```

- [ ] **Step 2: Run and verify failure**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: `BuildManager` and `TrapController` are undefined.

- [ ] **Step 3: Implement phase snapshots and trap rules**

At `begin_secret_phase`, snapshot only unoccupied slots from pieces that already exist. Assign builder role to P1 on odd rounds and P2 on even rounds. Lock submissions after `REVEAL`. Install the trap in the first submitted slot that is in the snapshot and unoccupied. Ice has `is_armed = true` continuously; dynamite has `used_this_round` and ignores collisions after its first trigger until `reset_for_round()`.

```gdscript
func reset_for_round() -> void:
    if trap_type == "dynamite":
        is_armed = true
        used_this_round = false
```

- [ ] **Step 4: Run all headless tests**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: snapshot, role alternation, occupied-slot rejection, ice persistence, and dynamite rearm tests pass.

- [ ] **Step 5: Commit build and trap mechanics**

```powershell
git add scripts/build scripts/traps scenes/traps tests/test_build_manager.gd tests/test_runner.gd
git commit -m "feat: add secret construction and persistent traps"
```

### Task 6: Implement two arcade cars, one-shot boost, and split-screen

**Files:**
- Create: `scenes/car/car.tscn`
- Create: `scripts/domain/player_round_state.gd`
- Create: `scripts/car/car_controller.gd`
- Create: `scripts/ui/split_screen_manager.gd`
- Create: `tests/test_round_rules.gd`
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Produces: `PlayerRoundState.reset_for_round()`, `try_consume_boost() -> bool`, `lose_life() -> bool`, and `CarController.configure(player_id: int, input_prefix: String)`.
- Consumes: input actions from Task 1 and `RaceState.phase`.

- [ ] **Step 1: Write failing boost and life tests**

```gdscript
func test_one_boost_charge_is_consumed_once_per_round() -> void:
    var player := PlayerRoundState.new()
    player.reset_for_round()
    assert(player.try_consume_boost())
    assert(not player.try_consume_boost())

func test_lives_reset_between_rounds() -> void:
    var player := PlayerRoundState.new()
    player.reset_for_round()
    player.lose_life()
    player.lose_life()
    player.reset_for_round()
    assert(player.lives == 3)
```

- [ ] **Step 2: Run and verify failure**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: `PlayerRoundState` is undefined.

- [ ] **Step 3: Implement domain state and car presentation**

`PlayerRoundState` owns three lives, `boost_charges`, dead/eliminated state, deaths, and `last_safe_respawn`. `CarController` is a `CharacterBody3D` with acceleration, braking/reverse, steering, light lateral damping, and a two-second velocity multiplier only when `try_consume_boost()` succeeds. Create a `SubViewport` and camera per player; `SplitScreenManager` puts them in equal horizontal screen rectangles and binds P1/P2 input prefixes.

```gdscript
func reset_for_round() -> void:
    lives = 3
    boost_charges = 1
    deaths = 0
    is_dead = false
    is_eliminated = false

func try_consume_boost() -> bool:
    if boost_charges != 1:
        return false
    boost_charges = 0
    return true
```

- [ ] **Step 4: Run tests and manual two-controller smoke check**

Run:

```powershell
& $godot --headless --path . -s res://tests/test_runner.gd
& $godot --path .
```

Expected: headless tests pass; both keyboard mappings can drive distinct cars, and each boost activates once in one round.

- [ ] **Step 5: Commit car controls**

```powershell
git add scenes/car scripts/domain/player_round_state.gd scripts/car scripts/ui tests/test_round_rules.gd tests/test_runner.gd
git commit -m "feat: add local arcade cars and boost"
```

### Task 7: Implement checkpoint/respawn triggers and logical progress

**Files:**
- Create: `scripts/domain/progress_tracker.gd`
- Create: `scripts/track/respawn_point.gd`
- Create: `scripts/track/race_checkpoint.gd`
- Modify: `scripts/track/track_manager.gd`
- Modify: `tests/test_round_rules.gd`

**Interfaces:**
- Produces: `ProgressTracker.record_piece_gate(player_id: int, piece_index: int)`, `global_progress(player_id: int, local_distance: float) -> float`, `try_activate_respawn(player_id: int, point_id: String) -> bool`, and `reset_round_claims() -> void`.
- Consumes: `TrackLayout`, `PlayerRoundState`, and `RaceCheckpoint`/`RespawnPoint` forward Area3D events.

- [ ] **Step 1: Write failing monotonic-trigger tests**

```gdscript
func test_reverse_respawn_crossing_is_ignored_after_forward_activation() -> void:
    tracker.record_piece_gate(1, 2)
    assert(tracker.try_activate_respawn(1, "rp_2"))
    assert(not tracker.try_activate_respawn(1, "rp_2"))

func test_nearby_later_piece_cannot_increase_progress() -> void:
    tracker.record_piece_gate(1, 0)
    assert(is_equal_approx(tracker.global_progress(1, 3.0), 3.0))
```

- [ ] **Step 2: Run and verify failure**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: `ProgressTracker` is undefined.

- [ ] **Step 3: Implement one-way trigger ownership**

Store `activated_respawns_by_player: Dictionary`, `claimed_checkpoints: Dictionary`, and current piece indexes. Let a checkpoint or respawn trigger only when its piece index is the current piece or immediate valid next piece. On a surviving player's first valid respawn activation, update that player's `last_safe_respawn` and respawn any dead opponent with lives at their own saved transform. If both cars are dead, respawn all non-eliminated players at their own saved transforms. Reset checkpoint claims and per-player respawn activations when `RACING` begins.

```gdscript
func try_activate_respawn(player_id: int, point_id: String, point_piece_index: int) -> bool:
    if point_id in activated_respawns_by_player.get(player_id, {}):
        return false
    if point_piece_index < current_piece_index[player_id] or point_piece_index > current_piece_index[player_id] + 1:
        return false
    if not activated_respawns_by_player.has(player_id):
        activated_respawns_by_player[player_id] = {}
    activated_respawns_by_player[player_id][point_id] = true
    return true
```

- [ ] **Step 4: Run headless regression tests**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: forward-only respawn, initial-respawn, checkpoint-claim reset, and path-based progress tests pass.

- [ ] **Step 5: Commit progress and respawn rules**

```powershell
git add scripts/domain/progress_tracker.gd scripts/track tests/test_round_rules.gd
git commit -m "feat: add safe respawns and logical progress"
```

### Task 8: Implement scoring, finish ordering, and full round orchestration

**Files:**
- Create: `scripts/domain/score_manager.gd`
- Modify: `scripts/game/game_controller.gd`
- Modify: `scripts/domain/race_state.gd`
- Modify: `tests/test_round_rules.gd`

**Interfaces:**
- Produces: `ScoreManager.score_results(results: Array, checkpoints_first: Dictionary, deaths: Dictionary) -> Dictionary` and `GameController.finish_round() -> void`.
- Consumes: `RaceState.finish_times`, `ProgressTracker`, `PlayerRoundState`, and build/trap reset hooks.

- [ ] **Step 1: Write failing scoring tests**

```gdscript
func test_finishers_rank_before_non_finishers_by_finish_time() -> void:
    var ranked := ScoreManager.rank([
        {"id": 1, "finish_time": 12.0, "progress": 30.0},
        {"id": 2, "finish_time": -1.0, "progress": 99.0}
    ])
    assert(ranked[0]["id"] == 1)

func test_round_score_awards_no_death_bonus_and_checkpoint_first_only() -> void:
    var scores := ScoreManager.score_results([1, 2], {"cp_1": 1}, {1: 0, 2: 1})
    assert(scores[1] == 6)
```

- [ ] **Step 2: Run and verify failure**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: `ScoreManager` is undefined.

- [ ] **Step 3: Implement the rule table exactly**

Apply +4/+2 for rank one/two, +1 to each finisher, +1 for every checkpoint's first claimant, and +1 to players with zero deaths. Rank first by valid `finish_time`, then `global_progress`, then player id. In `GameController.finish_round`, update match totals, call `RaceState.resolve_match` only after all scoring, then choose `MATCH_END`, `NEXT_ROUND`, or `BUILD_SECRET` as required. `TRACK_BUILD_BLOCKED` enters the same controlled result screen but has no extra build attempt.

```gdscript
func rank(results: Array) -> Array:
    var ranked := results.duplicate()
    ranked.sort_custom(func(a, b):
        var a_finished := a["finish_time"] >= 0.0
        var b_finished := b["finish_time"] >= 0.0
        if a_finished != b_finished:
            return a_finished
        if a_finished and not is_equal_approx(a["finish_time"], b["finish_time"]):
            return a["finish_time"] < b["finish_time"]
        if not is_equal_approx(a["progress"], b["progress"]):
            return a["progress"] > b["progress"]
        return a["id"] < b["id"]
    )
    return ranked
```

- [ ] **Step 4: Run full test suite**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: score totals, 20-point simultaneous evaluation, fifth-round tie breaks, finish ordering, and final-window cap tests pass.

- [ ] **Step 5: Commit orchestrated rounds**

```powershell
git add scripts/domain/score_manager.gd scripts/domain/race_state.gd scripts/game/game_controller.gd tests/test_round_rules.gd
git commit -m "feat: add scoring and round orchestration"
```

### Task 9: Add minimal build, racing, result, and HUD UI; verify the complete playable loop

**Files:**
- Create: `scenes/ui/hud.tscn`
- Create: `scripts/ui/hud.gd`
- Modify: `scenes/main/main.tscn`
- Modify: `scripts/game/game_controller.gd`
- Create: `README.md`

**Interfaces:**
- Produces: one local flow from `BUILD_SECRET` to `MATCH_END`, visible phase/timer/boost/lives/score labels, and a README with control map and verification commands.
- Consumes: all previous managers and signals.

- [ ] **Step 1: Write a failing integration assertion for phase flow**

```gdscript
func test_complete_round_advances_from_build_to_next_round() -> void:
    var game := GameController.new()
    game.start_match()
    game.submit_test_choices()
    game.complete_test_race()
    assert(game.race_state.phase == RaceState.Phase.NEXT_ROUND)
```

- [ ] **Step 2: Run and verify failure**

Run: `& $godot --headless --path . -s res://tests/test_runner.gd`

Expected: the integration helper or transition is missing.

- [ ] **Step 3: Wire only required UI and transitions**

Show the builder's valid variants, the modifier's available existing slots and trap type, a reveal panel, 3-2-1 countdown, split-screen HUD, result ordering, total scores, and `TRACK_BUILD_BLOCKED` results. Disable inputs outside their owning phase. Add test-only helpers only under `tests/`, not production `GameController`.

```gdscript
func _on_phase_changed(phase: RaceState.Phase) -> void:
    build_panel.visible = phase == RaceState.Phase.BUILD_SECRET
    countdown_label.visible = phase == RaceState.Phase.COUNTDOWN
    result_panel.visible = phase == RaceState.Phase.RESULTS or phase == RaceState.Phase.MATCH_END
    hud.visible = phase == RaceState.Phase.RACING or phase == RaceState.Phase.FINAL_WINDOW
```

- [ ] **Step 4: Run automated and manual acceptance verification**

Run:

```powershell
& $godot --headless --path . -s res://tests/test_runner.gd
& $godot --headless --path . --editor --quit
& $godot --path .
git diff --check
```

Manual acceptance: play two rounds with alternating roles; verify moved finish, one boost per player each round, persistent ice/dynamite, respawn from saved safe point, a first finisher's 15-second window, and scores that end the match at 20 or after round five.

- [ ] **Step 5: Commit the playable MVP**

```powershell
git add scenes/main scenes/ui scripts/game scripts/ui README.md tests
git commit -m "feat: deliver local track construction MVP"
```

## Plan self-review

- Spec coverage: Tasks 2 and 8 cover the state flow, time cap, score target, ranking, and five-round cap. Tasks 3 and 4 cover linear snapped pieces, geometry validation, checkpoints, and movable finish. Tasks 5 and 7 cover secret construction, persistent traps, safe respawns, and monotonic triggers. Task 6 covers both cars, split-screen, lives, and boost. Task 9 covers the full player-visible loop.
- Deferred-marker scan: this plan assigns every required production behavior to a named file and task; it uses no deferred features.
- Interface consistency: `RaceState`, `TrackLayout`, `TrackManager`, `BuildManager`, `PlayerRoundState`, `ProgressTracker`, and `ScoreManager` are introduced before their first consuming task.
