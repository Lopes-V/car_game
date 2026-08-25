class_name TrackLayout
extends RefCounted

const BuildOption = preload("res://scripts/domain/build_choice.gd")
const Constants = preload("res://scripts/domain/race_constants.gd")

var pieces: Array[BuildOption] = []
var pieces_since_last_checkpoint := 0

var _current_end_connector := Transform3D.IDENTITY
var _checkpoint_index_for_last_append := -1
var _accumulated_lengths_before_piece: Array[float] = []

static func with_initial_straight():
	var layout = new()
	var initial_piece := BuildOption.new("straight", true, Transform3D.IDENTITY)
	layout.pieces.append(initial_piece)
	layout._accumulated_lengths_before_piece.append(0.0)
	layout._current_end_connector = initial_piece.output_transform
	layout.pieces_since_last_checkpoint = 1
	return layout

func get_valid_options() -> Array[BuildOption]:
	var valid_options: Array[BuildOption] = []
	for variant in Constants.TRACK_VARIANTS:
		var candidate := BuildOption.new(
			variant["variant_id"],
			variant["allows_checkpoint"],
			_current_end_connector,
		)
		if _is_candidate_valid(candidate):
			valid_options.append(candidate)

	if not valid_options.is_empty():
		return valid_options

	var straight_fallback := BuildOption.new("straight", true, _current_end_connector)
	if _is_candidate_valid(straight_fallback):
		valid_options.append(straight_fallback)
	return valid_options

func append(option: BuildOption) -> void:
	var length_before_option := 0.0
	if not pieces.is_empty():
		length_before_option = _accumulated_lengths_before_piece[-1] + pieces[-1].length_meters
	_accumulated_lengths_before_piece.append(length_before_option)
	pieces.append(option)
	_current_end_connector = option.output_transform
	pieces_since_last_checkpoint += 1
	_checkpoint_index_for_last_append = -1
	if pieces_since_last_checkpoint >= 2 and option.allows_checkpoint:
		_checkpoint_index_for_last_append = pieces.size() - 1
		pieces_since_last_checkpoint = 0

func next_checkpoint_index() -> int:
	return _checkpoint_index_for_last_append

func global_progress(piece_index: int, local_distance: float) -> float:
	return _accumulated_lengths_before_piece[piece_index] + clampf(local_distance, 0.0, pieces[piece_index].length_meters)

func _is_candidate_valid(candidate: BuildOption) -> bool:
	for piece in pieces:
		if _has_positive_xz_intersection(candidate.footprint, piece.footprint):
			return false
	return true

func _has_positive_xz_intersection(first: AABB, second: AABB) -> bool:
	var overlap := first.end.min(second.end) - first.position.max(second.position)
	return overlap.x > 0.0 and overlap.z > 0.0
