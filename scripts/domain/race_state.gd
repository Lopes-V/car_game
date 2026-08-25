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
	if phase != Phase.COUNTDOWN:
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

func resolve_match(scores: Dictionary, tie_order: Array = []) -> int:
	if phase != Phase.RESULTS and phase != Phase.MATCH_END:
		return 0

	var highest_score := Constants.TARGET_SCORE - 1
	var candidates: Array = []
	for player_id in scores:
		var score: int = int(scores[player_id])
		if score < Constants.TARGET_SCORE:
			continue
		if score > highest_score:
			highest_score = score
			candidates = [int(player_id)]
		elif score == highest_score:
			candidates.append(int(player_id))
	if candidates.is_empty():
		return 0
	for player_id in tie_order:
		if candidates.has(int(player_id)):
			return int(player_id)
	candidates.sort()
	return int(candidates[0])
