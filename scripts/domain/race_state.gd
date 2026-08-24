class_name RaceState
extends RefCounted

const Constants = preload("res://scripts/domain/race_constants.gd")

signal phase_changed(previous: int, current: int)

enum Phase { BUILD_SECRET, REVEAL, APPLY_BUILD, COUNTDOWN, RACING, FINAL_WINDOW, RESULTS, NEXT_ROUND, MATCH_END }

var phase: Phase = Phase.BUILD_SECRET:
	set(next_phase):
		if phase == next_phase:
			return
		var previous := phase
		phase = next_phase
		phase_changed.emit(previous, next_phase)

var round_number := 0
var race_end_time := 0.0
var finish_times: Dictionary = {}

func begin_round(next_round_number: int) -> void:
	round_number = next_round_number
	race_end_time = 0.0
	finish_times.clear()
	phase = Phase.BUILD_SECRET

func begin_racing(now_seconds: float) -> void:
	if phase == Phase.RACING:
		return
	phase = Phase.RACING
	race_end_time = now_seconds + Constants.ROUND_TIME_SECONDS

func record_finish(player_id: int, now_seconds: float) -> void:
	if phase != Phase.RACING and phase != Phase.FINAL_WINDOW:
		return
	if now_seconds > race_end_time:
		return
	if player_id in finish_times:
		return
	finish_times[player_id] = now_seconds
	if phase == Phase.RACING:
		phase = Phase.FINAL_WINDOW
		race_end_time = min(race_end_time, now_seconds + Constants.FINAL_WINDOW_SECONDS)

func should_end_race(now_seconds: float) -> bool:
	if phase != Phase.RACING and phase != Phase.FINAL_WINDOW:
		return false
	if now_seconds < race_end_time:
		return false
	phase = Phase.RESULTS
	return true

func resolve_match(scores: Dictionary) -> int:
	if phase != Phase.RESULTS and phase != Phase.MATCH_END:
		return 0

	var winner_id := 0
	var highest_score := Constants.TARGET_SCORE - 1
	for player_id in scores:
		var score = scores[player_id]
		if score >= Constants.TARGET_SCORE and score > highest_score:
			highest_score = score
			winner_id = player_id
		elif score >= Constants.TARGET_SCORE and score == highest_score:
			winner_id = 0
	return winner_id
