extends SceneTree

const SUITES := [
	"res://tests/test_race_state.gd",
	"res://tests/test_track_layout.gd",
	"res://tests/test_track_manager.gd",
	"res://tests/test_build_manager.gd",
	"res://tests/test_round_rules.gd",
	"res://tests/test_playable_mvp.gd",
	"res://tests/test_find_godot.gd",
]

func _init() -> void:
	call_deferred("_run_suites")

func _run_suites() -> void:
	var failed_suite_count := 0
	for suite_path in SUITES:
		var suite_script = load(suite_path)
		if suite_script == null:
			push_error("Unable to load test suite: %s" % suite_path)
			failed_suite_count += 1
			continue

		var suite = suite_script.new()
		if suite == null or not suite.has_method("run"):
			push_error("Invalid test suite: %s" % suite_path)
			failed_suite_count += 1
			continue

		if await suite.run() != true:
			failed_suite_count += 1

	quit(0 if failed_suite_count == 0 else 1)
