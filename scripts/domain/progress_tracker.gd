class_name ProgressTracker
extends RefCounted

signal race_checkpoint_first(checkpoint_id: String, player_id: int)
signal respawn_requested(player_id: int, safe_transform: Transform3D)

var layout
var player_states: Dictionary = {}
var current_piece_indexes: Dictionary = {}
var high_water_progress_by_player: Dictionary = {}
var activated_respawns_by_player: Dictionary = {}
var claimed_checkpoints: Dictionary = {}
var _initial_respawn := Transform3D.IDENTITY

func _init(track_layout = null, players: Dictionary = {}) -> void:
	layout = track_layout
	player_states = players
	for player_id in player_states:
		current_piece_indexes[player_id] = 0
		high_water_progress_by_player[player_id] = 0.0
		activated_respawns_by_player[player_id] = {}

func record_piece_gate(player_id: int, piece_index: int) -> bool:
	if not current_piece_indexes.has(player_id) or layout == null:
		return false
	var current_index: int = current_piece_indexes[player_id]
	if piece_index != current_index + 1 or piece_index >= layout.pieces.size():
		return false
	current_piece_indexes[player_id] = piece_index
	high_water_progress_by_player[player_id] = maxf(
		high_water_progress_by_player.get(player_id, 0.0),
		layout.global_progress(piece_index, 0.0),
	)
	return true

func global_progress(player_id: int, local_distance: float) -> float:
	if layout == null or not current_piece_indexes.has(player_id):
		return 0.0
	var sampled_progress: float = layout.global_progress(current_piece_indexes[player_id], local_distance)
	var high_water: float = maxf(high_water_progress_by_player.get(player_id, 0.0), sampled_progress)
	high_water_progress_by_player[player_id] = high_water
	return high_water

func try_claim_checkpoint(player_id: int, checkpoint_id: String, piece_index: int) -> bool:
	if not _is_valid_trigger_piece(player_id, piece_index) or claimed_checkpoints.has(checkpoint_id):
		return false
	claimed_checkpoints[checkpoint_id] = player_id
	race_checkpoint_first.emit(checkpoint_id, player_id)
	return true

func try_activate_respawn(
	player_id: int,
	point_id: String,
	point_piece_index: int = -1,
	safe_transform: Transform3D = Transform3D.IDENTITY,
) -> bool:
	if point_piece_index < 0:
		point_piece_index = _piece_index_from_id(point_id)
	if not _is_valid_trigger_piece(player_id, point_piece_index):
		return false
	var state = player_states.get(player_id)
	if state == null or state.is_dead or state.is_eliminated:
		return false
	var player_activations: Dictionary = activated_respawns_by_player.get(player_id, {})
	if player_activations.has(point_id):
		return false
	player_activations[point_id] = true
	activated_respawns_by_player[player_id] = player_activations
	state.last_safe_respawn = safe_transform
	for opponent_id in player_states:
		if opponent_id == player_id:
			continue
		var opponent = player_states[opponent_id]
		if opponent.is_dead and not opponent.is_eliminated and opponent.respawn(opponent.last_safe_respawn):
			respawn_requested.emit(opponent_id, opponent.last_safe_respawn)
	return true

func resolve_all_dead() -> bool:
	if player_states.is_empty():
		return false
	for state in player_states.values():
		if not state.is_dead:
			return false
	var eligible_ids: Array = []
	for player_id in player_states:
		if not player_states[player_id].is_eliminated:
			eligible_ids.append(player_id)
	if eligible_ids.is_empty():
		return false
	eligible_ids.sort()
	for player_id in eligible_ids:
		var state = player_states[player_id]
		var safe_transform: Transform3D = state.last_safe_respawn
		if state.respawn(safe_transform):
			respawn_requested.emit(player_id, safe_transform)
	return true

func set_initial_respawn(safe_transform: Transform3D) -> void:
	_initial_respawn = safe_transform
	for state in player_states.values():
		state.last_safe_respawn = safe_transform

func reset_round_claims() -> void:
	claimed_checkpoints.clear()
	for player_id in player_states:
		activated_respawns_by_player[player_id] = {}
		current_piece_indexes[player_id] = 0
		high_water_progress_by_player[player_id] = 0.0
		player_states[player_id].last_safe_respawn = _initial_respawn

func _is_valid_trigger_piece(player_id: int, piece_index: int) -> bool:
	if layout == null or not current_piece_indexes.has(player_id):
		return false
	if piece_index < 0 or piece_index >= layout.pieces.size():
		return false
	var current_index: int = current_piece_indexes[player_id]
	return piece_index == current_index or piece_index == current_index + 1

func _piece_index_from_id(point_id: String) -> int:
	if point_id == "respawn_initial":
		return 0
	var suffix := point_id.get_slice("_", point_id.get_slice_count("_") - 1)
	return suffix.to_int() if suffix.is_valid_int() else -1
