extends RefCounted

const State = preload("res://scripts/domain/race_state.gd")

func run() -> bool:
	var main_scene = load("res://scenes/main/main.tscn") as PackedScene
	if main_scene == null:
		push_error("Main scene could not be loaded.")
		return false

	var main_instance = main_scene.instantiate()
	if not main_instance is Node3D:
		push_error("Main scene root must be a Node3D.")
		main_instance.free()
		return false

	var game_controller = main_instance.get_node_or_null("GameController")
	if game_controller == null:
		push_error("Main scene must contain a GameController child.")
		main_instance.free()
		return false
	if not game_controller.has_method("start_match"):
		push_error("GameController must expose start_match().")
		main_instance.free()
		return false

	var expected_bindings := {
		"p1_accelerate": KEY_W,
		"p1_brake": KEY_S,
		"p1_left": KEY_A,
		"p1_right": KEY_D,
		"p2_accelerate": KEY_UP,
		"p2_brake": KEY_DOWN,
		"p2_left": KEY_LEFT,
		"p2_right": KEY_RIGHT,
		"p2_boost": KEY_ENTER,
	}
	for action_name in expected_bindings:
		if not _has_key_binding(action_name, expected_bindings[action_name]):
			push_error("Input action is missing its expected binding: %s" % action_name)
			main_instance.free()
			return false
	if not _has_key_binding("p1_boost", KEY_NONE, KEY_SHIFT, KEY_LOCATION_LEFT):
		push_error("P1 boost must be bound to Left Shift.")
		main_instance.free()
		return false

	main_instance.free()
	return (
		test_first_finish_caps_final_window_at_hard_limit()
		and test_duplicate_finish_keeps_first_recorded_time()
		and test_race_ends_at_deadline_and_enters_results()
		and test_target_score_is_evaluated_only_after_results()
		and test_phase_changed_emits_only_for_real_transitions()
		and test_begin_round_resets_round_state()
	)

func test_first_finish_caps_final_window_at_hard_limit() -> bool:
	var state := State.new()
	state.begin_racing(0.0)
	state.record_finish(1, 119.0)
	return (
		_expect(state.phase == State.Phase.FINAL_WINDOW, "First finish must enter FINAL_WINDOW.")
		and _expect(is_equal_approx(state.race_end_time, 120.0), "Final window must be capped by the 120-second hard limit.")
	)

func test_duplicate_finish_keeps_first_recorded_time() -> bool:
	var state := State.new()
	state.begin_racing(0.0)
	state.record_finish(1, 10.0)
	state.record_finish(1, 11.0)
	return _expect(is_equal_approx(state.finish_times[1], 10.0), "A duplicate finish must keep the first finish time.")

func test_race_ends_at_deadline_and_enters_results() -> bool:
	var state := State.new()
	state.begin_racing(0.0)
	return (
		_expect(not state.should_end_race(119.9), "Race must continue before its deadline.")
		and _expect(state.should_end_race(120.0), "Race must end at its deadline.")
		and _expect(state.phase == State.Phase.RESULTS, "Ending a race must enter RESULTS.")
		and _expect(not state.should_end_race(121.0), "A completed race must not end twice.")
	)

func test_target_score_is_evaluated_only_after_results() -> bool:
	var state := State.new()
	state.begin_round(3)
	state.begin_racing(0.0)
	if not _expect(state.resolve_match({1: 21, 2: 22}) == 0, "Scores must not resolve a match during RACING."):
		return false
	state.phase = State.Phase.RESULTS
	return (
		_expect(state.resolve_match({1: 19, 2: 20}) == 2, "The higher target-reaching score must win after RESULTS.")
		and _expect(state.resolve_match({1: 19, 2: 18}) == 0, "No match must resolve when neither score reaches target.")
	)

func test_phase_changed_emits_only_for_real_transitions() -> bool:
	var observed_changes: Array[Dictionary] = []
	var state := State.new()
	state.phase_changed.connect(func(previous: int, current: int) -> void:
		observed_changes.append({"previous": previous, "current": current})
	)
	state.begin_round(1)
	state.begin_racing(0.0)
	state.begin_racing(1.0)
	state.record_finish(1, 10.0)
	state.should_end_race(25.0)
	return (
		_expect(observed_changes.size() == 3, "phase_changed must emit only when the phase changes.")
		and _expect(observed_changes[0] == {"previous": State.Phase.BUILD_SECRET, "current": State.Phase.RACING}, "RACING transition signal must carry old and new phases.")
		and _expect(observed_changes[2] == {"previous": State.Phase.FINAL_WINDOW, "current": State.Phase.RESULTS}, "RESULTS transition signal must carry old and new phases.")
	)

func test_begin_round_resets_round_state() -> bool:
	var state := State.new()
	state.begin_racing(0.0)
	state.record_finish(1, 10.0)
	state.begin_round(2)
	return (
		_expect(state.round_number == 2, "begin_round must store the requested round number.")
		and _expect(state.phase == State.Phase.BUILD_SECRET, "begin_round must return to BUILD_SECRET.")
		and _expect(state.finish_times.is_empty(), "begin_round must clear prior finish times.")
		and _expect(is_zero_approx(state.race_end_time), "begin_round must clear the prior race deadline.")
	)

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false

func _has_key_binding(
	action_name: StringName,
	keycode: Key,
	physical_keycode: Key = KEY_NONE,
	location: KeyLocation = KEY_LOCATION_UNSPECIFIED,
) -> bool:
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey \
				and event.keycode == keycode \
				and event.physical_keycode == physical_keycode \
				and event.location == location:
			return true
	return false
