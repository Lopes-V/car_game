class_name GameController
extends Node

const RaceState = preload("res://scripts/domain/race_state.gd")
const ScoreManager = preload("res://scripts/domain/score_manager.gd")
const Constants = preload("res://scripts/domain/race_constants.gd")
const ProgressTracker = preload("res://scripts/domain/progress_tracker.gd")
const BuildManager = preload("res://scripts/build/build_manager.gd")

var race_state
var progress_tracker
var player_states: Dictionary = {}
var build_manager

var total_scores: Dictionary = {1: 0, 2: 0}
var current_ranked_results: Array = []
var current_round_scores: Dictionary = {}
var winner_id := 0
var end_reason := ""

var _round_scored := false
var _terminal_handled := false
var track_manager
var cars: Dictionary = {}
var split_screen
var hud
var _countdown_remaining := 0.0

func _ready() -> void:
	var root := get_parent()
	if root == null or not root.has_node("TrackManager"):
		return
	track_manager = root.get_node("TrackManager")
	track_manager.create_initial_track()
	cars = {1: root.get_node("Player1"), 2: root.get_node("Player2")}
	for player_id in cars:
		var car = cars[player_id]
		car.configure(player_id, "p%d" % player_id)
		player_states[player_id] = car.round_state
	progress_tracker = ProgressTracker.new(track_manager.layout, player_states)
	progress_tracker.respawn_requested.connect(_on_respawn_requested)
	track_manager.configure_progress_tracker(progress_tracker)
	build_manager = BuildManager.new(race_state, track_manager)
	add_child(build_manager)
	build_manager.track_build_blocked.connect(_on_track_build_blocked)
	build_manager.build_applied.connect(_on_build_applied)
	build_manager.choices_revealed.connect(_on_choices_revealed)
	track_manager.finish.get_node("FinishGate").crossed.connect(_on_finish_crossed)
	split_screen = root.get_node("SplitScreenManager")
	split_screen.configure(cars[1], cars[2])
	hud = root.get_node("HUD")
	hud.extension_locked.connect(_on_extension_locked)
	hud.modification_locked.connect(_on_modification_locked)
	hud.reveal_requested.connect(_on_reveal_requested)
	hud.continue_requested.connect(_on_continue_requested)
	start_match()
	_place_cars(Transform3D.IDENTITY)
	_show_build_hud()

func _process(delta: float) -> void:
	if race_state.phase == RaceState.Phase.COUNTDOWN:
		_countdown_remaining = maxf(_countdown_remaining - delta, 0.0)
		if hud != null:
			hud.show_countdown(_countdown_remaining)
		if is_zero_approx(_countdown_remaining):
			start_racing(Time.get_ticks_msec() / 1000.0)
			_set_car_controls(true)
	elif race_state.phase == RaceState.Phase.RACING or race_state.phase == RaceState.Phase.FINAL_WINDOW:
		var now := Time.get_ticks_msec() / 1000.0
		_update_runtime_progress()
		_check_kill_plane()
		if race_state.phase != RaceState.Phase.RACING and race_state.phase != RaceState.Phase.FINAL_WINDOW:
			return
		if hud != null:
			hud.show_race_state(
				"RACING" if race_state.phase == RaceState.Phase.RACING else "FINAL_WINDOW",
				race_state.race_end_time - now,
				player_states,
				total_scores,
			)
		if race_state.should_end_race(now):
			_set_car_controls(false)
			finish_round()
			_show_results()

func _init(
	configured_race_state = null,
	configured_progress_tracker = null,
	configured_player_states: Dictionary = {},
	configured_build_manager = null,
) -> void:
	race_state = configured_race_state if configured_race_state != null else RaceState.new()
	progress_tracker = configured_progress_tracker
	player_states = configured_player_states
	build_manager = configured_build_manager
	if build_manager != null and build_manager.has_signal("track_build_blocked"):
		build_manager.track_build_blocked.connect(_on_track_build_blocked)
	if build_manager != null and build_manager.has_signal("build_applied"):
		build_manager.build_applied.connect(_on_build_applied)

func start_match() -> void:
	total_scores = {1: 0, 2: 0}
	winner_id = 0
	end_reason = ""
	_terminal_handled = false
	_reset_round_results()
	_reset_players(Transform3D.IDENTITY)
	if progress_tracker != null:
		progress_tracker.set_initial_respawn(Transform3D.IDENTITY)
		progress_tracker.reset_round_claims()
	if build_manager != null:
		build_manager.begin_secret_phase(1)
	else:
		race_state.begin_round(1)

func finish_round() -> void:
	if _round_scored or _terminal_handled or race_state.phase != RaceState.Phase.RESULTS:
		return
	_round_scored = true

	var deaths := _snapshot_deaths()
	var results: Array = []
	for player_id in _player_ids():
		results.append({
			"id": player_id,
			"finish_time": float(race_state.finish_times.get(player_id, -1.0)),
			"progress": _snapshot_progress(player_id),
		})
	current_ranked_results = ScoreManager.rank(results)
	var checkpoint_claims: Dictionary = (
		progress_tracker.claimed_checkpoints.duplicate(true)
		if progress_tracker != null
		else {}
	)
	current_round_scores = ScoreManager.score_results(current_ranked_results, checkpoint_claims, deaths)
	for player_id in current_round_scores:
		total_scores[player_id] = int(total_scores.get(player_id, 0)) + int(current_round_scores[player_id])

	var tie_order := ScoreManager.current_round_tie_order(current_ranked_results, deaths)
	winner_id = race_state.resolve_match(total_scores, tie_order)
	if winner_id != 0:
		end_reason = "TARGET_SCORE"
		_terminal_handled = true
		race_state.phase = RaceState.Phase.MATCH_END
		_show_results()
		return
	if race_state.round_number >= Constants.MAX_ROUNDS:
		winner_id = _winner_by_total(tie_order)
		end_reason = "MAX_ROUNDS"
		_terminal_handled = true
		race_state.phase = RaceState.Phase.MATCH_END
		_show_results()
		return
	race_state.phase = RaceState.Phase.NEXT_ROUND
	_show_results()

func begin_next_round(initial_safe_respawn: Transform3D = Transform3D.IDENTITY) -> bool:
	if _terminal_handled or race_state.phase != RaceState.Phase.NEXT_ROUND:
		return false
	var next_round_number: int = race_state.round_number + 1
	_reset_round_results()
	_reset_players(initial_safe_respawn)
	if progress_tracker != null:
		progress_tracker.set_initial_respawn(initial_safe_respawn)
		progress_tracker.reset_round_claims()
	if build_manager != null:
		return build_manager.begin_secret_phase(next_round_number)
	race_state.begin_round(next_round_number)
	return true

func start_racing(now_seconds: float) -> bool:
	if _terminal_handled or race_state.phase != RaceState.Phase.COUNTDOWN:
		return false
	if progress_tracker != null:
		progress_tracker.reset_round_claims()
	if build_manager != null:
		build_manager.reset_traps_for_racing()
	if track_manager != null and track_manager.finish != null:
		track_manager.finish.get_node("FinishGate").reset_for_round()
	race_state.begin_racing(now_seconds)
	if race_state.phase == RaceState.Phase.RACING:
		_set_car_controls(true)
	return race_state.phase == RaceState.Phase.RACING

func handle_track_build_blocked() -> void:
	_on_track_build_blocked()

func _on_build_applied(success: bool) -> void:
	if (
		not success
		or _terminal_handled
		or race_state.phase != RaceState.Phase.APPLY_BUILD
	):
		return
	race_state.phase = RaceState.Phase.COUNTDOWN
	_countdown_remaining = 3.0
	_place_cars(_initial_safe_transform())
	_bind_traps()

func _on_track_build_blocked() -> void:
	if _terminal_handled:
		return
	_terminal_handled = true
	_round_scored = true
	current_ranked_results = []
	current_round_scores = {}
	end_reason = "TRACK_BUILD_BLOCKED"
	race_state.phase = RaceState.Phase.RESULTS
	winner_id = _winner_by_total([])
	race_state.phase = RaceState.Phase.MATCH_END
	_show_results()

func _reset_round_results() -> void:
	_round_scored = false
	current_ranked_results = []
	current_round_scores = {}

func _reset_players(initial_safe_respawn: Transform3D) -> void:
	for state in player_states.values():
		state.reset_for_round(initial_safe_respawn)

func _snapshot_deaths() -> Dictionary:
	var deaths: Dictionary = {}
	for player_id in _player_ids():
		var state = player_states.get(player_id)
		deaths[player_id] = int(state.deaths) if state != null else 0
	return deaths

func _snapshot_progress(player_id: int) -> float:
	if progress_tracker == null:
		return 0.0
	return float(progress_tracker.high_water_progress_by_player.get(player_id, 0.0))

func _player_ids() -> Array:
	var ids: Array = player_states.keys()
	if ids.is_empty():
		ids = total_scores.keys()
	ids.sort()
	return ids

func _winner_by_total(tie_order: Array) -> int:
	var candidates: Array = []
	var highest_score := -1
	for player_id in total_scores:
		var score := int(total_scores[player_id])
		if score > highest_score:
			highest_score = score
			candidates = [int(player_id)]
		elif score == highest_score:
			candidates.append(int(player_id))
	for player_id in tie_order:
		if candidates.has(int(player_id)):
			return int(player_id)
	if candidates.is_empty():
		return 0
	candidates.sort()
	return int(candidates[0])

func _on_extension_locked(option_id: String) -> void:
	build_manager.submit_extension(build_manager.builder_player_id, option_id)

func _on_modification_locked(trap_id: String, slot_ids: Array[String]) -> void:
	if build_manager.submit_modification(build_manager.modifier_player_id, trap_id, slot_ids):
		build_manager.reveal_and_apply()
	elif hud != null:
		hud.show_build_error("Construcao rejeitada: sao necessarios tres slots validos")

func _on_choices_revealed(extension_id: String, trap_id: String) -> void:
	if hud != null:
		hud.show_reveal(extension_id, trap_id)

func _on_reveal_requested() -> void:
	build_manager.reveal_and_apply()

func _on_continue_requested() -> void:
	if begin_next_round(_initial_safe_transform()):
		_restore_car_bodies(_initial_safe_transform())
		_place_cars(_initial_safe_transform())
		_show_build_hud()

func _show_build_hud() -> void:
	if hud == null or build_manager == null:
		return
	hud.set_phase_text("BUILD_SECRET - Rodada %d" % race_state.round_number)
	hud.show_build_state(
		build_manager.builder_player_id,
		build_manager.modifier_player_id,
		build_manager.get_extension_option_ids(),
		build_manager.get_available_slot_ids(),
	)

func _show_results() -> void:
	if hud == null:
		return
	hud.show_results(
		current_ranked_results,
		current_round_scores,
		total_scores,
		winner_id,
		end_reason,
		race_state.phase == RaceState.Phase.NEXT_ROUND,
	)

func _set_car_controls(enabled: bool) -> void:
	for player_id in cars:
		var car = cars[player_id]
		car.controls_enabled = enabled and not car.round_state.is_dead and not car.round_state.is_eliminated and not race_state.finish_times.has(player_id)

func _place_cars(safe_transform: Transform3D) -> void:
	for player_id in cars:
		var car = cars[player_id]
		car.global_transform = safe_transform.translated_local(Vector3(-1.2 if player_id == 1 else 1.2, 1.0, -2.0))
		car.velocity = Vector3.ZERO

func _restore_car_bodies(initial_safe_respawn: Transform3D) -> void:
	for car in cars.values():
		car.reset_for_round(initial_safe_respawn)
		car.visible = true
		car.collision_layer = 1
		car.collision_mask = 1
		car.controls_enabled = false

func _initial_safe_transform() -> Transform3D:
	if track_manager == null:
		return Transform3D.IDENTITY
	var initial = track_manager.get_node_or_null("InitialRespawnPoint")
	return initial.safe_transform if initial != null else Transform3D.IDENTITY

func _bind_traps() -> void:
	if track_manager == null:
		return
	for slot in track_manager.get_existing_trap_slots():
		for child in slot.get_children():
			if child.has_signal("triggered") and not child.triggered.is_connected(_on_trap_triggered):
				child.triggered.connect(_on_trap_triggered)

func _on_finish_crossed(player_id: int) -> void:
	if race_state.phase != RaceState.Phase.RACING and race_state.phase != RaceState.Phase.FINAL_WINDOW:
		return
	race_state.record_finish(player_id, Time.get_ticks_msec() / 1000.0)
	if cars.has(player_id) and race_state.finish_times.has(player_id):
		cars[player_id].controls_enabled = false

func _on_trap_triggered(player_id: int, trap_type: String) -> void:
	if not cars.has(player_id) or (race_state.phase != RaceState.Phase.RACING and race_state.phase != RaceState.Phase.FINAL_WINDOW):
		return
	if trap_type == "ice":
		cars[player_id].apply_low_grip()
	elif trap_type == "dynamite":
		_kill_player(player_id)

func _kill_player(player_id: int) -> void:
	var state = player_states.get(player_id)
	if state == null or state.is_dead or state.is_eliminated:
		return
	state.lose_life()
	var car = cars.get(player_id)
	if car != null:
		car.controls_enabled = false
		car.visible = false
		car.velocity = Vector3.ZERO
		car.collision_layer = 0
		car.collision_mask = 0
	var all_dead := true
	var all_eliminated := true
	for other_state in player_states.values():
		all_dead = all_dead and other_state.is_dead
		all_eliminated = all_eliminated and other_state.is_eliminated
	if all_eliminated:
		race_state.phase = RaceState.Phase.RESULTS
		_set_car_controls(false)
		finish_round()
	elif all_dead:
		progress_tracker.resolve_all_dead()

func _on_respawn_requested(player_id: int, safe_transform: Transform3D) -> void:
	var car = cars.get(player_id)
	if car == null:
		return
	var lane_x := -1.2 if player_id == 1 else 1.2
	car.global_transform = safe_transform.translated_local(Vector3(lane_x, 1.0, 0.0))
	car.velocity = Vector3.ZERO
	car.visible = true
	car.collision_layer = 1
	car.collision_mask = 1
	car.controls_enabled = (
		race_state.phase == RaceState.Phase.RACING or race_state.phase == RaceState.Phase.FINAL_WINDOW
	) and not race_state.finish_times.has(player_id)

func _check_kill_plane() -> void:
	for player_id in cars:
		if cars[player_id].global_position.y < -15.0:
			_kill_player(player_id)

func _update_runtime_progress() -> void:
	if progress_tracker == null or track_manager == null:
		return
	for player_id in cars:
		var piece_index := int(progress_tracker.current_piece_indexes.get(player_id, 0))
		var piece = track_manager.get_piece(piece_index)
		if piece == null:
			continue
		var path := piece.get_node("ProgressPath") as Path3D
		if path == null or path.curve == null:
			continue
		var local_point := path.to_local(cars[player_id].global_position)
		progress_tracker.global_progress(player_id, path.curve.get_closest_offset(local_point))
