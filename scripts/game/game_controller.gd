class_name GameController
extends Node

const RaceState = preload("res://scripts/domain/race_state.gd")
const ScoreManager = preload("res://scripts/domain/score_manager.gd")
const Constants = preload("res://scripts/domain/race_constants.gd")

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
		return
	if race_state.round_number >= Constants.MAX_ROUNDS:
		winner_id = _winner_by_total(tie_order)
		end_reason = "MAX_ROUNDS"
		_terminal_handled = true
		race_state.phase = RaceState.Phase.MATCH_END
		return
	race_state.phase = RaceState.Phase.NEXT_ROUND

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
	race_state.begin_racing(now_seconds)
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
