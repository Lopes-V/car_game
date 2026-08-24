class_name TrackManager
extends Node3D

const BuildOption = preload("res://scripts/domain/build_choice.gd")
const TrackLayout = preload("res://scripts/domain/track_layout.gd")
const TRACK_PIECE_SCENE = preload("res://scenes/track/track_piece.tscn")
const FINISH_SCENE = preload("res://scenes/track/finish.tscn")
const RaceCheckpoint = preload("res://scripts/track/race_checkpoint.gd")
const RespawnPoint = preload("res://scripts/track/respawn_point.gd")
const CarController = preload("res://scripts/car/car_controller.gd")
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
var progress_tracker

func create_initial_track() -> void:
	if layout != null:
		return
	layout = TrackLayout.with_initial_straight()
	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)
	_instantiate_piece(layout.pieces[0], 0)
	_add_initial_respawn_point()
	finish = FINISH_SCENE.instantiate()
	finish.name = "Finish"
	add_child(finish)
	move_finish(layout.pieces[0].output_transform)

func configure_progress_tracker(tracker) -> void:
	progress_tracker = tracker
	var initial = get_node_or_null("InitialRespawnPoint")
	if initial != null:
		initial.progress_tracker = tracker
		tracker.set_initial_respawn(initial.safe_transform)
	if pieces_root != null:
		for piece in pieces_root.get_children():
			_bind_progress_tracker(piece, tracker)

func apply_extension(option: BuildOption) -> bool:
	if layout == null or option == null:
		return false
	var accepted_option: BuildOption
	for valid_option in layout.get_valid_options():
		if _options_match(option, valid_option):
			accepted_option = valid_option
			break
	if accepted_option == null:
		return false
	layout.append(accepted_option)
	var new_piece_index := layout.pieces.size() - 1
	var piece: Node3D = _instantiate_piece(accepted_option, new_piece_index)
	if layout.next_checkpoint_index() == new_piece_index:
		_add_checkpoint_nodes(piece, new_piece_index)
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

func occupy_trap_slot(slot_id: String, trap: Node3D) -> bool:
	if trap == null or trap.get_parent() != null:
		return false
	for slot in get_existing_trap_slots():
		if slot.get_meta("slot_id", "") != slot_id:
			continue
		if slot.get_meta("occupied", false) == true:
			return false
		slot.add_child(trap)
		trap.transform = Transform3D.IDENTITY
		slot.set_meta("occupied", true)
		return true
	return false

func _instantiate_piece(option: BuildOption, piece_index: int) -> Node3D:
	var piece_scene: PackedScene = VARIANT_CATALOGUE[option.variant_id]
	var piece = piece_scene.instantiate()
	pieces_root.add_child(piece)
	piece.configure(option, piece_index)
	var output_gate: Area3D = piece.get_node("OutputGate")
	output_gate.body_entered.connect(_on_output_gate_body_entered.bind(piece_index, output_gate))
	return piece

func _add_initial_respawn_point() -> void:
	var initial := RespawnPoint.new()
	initial.name = "InitialRespawnPoint"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 3.0, 0.4)
	collision.shape = shape
	initial.add_child(collision)
	add_child(initial)
	initial.configure("respawn_initial", 0, progress_tracker, initial.global_transform)

func _add_checkpoint_nodes(piece: Node3D, piece_index: int) -> void:
	var safe_zone: Area3D = piece.get_node("SafeRespawnZone")
	var checkpoint := RaceCheckpoint.new()
	checkpoint.name = "RaceCheckpoint"
	checkpoint.transform = Transform3D.IDENTITY
	var checkpoint_collision := CollisionShape3D.new()
	checkpoint_collision.name = "CollisionShape3D"
	var checkpoint_shape := BoxShape3D.new()
	checkpoint_shape.size = Vector3(6.0, 3.0, 0.4)
	checkpoint_collision.shape = checkpoint_shape
	checkpoint.add_child(checkpoint_collision)
	safe_zone.add_child(checkpoint)
	checkpoint.configure("checkpoint_%d" % piece_index, piece_index, progress_tracker)

	var respawn_point := RespawnPoint.new()
	respawn_point.name = "RespawnPoint"
	respawn_point.transform = Transform3D.IDENTITY
	var respawn_collision := CollisionShape3D.new()
	var respawn_shape := BoxShape3D.new()
	respawn_shape.size = Vector3(6.0, 3.0, 0.4)
	respawn_collision.shape = respawn_shape
	respawn_point.add_child(respawn_collision)
	safe_zone.add_child(respawn_point)
	respawn_point.configure("respawn_%d" % piece_index, piece_index, progress_tracker, respawn_point.global_transform)

func _on_output_gate_body_entered(body: Node3D, piece_index: int, gate: Area3D) -> void:
	if progress_tracker == null or not body is CarController:
		return
	var player_value: int = body.player_id
	if player_value <= 0:
		return
	var forward := (gate.global_basis * Vector3.FORWARD).normalized()
	if body.velocity.dot(forward) <= 0.01:
		return
	progress_tracker.record_piece_gate(player_value, piece_index + 1)

func _bind_progress_tracker(node: Node, tracker) -> void:
	if node is RaceCheckpoint or node is RespawnPoint:
		node.progress_tracker = tracker
	for child in node.get_children():
		_bind_progress_tracker(child, tracker)

func _options_match(candidate: BuildOption, valid_option: BuildOption) -> bool:
	return (
		candidate.variant_id == valid_option.variant_id
		and candidate.allows_checkpoint == valid_option.allows_checkpoint
		and candidate.transform == valid_option.transform
		and candidate.output_transform == valid_option.output_transform
		and candidate.length_meters == valid_option.length_meters
		and candidate.footprint == valid_option.footprint
	)
