class_name FinishGate
extends Area3D

signal crossed(player_id: int)

const FORWARD_EPSILON := 0.01
const CarController = preload("res://scripts/car/car_controller.gd")

var _crossed_players: Dictionary = {}

func _ready() -> void:
	body_entered.connect(handle_body_crossing)

func handle_body_crossing(body: Node3D) -> bool:
	if not body is CarController or body.player_id <= 0 or _crossed_players.has(body.player_id):
		return false
	var forward := (global_basis * Vector3.FORWARD).normalized()
	if body.velocity.dot(forward) <= FORWARD_EPSILON:
		return false
	_crossed_players[body.player_id] = true
	crossed.emit(body.player_id)
	return true

func reset_for_round() -> void:
	_crossed_players.clear()
