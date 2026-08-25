class_name ScoreManager
extends RefCounted

const FIRST_PLACE_POINTS := 4
const SECOND_PLACE_POINTS := 2
const FINISH_POINTS := 1
const CHECKPOINT_POINTS := 1
const SURVIVAL_POINTS := 1

static func rank(results: Array) -> Array:
	var ranked := results.duplicate(true)
	ranked.sort_custom(func(a, b) -> bool:
		var a_finished: bool = float(a.get("finish_time", -1.0)) >= 0.0
		var b_finished: bool = float(b.get("finish_time", -1.0)) >= 0.0
		if a_finished != b_finished:
			return a_finished
		if a_finished:
			if not is_equal_approx(float(a["finish_time"]), float(b["finish_time"])):
				return float(a["finish_time"]) < float(b["finish_time"])
			return int(a["id"]) < int(b["id"])
		if not is_equal_approx(float(a.get("progress", 0.0)), float(b.get("progress", 0.0))):
			return float(a.get("progress", 0.0)) > float(b.get("progress", 0.0))
		return int(a["id"]) < int(b["id"])
	)
	return ranked

static func score_results(results: Array, checkpoints_first: Dictionary, deaths: Dictionary) -> Dictionary:
	var scores: Dictionary = {}
	for rank_index in results.size():
		var entry = results[rank_index]
		var player_id: int = int(entry["id"]) if entry is Dictionary else int(entry)
		var finished: bool = entry is Dictionary and float(entry.get("finish_time", -1.0)) >= 0.0
		var points := FIRST_PLACE_POINTS if rank_index == 0 else SECOND_PLACE_POINTS if rank_index == 1 else 0
		if finished:
			points += FINISH_POINTS
		if int(deaths.get(player_id, 0)) == 0:
			points += SURVIVAL_POINTS
		scores[player_id] = points

	for claimant in checkpoints_first.values():
		var player_id := int(claimant)
		if scores.has(player_id):
			scores[player_id] += CHECKPOINT_POINTS
	return scores

static func current_round_tie_order(ranked_results: Array, deaths: Dictionary) -> Array:
	var ordered: Array = []
	for result in ranked_results:
		ordered.append({
			"id": int(result["id"]),
			"finish_time": float(result.get("finish_time", -1.0)),
			"progress": float(result.get("progress", 0.0)),
			"deaths": int(deaths.get(int(result["id"]), 0)),
		})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_finished: bool = a["finish_time"] >= 0.0
		var b_finished: bool = b["finish_time"] >= 0.0
		if a_finished != b_finished:
			return a_finished
		if a_finished and not is_equal_approx(a["finish_time"], b["finish_time"]):
			return a["finish_time"] < b["finish_time"]
		if not is_equal_approx(a["progress"], b["progress"]):
			return a["progress"] > b["progress"]
		if a["deaths"] != b["deaths"]:
			return a["deaths"] < b["deaths"]
		return a["id"] < b["id"]
	)
	var ids: Array = []
	for entry in ordered:
		ids.append(entry["id"])
	return ids
