class_name RaceCheckpoint
extends Area3D

signal crossed(player_id: int, checkpoint_id: String, piece_index: int)

const FORWARD_EPSILON := 0.01
const CarController = preload("res://scripts/car/car_controller.gd")

@export var checkpoint_id := ""
@export var piece_index := -1
var progress_tracker

func _ready() -> void:
	body_entered.connect(handle_body_crossing)

func configure(id: String, index: int, tracker = null) -> void:
	checkpoint_id = id
	piece_index = index
	progress_tracker = tracker

func handle_body_crossing(body: Node3D) -> bool:
	var player_id := _forward_player_id(body)
	if player_id <= 0 or progress_tracker == null:
		return false
	var claimed: bool = progress_tracker.try_claim_checkpoint(player_id, checkpoint_id, piece_index)
	if claimed:
		crossed.emit(player_id, checkpoint_id, piece_index)
	return claimed

func _forward_player_id(body: Node3D) -> int:
	if not body is CarController:
		return 0
	var player_value: int = body.player_id
	if player_value <= 0:
		return 0
	var forward := (global_basis * Vector3.FORWARD).normalized()
	return player_value if body.velocity.dot(forward) > FORWARD_EPSILON else 0
