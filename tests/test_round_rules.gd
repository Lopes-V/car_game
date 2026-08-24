extends RefCounted

const CarController = preload("res://scripts/car/car_controller.gd")
const PlayerRoundState = preload("res://scripts/domain/player_round_state.gd")
const SplitScreenManager = preload("res://scripts/ui/split_screen_manager.gd")

func run() -> bool:
	var all_passed := true
	all_passed = test_one_boost_charge_is_consumed_once_per_round() and all_passed
	all_passed = test_life_loss_is_idempotent_until_respawn() and all_passed
	all_passed = test_lives_and_boost_reset_between_rounds() and all_passed
	all_passed = test_car_reads_only_its_configured_input_prefix() and all_passed
	all_passed = test_car_rejects_input_while_disabled_or_dead() and all_passed
	all_passed = test_boost_requires_a_fresh_enabled_activation() and all_passed
	all_passed = test_invalid_control_state_clears_active_boost() and all_passed
	all_passed = test_controller_round_reset_clears_runtime_and_domain_state() and all_passed
	all_passed = test_active_boost_increases_and_preserves_coasting_speed() and all_passed
	all_passed = test_shared_car_scene_has_body_collision_and_player_color() and all_passed
	all_passed = test_split_screen_binds_two_targets_to_shared_world_viewports() and all_passed
	return all_passed

func test_one_boost_charge_is_consumed_once_per_round() -> bool:
	var player = PlayerRoundState.new()
	player.reset_for_round()
	return (
		_expect(player.try_consume_boost(), "The round's single boost charge must be available.")
		and _expect(not player.try_consume_boost(), "A consumed boost charge must not be available again.")
		and _expect(player.boost_charges == 0, "Consuming boost must leave zero charges.")
	)

func test_life_loss_is_idempotent_until_respawn() -> bool:
	var player = PlayerRoundState.new()
	var initial_safe := Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	player.reset_for_round(initial_safe)
	var first_loss_can_respawn: bool = player.lose_life()
	var repeated_loss_can_respawn: bool = player.lose_life()
	var after_repeated_loss: int = player.lives
	var respawned: bool = player.respawn(Transform3D(Basis.IDENTITY, Vector3(4.0, 5.0, 6.0)))
	player.lose_life()
	var second_respawned: bool = player.respawn(Transform3D.IDENTITY)
	var final_loss_can_respawn: bool = player.lose_life()
	return (
		_expect(first_loss_can_respawn and repeated_loss_can_respawn, "A dead player with lives must remain eligible for a future respawn.")
		and _expect(after_repeated_loss == 2 and player.deaths == 3, "Repeated damage while dead must not consume another life or count another death.")
		and _expect(respawned and second_respawned, "A player with remaining lives must be able to respawn.")
		and _expect(not final_loss_can_respawn, "Losing the final life must make future respawn impossible.")
		and _expect(player.lives == 0 and player.is_dead and player.is_eliminated, "Final life loss must leave the player dead and eliminated.")
		and _expect(player.last_safe_respawn == Transform3D.IDENTITY, "Respawn must record the supplied safe transform.")
	)

func test_lives_and_boost_reset_between_rounds() -> bool:
	var player = PlayerRoundState.new()
	player.reset_for_round()
	player.lose_life()
	player.try_consume_boost()
	var next_safe := Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, -5.0))
	player.reset_for_round(next_safe)
	return (
		_expect(player.lives == 3 and player.deaths == 0, "A new round must restore exactly three lives and clear deaths.")
		and _expect(player.boost_charges == 1, "A new round must restore exactly one boost charge.")
		and _expect(not player.is_dead and not player.is_eliminated, "A new round must restore the live non-eliminated state.")
		and _expect(player.last_safe_respawn == next_safe, "A new round must record its initial safe respawn.")
	)

func test_car_reads_only_its_configured_input_prefix() -> bool:
	var first_fixture := _create_car_fixture(1, "p1")
	var car = first_fixture["car"]
	Input.action_press("p2_accelerate")
	car._physics_process(0.1)
	var first_ignored_other_prefix := is_zero_approx(car.velocity.z)
	Input.action_release("p2_accelerate")
	Input.action_press("p1_accelerate")
	car._physics_process(0.1)
	var first_accepted_own_prefix: bool = car.velocity.z < 0.0
	Input.action_release("p1_accelerate")
	_free_fixture(first_fixture)

	var second_fixture := _create_car_fixture(2, "p2")
	car = second_fixture["car"]
	Input.action_press("p1_accelerate")
	car._physics_process(0.1)
	var second_ignored_other_prefix := is_zero_approx(car.velocity.z)
	Input.action_release("p1_accelerate")
	Input.action_press("p2_accelerate")
	car._physics_process(0.1)
	var second_accepted_own_prefix: bool = car.velocity.z < 0.0
	Input.action_release("p2_accelerate")
	_free_fixture(second_fixture)
	return (
		_expect(first_ignored_other_prefix and second_ignored_other_prefix, "Each car must ignore the other player's acceleration input.")
		and _expect(first_accepted_own_prefix and second_accepted_own_prefix, "Each car must accept only its configured acceleration input.")
	)

func test_car_rejects_input_while_disabled_or_dead() -> bool:
	var fixture := _create_car_fixture(1, "p1")
	var car = fixture["car"]
	var state = fixture["state"]
	Input.action_press("p1_accelerate")
	car.controls_enabled = false
	car._physics_process(0.1)
	var ignored_disabled := is_zero_approx(car.velocity.z)
	car.controls_enabled = true
	state.lose_life()
	car._physics_process(0.1)
	var ignored_dead := is_zero_approx(car.velocity.z)
	Input.action_release("p1_accelerate")
	_free_fixture(fixture)
	return (
		_expect(ignored_disabled, "A disabled car must ignore its own input.")
		and _expect(ignored_dead, "A dead car must ignore its own input.")
	)

func test_boost_requires_a_fresh_enabled_activation() -> bool:
	var fixture := _create_car_fixture(1, "p1")
	var car = fixture["car"]
	var state = fixture["state"]
	car.controls_enabled = false
	Input.action_press("p1_boost")
	car._physics_process(0.1)
	var ignored_while_disabled: bool = state.boost_charges == 1 and is_zero_approx(car.boost_time_remaining)
	car.controls_enabled = true
	car._physics_process(0.1)
	var held_press_not_fresh: bool = state.boost_charges == 1 and is_zero_approx(car.boost_time_remaining)
	Input.action_release("p1_boost")
	car._physics_process(0.1)
	Input.action_press("p1_boost")
	car._physics_process(0.1)
	var fresh_press_consumed: bool = state.boost_charges == 0 and car.boost_time_remaining > 1.8
	car._physics_process(0.1)
	var held_press_did_not_restart: bool = car.boost_time_remaining < 1.9
	Input.action_release("p1_boost")
	_free_fixture(fixture)
	return (
		_expect(ignored_while_disabled, "A boost press while controls are disabled must not consume the charge.")
		and _expect(held_press_not_fresh, "Enabling controls while boost is held must not count as a fresh activation.")
		and _expect(fresh_press_consumed, "A fresh enabled boost activation must consume the single charge.")
		and _expect(held_press_did_not_restart, "Holding boost must not restart its duration.")
	)

func test_invalid_control_state_clears_active_boost() -> bool:
	var fixture := _create_car_fixture(1, "p1")
	var car = fixture["car"]
	var state = fixture["state"]
	Input.action_press("p1_boost")
	car._physics_process(0.1)
	var activated_before_death: bool = car.boost_time_remaining > 0.0
	state.lose_life()
	car._physics_process(0.1)
	var cleared_on_death: bool = is_zero_approx(car.boost_time_remaining)
	state.respawn(Transform3D.IDENTITY)
	car._physics_process(0.1)
	var stayed_cleared_after_respawn: bool = is_zero_approx(car.boost_time_remaining)
	state.reset_for_round()
	Input.action_release("p1_boost")
	car._physics_process(0.1)
	Input.action_press("p1_boost")
	car._physics_process(0.1)
	var reactivated_before_disable: bool = car.boost_time_remaining > 0.0
	car.controls_enabled = false
	var cleared_on_disable: bool = is_zero_approx(car.boost_time_remaining)
	Input.action_release("p1_boost")
	_free_fixture(fixture)
	return (
		_expect(activated_before_death and reactivated_before_disable, "The fixture must activate boost before invalidation checks.")
		and _expect(cleared_on_death, "Death must clear active controller boost immediately on the next physics update.")
		and _expect(stayed_cleared_after_respawn, "Respawn must not resume boost left from before death.")
		and _expect(cleared_on_disable, "Disabling controls must clear active boost without preserving its timer.")
	)

func test_controller_round_reset_clears_runtime_and_domain_state() -> bool:
	var fixture := _create_car_fixture(1, "p1")
	var car = fixture["car"]
	var state = fixture["state"]
	car.velocity = Vector3(2.0, 0.0, -12.0)
	Input.action_press("p1_boost")
	car._physics_process(0.1)
	state.lose_life()
	var next_safe := Transform3D(Basis.IDENTITY, Vector3(3.0, 1.0, -8.0))
	car.reset_for_round(next_safe)
	var reset_cleanly: bool = (
		state.lives == 3
		and state.boost_charges == 1
		and not state.is_dead
		and state.last_safe_respawn == next_safe
		and is_zero_approx(car.boost_time_remaining)
		and car.velocity == Vector3.ZERO
		and not car.controls_enabled
	)
	Input.action_release("p1_boost")
	car._physics_process(0.1)
	car.controls_enabled = true
	Input.action_press("p1_boost")
	car._physics_process(0.1)
	var resumed_with_new_charge: bool = state.boost_charges == 0 and car.boost_time_remaining > 0.0
	Input.action_release("p1_boost")
	_free_fixture(fixture)
	return (
		_expect(reset_cleanly, "Controller round reset must clear velocity/boost, disable controls, and reset its domain state.")
		and _expect(resumed_with_new_charge, "After reset and a fresh press, the new round's boost charge must activate normally.")
	)

func test_active_boost_increases_and_preserves_coasting_speed() -> bool:
	var fixture := _create_car_fixture(1, "p1")
	var car = fixture["car"]
	car.velocity = Vector3(0.0, 0.0, -10.0)
	Input.action_press("p1_boost")
	car._physics_process(0.25)
	var speed_after_activation: float = -car.velocity.z
	Input.action_release("p1_boost")
	var stayed_boosted_and_capped: bool = speed_after_activation > 10.0 and speed_after_activation <= 44.8
	for step in range(7):
		car._physics_process(0.25)
		var active_speed: float = -car.velocity.z
		stayed_boosted_and_capped = stayed_boosted_and_capped and active_speed > 10.0 and active_speed <= 44.8
	var full_duration_elapsed := is_zero_approx(car.boost_time_remaining)
	var speed_at_expiry: float = -car.velocity.z
	car._physics_process(0.25)
	var normal_coasting_resumed: bool = -car.velocity.z < speed_at_expiry
	_free_fixture(fixture)
	return (
		_expect(speed_after_activation > 10.0, "Fresh boost must immediately increase an existing forward coasting velocity.")
		and _expect(stayed_boosted_and_capped, "Boost must preserve stronger forward motion for two seconds without exceeding its 1.6x cap.")
		and _expect(full_duration_elapsed and normal_coasting_resumed, "Normal coasting deceleration must resume after the two-second boost expires.")
	)

func test_shared_car_scene_has_body_collision_and_player_color() -> bool:
	var packed_scene := load("res://scenes/car/car.tscn") as PackedScene
	var first_car = packed_scene.instantiate()
	var second_car = packed_scene.instantiate()
	first_car.configure(1, "p1")
	second_car.configure(2, "p2")
	var first_mesh := first_car.get_node_or_null("BodyMesh") as MeshInstance3D
	var second_mesh := second_car.get_node_or_null("BodyMesh") as MeshInstance3D
	var collision := first_car.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var first_material := first_mesh.material_override as StandardMaterial3D if first_mesh != null else null
	var second_material := second_mesh.material_override as StandardMaterial3D if second_mesh != null else null
	var passed := (
		_expect(first_car is CarController and second_car is CarController, "The shared car scene root must use CarController.")
		and _expect(first_mesh != null and first_mesh.mesh != null, "The shared car scene must contain visible body geometry.")
		and _expect(collision != null and collision.shape != null, "The shared car scene must contain an active collision shape.")
		and _expect(first_material != null and first_material.albedo_color == Color(0.2, 0.55, 1.0), "Configuring P1 must apply its visible blue material.")
		and _expect(second_material != null and second_material.albedo_color == Color(1.0, 0.3, 0.2), "Configuring P2 must apply its visible red material.")
	)
	first_car.free()
	second_car.free()
	return passed

func test_split_screen_binds_two_targets_to_shared_world_viewports() -> bool:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var temporary_root := Node3D.new()
	temporary_root.name = "SplitScreenTestRoot"
	scene_tree.root.add_child(temporary_root)
	var first_car := CarController.new()
	var second_car := CarController.new()
	temporary_root.add_child(first_car)
	temporary_root.add_child(second_car)
	var manager = SplitScreenManager.new()
	temporary_root.add_child(manager)
	manager.configure(first_car, second_car)
	var top_container = manager.get_node_or_null("TopView")
	var bottom_container = manager.get_node_or_null("BottomView")
	var first_viewport = manager.get_viewport_for_player(1)
	var second_viewport = manager.get_viewport_for_player(2)
	var first_camera = manager.get_camera_for_player(1)
	var second_camera = manager.get_camera_for_player(2)
	var passed := (
		_expect(top_container is SubViewportContainer and bottom_container is SubViewportContainer, "Split-screen must own two viewport containers.")
		and _expect(is_equal_approx(top_container.anchor_bottom, 0.5) and is_equal_approx(bottom_container.anchor_top, 0.5), "The two viewport containers must occupy equal top and bottom halves.")
		and _expect(first_viewport is SubViewport and second_viewport is SubViewport and first_viewport != second_viewport, "Each player must have a distinct SubViewport.")
		and _expect(first_viewport.world_3d == temporary_root.get_viewport().world_3d and second_viewport.world_3d == temporary_root.get_viewport().world_3d, "Both player viewports must share the main World3D.")
		and _expect(first_camera is Camera3D and second_camera is Camera3D, "Each player viewport must own a follow camera.")
		and _expect(first_camera.get_parent() == first_viewport and second_camera.get_parent() == second_viewport, "Follow cameras must live inside their viewports, not under cars.")
		and _expect(manager.get_target_for_player(1) == first_car and manager.get_target_for_player(2) == second_car, "Each follow camera must bind to its configured car target.")
	)
	scene_tree.root.remove_child(temporary_root)
	temporary_root.free()
	return passed

func _create_car_fixture(player_id: int, prefix: String) -> Dictionary:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var temporary_root := Node3D.new()
	temporary_root.name = "CarControllerTestRoot"
	scene_tree.root.add_child(temporary_root)
	var state = PlayerRoundState.new()
	state.reset_for_round()
	var car = CarController.new()
	car.round_state = state
	car.configure(player_id, prefix)
	car.controls_enabled = true
	temporary_root.add_child(car)
	return {"root": temporary_root, "car": car, "state": state}

func _free_fixture(fixture: Dictionary) -> void:
	for action in ["p1_accelerate", "p1_brake", "p1_left", "p1_right", "p1_boost", "p2_accelerate", "p2_brake", "p2_left", "p2_right", "p2_boost"]:
		Input.action_release(action)
	var temporary_root: Node3D = fixture["root"]
	var scene_tree := Engine.get_main_loop() as SceneTree
	if temporary_root.get_parent() == scene_tree.root:
		scene_tree.root.remove_child(temporary_root)
	temporary_root.free()

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
