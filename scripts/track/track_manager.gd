class_name TrackManager
extends Node3D

const BuildOption = preload("res://scripts/domain/build_choice.gd")
const TrackLayout = preload("res://scripts/domain/track_layout.gd")
const TRACK_PIECE_SCENE = preload("res://scenes/track/track_piece.tscn")
const FINISH_SCENE = preload("res://scenes/track/finish.tscn")
const VARIANT_CATALOGUE := {
	"straight": TRACK_PIECE_SCENE,
	"curve_left": TRACK_PIECE_SCENE,
	"curve_right": TRACK_PIECE_SCENE,
	"uphill": TRACK_PIECE_SCENE,
}

var layout: TrackLayout
var pieces_root: Node3D
var finish: Node3D
var current_end_connector := Transform3D.IDENTITY

func create_initial_track() -> void:
	if layout != null:
		return
	layout = TrackLayout.with_initial_straight()
	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)
	_instantiate_piece(layout.pieces[0], 0)
	finish = FINISH_SCENE.instantiate()
	finish.name = "Finish"
	add_child(finish)
	move_finish(layout.pieces[0].output_transform)

func apply_extension(option: BuildOption) -> bool:
	if layout == null or option == null:
		return false
	var accepted_option: BuildOption
	for valid_option in layout.get_valid_options():
		if _options_match(option, valid_option):
			accepted_option = option
			break
	if accepted_option == null:
		return false
	layout.append(accepted_option)
	var new_piece_index := layout.pieces.size() - 1
	var piece: Node3D = _instantiate_piece(accepted_option, new_piece_index)
	if layout.next_checkpoint_index() == new_piece_index:
		_add_checkpoint_metadata(piece, new_piece_index)
	move_finish(accepted_option.output_transform)
	return true

func move_finish(connector: Transform3D) -> void:
	finish.global_transform = connector
	current_end_connector = connector

func get_existing_trap_slots() -> Array:
	var slots: Array = []
	if pieces_root == null:
		return slots
	for piece in pieces_root.get_children():
		for slot in piece.get_trap_slots():
			slots.append(slot)
	return slots

func _instantiate_piece(option: BuildOption, piece_index: int) -> Node3D:
	var piece_scene: PackedScene = VARIANT_CATALOGUE[option.variant_id]
	var piece = piece_scene.instantiate()
	pieces_root.add_child(piece)
	piece.configure(option, piece_index)
	return piece

func _add_checkpoint_metadata(piece: Node3D, piece_index: int) -> void:
	var safe_zone: Area3D = piece.get_node("SafeRespawnZone")
	var checkpoint := Area3D.new()
	checkpoint.name = "RaceCheckpoint"
	checkpoint.set_meta("piece_index", piece_index)
	var checkpoint_collision := CollisionShape3D.new()
	checkpoint_collision.name = "CollisionShape3D"
	var checkpoint_shape := BoxShape3D.new()
	checkpoint_shape.size = Vector3(6.0, 3.0, 0.4)
	checkpoint_collision.shape = checkpoint_shape
	checkpoint.add_child(checkpoint_collision)
	safe_zone.add_child(checkpoint)

	var respawn_point := Marker3D.new()
	respawn_point.name = "RespawnPoint"
	respawn_point.set_meta("piece_index", piece_index)
	safe_zone.add_child(respawn_point)

func _options_match(candidate: BuildOption, valid_option: BuildOption) -> bool:
	return (
		candidate.variant_id == valid_option.variant_id
		and candidate.allows_checkpoint == valid_option.allows_checkpoint
		and candidate.transform.is_equal_approx(valid_option.transform)
		and candidate.output_transform.is_equal_approx(valid_option.output_transform)
		and is_equal_approx(candidate.length_meters, valid_option.length_meters)
		and candidate.footprint.position.is_equal_approx(valid_option.footprint.position)
		and candidate.footprint.size.is_equal_approx(valid_option.footprint.size)
	)
