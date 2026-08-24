class_name TrapController
extends Area3D

signal triggered(player_id: int, trap_type: String)

const CarController = preload("res://scripts/car/car_controller.gd")

@export_enum("ice", "dynamite") var trap_type := "ice"
var is_armed := true
var used_this_round := false

func _init(configured_trap_type: String = "ice") -> void:
	trap_type = configured_trap_type

func _ready() -> void:
	body_entered.connect(handle_body_crossing)

func handle_body_crossing(body: Node3D) -> bool:
	if not body is CarController or body.player_id <= 0 or not try_trigger():
		return false
	triggered.emit(body.player_id, trap_type)
	return true

func try_trigger() -> bool:
	if trap_type == "ice":
		is_armed = true
		return true
	if trap_type != "dynamite" or not is_armed or used_this_round:
		return false
	used_this_round = true
	is_armed = false
	return true

func reset_for_round() -> void:
	if trap_type == "dynamite":
		is_armed = true
		used_this_round = false
	elif trap_type == "ice":
		is_armed = true
