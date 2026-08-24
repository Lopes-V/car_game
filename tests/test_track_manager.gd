extends RefCounted

var BuildOption = load("res://scripts/domain/build_choice.gd")
var TrackManager = load("res://scripts/track/track_manager.gd")

func run() -> bool:
	var all_passed := true
	all_passed = test_initial_track_has_one_piece_and_persistent_finish() and all_passed
	all_passed = test_extension_snaps_piece_and_moves_same_finish() and all_passed
	all_passed = test_piece_exposes_runtime_metadata_and_ordered_trap_slots() and all_passed
	all_passed = test_checkpoint_metadata_is_created_in_safe_zone() and all_passed
	all_passed = test_invalid_option_is_rejected_without_mutating_track() and all_passed
	all_passed = test_extension_stores_canonical_snapshot_not_caller_option() and all_passed
	all_passed = test_near_match_and_stale_options_are_rejected() and all_passed
	all_passed = test_both_curves_have_continuous_outer_collision_and_forward_gate() and all_passed
	return all_passed

func test_initial_track_has_one_piece_and_persistent_finish() -> bool:
	var fixture := _create_manager_fixture()
	var manager = fixture["manager"]
	manager.create_initial_track()
	var original_finish = manager.finish
	manager.create_initial_track()
	var passed := (
		_expect(manager.pieces_root.get_child_count() == 1, "Initial track creation must produce exactly one piece and remain idempotent.")
		and _expect(manager.finish == original_finish, "Initial track creation must retain its one persistent finish node.")
		and _expect(manager.current_end_connector.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -20.0))), "The initial finish must use the straight piece's exact output connector.")
		and _expect(manager.finish.global_transform.is_equal_approx(manager.current_end_connector), "The initial finish transform must agree with the manager connector.")
	)
	_free_fixture(fixture)
	return passed

func test_extension_snaps_piece_and_moves_same_finish() -> bool:
	var fixture := _create_manager_fixture()
	var manager = fixture["manager"]
	manager.create_initial_track()
	var original_finish = manager.finish
	var option = _find_option(manager.layout.get_valid_options(), "curve_left")
	var applied: bool = option != null and manager.apply_extension(option)
	var extension = manager.pieces_root.get_child(1) if manager.pieces_root.get_child_count() > 1 else null
	var passed := (
		_expect(applied, "A currently offered extension must be accepted.")
		and _expect(manager.pieces_root.get_child_count() == 2, "An accepted extension must instantiate exactly one additional piece.")
		and _expect(extension != null and extension.global_transform.is_equal_approx(option.transform), "The new piece input must snap to the option's exact input transform.")
		and _expect(extension.get_node("OutputConnector").global_transform.is_equal_approx(option.output_transform), "The piece output connector must agree with the exact domain output transform.")
		and _expect(manager.finish == original_finish, "Extending the track must move, not recreate, the finish node.")
		and _expect(manager.finish.global_transform.is_equal_approx(manager.current_end_connector), "The moved finish must agree with the current end connector.")
		and _expect(manager.current_end_connector.is_equal_approx(option.output_transform), "The manager must advance to the accepted option's output transform.")
	)
	_free_fixture(fixture)
	return passed

func test_piece_exposes_runtime_metadata_and_ordered_trap_slots() -> bool:
	var fixture := _create_manager_fixture()
	var manager = fixture["manager"]
	manager.create_initial_track()
	var option = _find_option(manager.layout.get_valid_options(), "uphill")
	var applied: bool = option != null and manager.apply_extension(option)
	var initial_piece = manager.pieces_root.get_child(0)
	var uphill_piece = manager.pieces_root.get_child(1) if manager.pieces_root.get_child_count() > 1 else null
	var slots: Array = manager.get_existing_trap_slots()
	var required_nodes := ["InputConnector", "OutputConnector", "ProgressPath", "SafeRespawnZone", "TrapSlots", "RoadCollision", "OutputGate"]
	var passed := _expect(applied, "An offered uphill extension must be accepted for metadata inspection.")
	for node_name in required_nodes:
		passed = _expect(initial_piece.has_node(node_name), "Every track piece must retain named metadata node %s." % node_name) and passed
		passed = _expect(uphill_piece != null and uphill_piece.has_node(node_name), "Every configured variant must retain named metadata node %s." % node_name) and passed
	passed = (
		_expect(slots.size() == 6, "Two pieces must expose exactly three stable trap slots each.")
		and _expect(String(slots[0].get_meta("slot_id")) == "piece_0_slot_0", "Trap slots must begin in initial-piece chain order.")
		and _expect(String(slots[2].get_meta("slot_id")) == "piece_0_slot_2", "All initial-piece slots must precede extension slots.")
		and _expect(String(slots[3].get_meta("slot_id")) == "piece_1_slot_0", "Extension slot ids must encode piece and slot indexes.")
		and _expect(String(slots[5].get_meta("slot_id")) == "piece_1_slot_2", "Every piece must expose its third stable slot.")
		and _expect(_slots_are_outside_safe_zone(initial_piece, slots.slice(0, 3)), "Initial-piece trap slots must stay outside its safe respawn zone.")
		and _expect(_slots_are_outside_safe_zone(uphill_piece, slots.slice(3, 6)), "Uphill trap slots must stay outside its safe respawn zone.")
		and passed
	)
	_free_fixture(fixture)
	return passed

func test_checkpoint_metadata_is_created_in_safe_zone() -> bool:
	var fixture := _create_manager_fixture()
	var manager = fixture["manager"]
	manager.create_initial_track()
	var option = _find_option(manager.layout.get_valid_options(), "straight")
	var applied: bool = option != null and manager.apply_extension(option)
	var extension = manager.pieces_root.get_child(1) if manager.pieces_root.get_child_count() > 1 else null
	var passed := (
		_expect(applied, "An offered straight extension must be accepted for checkpoint placement.")
		and _expect(manager.layout.next_checkpoint_index() == 1, "The first allowed extension must be selected by the layout for a checkpoint.")
		and _expect(extension != null and extension.has_node("SafeRespawnZone/RaceCheckpoint"), "The selected piece must contain a neutral RaceCheckpoint in its safe zone.")
		and _expect(extension != null and extension.has_node("SafeRespawnZone/RespawnPoint"), "The selected piece must contain a neutral RespawnPoint in its safe zone.")
	)
	_free_fixture(fixture)
	return passed

func test_invalid_option_is_rejected_without_mutating_track() -> bool:
	var fixture := _create_manager_fixture()
	var manager = fixture["manager"]
	manager.create_initial_track()
	var original_finish_transform: Transform3D = manager.finish.global_transform
	var forged = BuildOption.new("straight", false, Transform3D.IDENTITY)
	var applied: bool = manager.apply_extension(forged)
	var passed := (
		_expect(not applied, "A forged option that is absent from the current valid snapshot must be rejected.")
		and _expect(manager.layout.pieces.size() == 1, "Rejecting an option must not mutate the domain layout.")
		and _expect(manager.pieces_root.get_child_count() == 1, "Rejecting an option must not instantiate runtime geometry.")
		and _expect(manager.finish.global_transform.is_equal_approx(original_finish_transform), "Rejecting an option must not move the finish.")
	)
	_free_fixture(fixture)
	return passed

func test_extension_stores_canonical_snapshot_not_caller_option() -> bool:
	var fixture := _create_manager_fixture()
	var manager = fixture["manager"]
	manager.create_initial_track()
	var caller_option = _find_option(manager.layout.get_valid_options(), "straight")
	var applied: bool = caller_option != null and manager.apply_extension(caller_option)
	var stored_option = manager.layout.pieces[1] if manager.layout.pieces.size() > 1 else null
	var runtime_piece = manager.pieces_root.get_child(1) if manager.pieces_root.get_child_count() > 1 else null
	if caller_option != null:
		caller_option.transform.origin = Vector3(101.0, 102.0, 103.0)
		caller_option.output_transform.origin = Vector3(201.0, 202.0, 203.0)
	var passed := (
		_expect(applied, "A current valid snapshot option must be accepted before canonical storage is checked.")
		and _expect(stored_option != caller_option, "The layout must store the matched canonical option, not the caller-owned object.")
		and _expect(runtime_piece != null and runtime_piece.option == stored_option, "The runtime piece must retain the canonical option stored by the layout.")
		and _expect(stored_option.transform == Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -20.0)), "Caller mutation must not change the stored canonical input transform.")
		and _expect(stored_option.output_transform == Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -40.0)), "Caller mutation must not change the stored canonical output transform.")
		and _expect(runtime_piece.global_transform == Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -20.0)), "Caller mutation must not change placed runtime geometry.")
	)
	_free_fixture(fixture)
	return passed

func test_near_match_and_stale_options_are_rejected() -> bool:
	var near_fixture := _create_manager_fixture()
	var near_manager = near_fixture["manager"]
	near_manager.create_initial_track()
	var current_straight = _find_option(near_manager.layout.get_valid_options(), "straight")
	var near_match = BuildOption.new("straight", true, current_straight.transform)
	near_match.transform.origin.x += 0.000001
	var near_applied: bool = near_manager.apply_extension(near_match)
	var near_passed := (
		_expect(not near_applied, "A forged transform that is only approximately equal must not match the authoritative snapshot.")
		and _expect(near_manager.layout.pieces.size() == 1, "Rejecting a near-match forgery must leave the layout unchanged.")
	)
	_free_fixture(near_fixture)

	var stale_fixture := _create_manager_fixture()
	var stale_manager = stale_fixture["manager"]
	stale_manager.create_initial_track()
	var stale_option = _find_option(stale_manager.layout.get_valid_options(), "straight")
	var advancing_option = _find_option(stale_manager.layout.get_valid_options(), "curve_left")
	var advanced: bool = advancing_option != null and stale_manager.apply_extension(advancing_option)
	var stale_applied: bool = stale_option != null and stale_manager.apply_extension(stale_option)
	var stale_passed := (
		_expect(advanced, "A current option must advance the connector before stale rejection is checked.")
		and _expect(not stale_applied, "An option captured for an earlier connector must be rejected as stale.")
		and _expect(stale_manager.layout.pieces.size() == 2, "Rejecting a stale option must not append another piece.")
	)
	_free_fixture(stale_fixture)
	return near_passed and stale_passed

func test_both_curves_have_continuous_outer_collision_and_forward_gate() -> bool:
	var all_passed := true
	for variant_id in ["curve_left", "curve_right"]:
		var fixture := _create_manager_fixture()
		var manager = fixture["manager"]
		manager.create_initial_track()
		var option = _find_option(manager.layout.get_valid_options(), variant_id)
		var applied: bool = option != null and manager.apply_extension(option)
		var curve_piece = manager.pieces_root.get_child(1) if manager.pieces_root.get_child_count() > 1 else null
		var gate: Area3D = curve_piece.get_node("OutputGate") if curve_piece != null else null
		var expected_forward: Vector3 = option.output_transform.basis * Vector3.FORWARD if option != null else Vector3.ZERO
		var variant_passed := (
			_expect(applied, "A current %s option must be accepted for curve geometry inspection." % variant_id)
			and _expect(curve_piece != null and _curve_outer_collision_is_continuous(curve_piece, variant_id), "%s collision boxes must meet or overlap along every outer-edge seam." % variant_id)
			and _expect(gate != null and gate.get_meta("forward_only", false) == true, "%s output gate must declare forward-only traversal." % variant_id)
			and _expect(gate != null and gate.global_transform.is_equal_approx(option.output_transform), "%s output gate must use the exact output connector transform." % variant_id)
			and _expect(gate != null and (gate.get_meta("forward_direction") as Vector3).is_equal_approx(expected_forward), "%s output gate metadata must expose the connector's global forward direction." % variant_id)
		)
		all_passed = variant_passed and all_passed
		_free_fixture(fixture)
	return all_passed

func _create_manager_fixture() -> Dictionary:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var temporary_root := Node3D.new()
	temporary_root.name = "TrackManagerTestRoot"
	scene_tree.root.add_child(temporary_root)
	var manager = TrackManager.new()
	temporary_root.add_child(manager)
	return {"root": temporary_root, "manager": manager}

func _free_fixture(fixture: Dictionary) -> void:
	var temporary_root: Node3D = fixture["root"]
	var scene_tree := Engine.get_main_loop() as SceneTree
	if temporary_root.get_parent() == scene_tree.root:
		scene_tree.root.remove_child(temporary_root)
	temporary_root.free()

func _find_option(options: Array, variant_id: String):
	for option in options:
		if option.variant_id == variant_id:
			return option
	return null

func _slots_are_outside_safe_zone(piece: Node3D, slots: Array) -> bool:
	var safe_zone: Area3D = piece.get_node("SafeRespawnZone")
	var safe_shape_node: CollisionShape3D = safe_zone.get_node("CollisionShape3D")
	var safe_box := safe_shape_node.shape as BoxShape3D
	if safe_box == null:
		return false
	var half_size := safe_box.size * 0.5
	for slot in slots:
		var point_in_safe_zone: Vector3 = safe_zone.global_transform.affine_inverse() * slot.global_position
		if (
			absf(point_in_safe_zone.x) <= half_size.x
			and absf(point_in_safe_zone.y) <= half_size.y
			and absf(point_in_safe_zone.z) <= half_size.z
		):
			return false
	return true

func _curve_outer_collision_is_continuous(piece: Node3D, variant_id: String) -> bool:
	var collision_shapes := piece.get_node("RoadCollision").get_children()
	if collision_shapes.size() < 2:
		return false
	var outer_side := 1.0 if variant_id == "curve_left" else -1.0
	for segment_index in range(collision_shapes.size() - 1):
		var current_shape: CollisionShape3D = collision_shapes[segment_index]
		var next_shape: CollisionShape3D = collision_shapes[segment_index + 1]
		var current_box := current_shape.shape as BoxShape3D
		var next_box := next_shape.shape as BoxShape3D
		if current_box == null or next_box == null:
			return false
		var current_outer_front := current_shape.transform * Vector3(outer_side * current_box.size.x * 0.5, 0.0, -current_box.size.z * 0.5)
		var next_outer_back := next_shape.transform * Vector3(outer_side * next_box.size.x * 0.5, 0.0, next_box.size.z * 0.5)
		var seam_forward := (
			current_shape.transform.basis * Vector3.FORWARD
			+ next_shape.transform.basis * Vector3.FORWARD
		).normalized()
		var seam_gap := (next_outer_back - current_outer_front).dot(seam_forward)
		if seam_gap > 0.00001:
			return false
	return true

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
