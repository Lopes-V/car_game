extends RefCounted

func run() -> bool:
	var main_scene = load("res://scenes/main/main.tscn") as PackedScene
	if main_scene == null:
		push_error("Main scene could not be loaded.")
		return false

	var main_instance = main_scene.instantiate()
	if not main_instance is Node3D:
		push_error("Main scene root must be a Node3D.")
		main_instance.free()
		return false

	var game_controller = main_instance.get_node_or_null("GameController")
	if game_controller == null:
		push_error("Main scene must contain a GameController child.")
		main_instance.free()
		return false
	if not game_controller.has_method("start_match"):
		push_error("GameController must expose start_match().")
		main_instance.free()
		return false

	var expected_bindings := {
		"p1_accelerate": KEY_W,
		"p1_brake": KEY_S,
		"p1_left": KEY_A,
		"p1_right": KEY_D,
		"p2_accelerate": KEY_UP,
		"p2_brake": KEY_DOWN,
		"p2_left": KEY_LEFT,
		"p2_right": KEY_RIGHT,
		"p2_boost": KEY_ENTER,
	}
	for action_name in expected_bindings:
		if not _has_key_binding(action_name, expected_bindings[action_name]):
			push_error("Input action is missing its expected binding: %s" % action_name)
			main_instance.free()
			return false
	if not _has_key_binding("p1_boost", KEY_NONE, KEY_SHIFT, KEY_LOCATION_LEFT):
		push_error("P1 boost must be bound to Left Shift.")
		main_instance.free()
		return false

	main_instance.free()
	return true

func _has_key_binding(
	action_name: StringName,
	keycode: Key,
	physical_keycode: Key = KEY_NONE,
	location: KeyLocation = KEY_LOCATION_UNSPECIFIED,
) -> bool:
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey \
				and event.keycode == keycode \
				and event.physical_keycode == physical_keycode \
				and event.location == location:
			return true
	return false
