class_name CarController
extends CharacterBody3D

const PlayerState = preload("res://scripts/domain/player_round_state.gd")

@export var acceleration := 30.0
@export var braking := 40.0
@export var reverse_speed := 10.0
@export var forward_speed := 28.0
@export var steering_speed := 1.8
@export var lateral_damping := 8.0
@export var coasting_deceleration := 6.0
@export var boost_duration := 2.0
@export var boost_multiplier := 1.6

var player_id := 0
var input_prefix := ""
var controls_enabled := false:
	set(next_enabled):
		controls_enabled = next_enabled
		if not controls_enabled:
			_clear_active_boost()
var round_state: PlayerState
var boost_time_remaining := 0.0
var low_grip_time_remaining := 0.0

var _boost_was_pressed := false

func _ready() -> void:
	_apply_player_color()

func configure(next_player_id: int, next_input_prefix: String) -> void:
	player_id = next_player_id
	input_prefix = next_input_prefix
	if round_state == null:
		round_state = PlayerState.new()
		round_state.reset_for_round()
	_apply_player_color()

func reset_for_round(initial_safe_respawn: Transform3D = Transform3D.IDENTITY) -> void:
	if round_state == null:
		round_state = PlayerState.new()
	round_state.reset_for_round(initial_safe_respawn)
	velocity = Vector3.ZERO
	controls_enabled = false
	low_grip_time_remaining = 0.0
	_boost_was_pressed = _is_action_pressed("boost")

func _physics_process(delta: float) -> void:
	var boost_pressed := _is_action_pressed("boost")
	var accepts_input := (
		controls_enabled
		and round_state != null
		and not round_state.is_dead
		and not round_state.is_eliminated
	)
	if not accepts_input:
		_clear_active_boost()
		_boost_was_pressed = boost_pressed
		return

	var boost_activated := false
	if boost_pressed and not _boost_was_pressed and round_state.try_consume_boost():
		boost_time_remaining = boost_duration
		boost_activated = true
	_boost_was_pressed = boost_pressed

	var speed_scale := boost_multiplier if boost_time_remaining > 0.0 else 1.0
	var local_velocity := global_transform.basis.inverse() * velocity
	var forward_velocity := -local_velocity.z
	if boost_activated and forward_velocity > 0.0:
		forward_velocity = minf(forward_velocity * boost_multiplier, forward_speed * boost_multiplier)
	var accelerate_strength := Input.get_action_strength(_action_name("accelerate"))
	var brake_strength := Input.get_action_strength(_action_name("brake"))
	if accelerate_strength > 0.0:
		forward_velocity = move_toward(
			forward_velocity,
			forward_speed * speed_scale,
			acceleration * speed_scale * accelerate_strength * delta,
		)
	elif brake_strength > 0.0:
		forward_velocity = move_toward(
			forward_velocity,
			-reverse_speed,
			braking * brake_strength * delta,
		)
	elif boost_time_remaining > 0.0 and forward_velocity >= 0.0:
		forward_velocity = move_toward(
			forward_velocity,
			forward_speed * boost_multiplier,
			acceleration * boost_multiplier * delta,
		)
	else:
		forward_velocity = move_toward(forward_velocity, 0.0, coasting_deceleration * delta)

	var steer_input := Input.get_axis(_action_name("left"), _action_name("right"))
	if not is_zero_approx(forward_velocity):
		var travel_direction := signf(forward_velocity)
		rotate_y(-steer_input * steering_speed * travel_direction * delta)

	var current_lateral_damping := lateral_damping * (0.2 if low_grip_time_remaining > 0.0 else 1.0)
	local_velocity.x = move_toward(local_velocity.x, 0.0, current_lateral_damping * delta)
	local_velocity.z = -forward_velocity
	velocity = global_transform.basis * local_velocity
	if not is_on_floor():
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * delta
	move_and_slide()
	boost_time_remaining = maxf(boost_time_remaining - delta, 0.0)
	low_grip_time_remaining = maxf(low_grip_time_remaining - delta, 0.0)

func apply_low_grip(duration_seconds: float = 2.0) -> void:
	low_grip_time_remaining = maxf(low_grip_time_remaining, duration_seconds)

func _action_name(suffix: String) -> StringName:
	return StringName("%s_%s" % [input_prefix, suffix])

func _is_action_pressed(suffix: String) -> bool:
	if input_prefix.is_empty():
		return false
	return Input.is_action_pressed(_action_name(suffix))

func _clear_active_boost() -> void:
	boost_time_remaining = 0.0

func _apply_player_color() -> void:
	var body_mesh := get_node_or_null("BodyMesh") as MeshInstance3D
	if body_mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.55, 1.0) if player_id == 1 else Color(1.0, 0.3, 0.2)
	body_mesh.material_override = material
