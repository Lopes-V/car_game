extends RefCounted

const BuildManager = preload("res://scripts/build/build_manager.gd")
const RaceState = preload("res://scripts/domain/race_state.gd")
const TrackManager = preload("res://scripts/track/track_manager.gd")
const TrapController = preload("res://scripts/traps/trap_controller.gd")

func run() -> bool:
	var all_passed := true
	all_passed = test_roles_alternate_and_choices_stay_secret_until_reveal() and all_passed
	all_passed = test_modifier_rejects_invalid_future_and_duplicate_slots() and all_passed
	all_passed = test_reveal_uses_first_still_unoccupied_priority_slot() and all_passed
	all_passed = test_reveal_reports_failure_when_every_priority_became_occupied() and all_passed
	all_passed = test_occupied_slots_persist_and_are_excluded_next_round() and all_passed
	all_passed = test_submitted_priority_list_is_isolated_from_caller_mutation() and all_passed
	all_passed = test_ice_remains_armed_after_repeated_triggers() and all_passed
	all_passed = test_dynamite_triggers_once_and_build_manager_rearms_it() and all_passed
	all_passed = test_empty_option_snapshot_emits_track_build_blocked() and all_passed
	return all_passed

func test_roles_alternate_and_choices_stay_secret_until_reveal() -> bool:
	var odd_fixture := _create_fixture()
	var odd_manager = odd_fixture["build_manager"]
	var odd_state = odd_fixture["race_state"]
	var locked_players: Array[int] = []
	var revealed_choices: Array[Dictionary] = []
	odd_manager.choice_locked.connect(func(player_id: int) -> void: locked_players.append(player_id))
	odd_manager.choices_revealed.connect(
		func(extension_id: String, trap_id: String) -> void:
			revealed_choices.append({"extension_id": extension_id, "trap_id": trap_id})
	)
	var began: bool = odd_manager.begin_secret_phase(1)
	var odd_roles_passed := (
		_expect(began, "A round with build options must begin its secret phase.")
		and _expect(not odd_manager.submit_extension(2, "straight"), "P2 must not extend on an odd round.")
		and _expect(odd_manager.submit_extension(1, "straight"), "P1 must extend on an odd round.")
		and _expect(not odd_manager.submit_modification(1, "ice", _initial_slot_ids()), "P1 must not modify on an odd round.")
		and _expect(odd_manager.submit_modification(2, "ice", _initial_slot_ids()), "P2 must modify on an odd round.")
		and _expect(locked_players == [1, 2], "Each accepted secret choice must lock only its submitting player.")
		and _expect(revealed_choices.is_empty(), "Secret choice signals must not expose either choice before REVEAL.")
		and _expect(odd_manager.reveal_and_apply(), "Both valid odd-round choices must reveal and apply.")
		and _expect(odd_state.phase == RaceState.Phase.APPLY_BUILD, "A completed reveal must leave RaceState in APPLY_BUILD.")
		and _expect(revealed_choices == [{"extension_id": "straight", "trap_id": "ice"}], "REVEAL must expose both choices together exactly once.")
		and _expect(not odd_manager.submit_extension(1, "curve_left"), "Extension changes must be locked after REVEAL.")
		and _expect(not odd_manager.submit_modification(2, "dynamite", _initial_slot_ids()), "Modification changes must be locked after REVEAL.")
	)
	_free_fixture(odd_fixture)

	var even_fixture := _create_fixture()
	var even_manager = even_fixture["build_manager"]
	var even_began: bool = even_manager.begin_secret_phase(2)
	var even_roles_passed := (
		_expect(even_began, "An even round with build options must begin its secret phase.")
		and _expect(not even_manager.submit_extension(1, "straight"), "P1 must not extend on an even round.")
		and _expect(even_manager.submit_extension(2, "straight"), "P2 must extend on an even round.")
		and _expect(not even_manager.submit_modification(2, "ice", _initial_slot_ids()), "P2 must not modify on an even round.")
		and _expect(even_manager.submit_modification(1, "dynamite", _initial_slot_ids()), "P1 must modify on an even round.")
	)
	_free_fixture(even_fixture)
	return odd_roles_passed and even_roles_passed

func test_modifier_rejects_invalid_future_and_duplicate_slots() -> bool:
	var fixture := _create_fixture()
	var manager = fixture["build_manager"]
	manager.begin_secret_phase(1)
	var too_few: Array[String] = ["piece_0_slot_0", "piece_0_slot_1"]
	var duplicates: Array[String] = ["piece_0_slot_0", "piece_0_slot_0", "piece_0_slot_1"]
	var future_slot: Array[String] = ["piece_1_slot_0", "piece_0_slot_1", "piece_0_slot_2"]
	var passed := (
		_expect(not manager.submit_modification(2, "oil", _initial_slot_ids()), "Only ice and dynamite are valid trap types.")
		and _expect(not manager.submit_modification(2, "ice", too_few), "A modification must contain exactly three priorities.")
		and _expect(not manager.submit_modification(2, "ice", duplicates), "A modification must reject duplicate priorities.")
		and _expect(not manager.submit_modification(2, "ice", future_slot), "A slot from the not-yet-created extension must be rejected.")
		and _expect(manager.submit_modification(2, "ice", _initial_slot_ids()), "Three distinct phase-start slots must be accepted.")
	)
	_free_fixture(fixture)
	return passed

func test_reveal_uses_first_still_unoccupied_priority_slot() -> bool:
	var fixture := _create_fixture()
	var manager = fixture["build_manager"]
	var track = fixture["track_manager"]
	manager.begin_secret_phase(1)
	var extension_submitted: bool = manager.submit_extension(1, "straight")
	var modification_submitted: bool = manager.submit_modification(2, "dynamite", _initial_slot_ids())
	var competing_trap = TrapController.new("ice")
	var first_occupied: bool = track.occupy_trap_slot("piece_0_slot_0", competing_trap)
	var applied: bool = manager.reveal_and_apply()
	var first_slot: Marker3D = _slot(track, "piece_0_slot_0")
	var fallback_slot: Marker3D = _slot(track, "piece_0_slot_1")
	var installed_trap = fallback_slot.get_child(0) if fallback_slot != null and fallback_slot.get_child_count() == 1 else null
	var passed := (
		_expect(extension_submitted and modification_submitted, "Priority fallback requires two accepted secret choices.")
		and _expect(first_occupied, "The first snapshotted slot must be occupiable before reveal.")
		and _expect(applied, "Reveal must succeed when a later submitted priority remains available.")
		and _expect(first_slot != null and first_slot.get_child(0) == competing_trap, "Fallback must not replace the trap occupying the first priority.")
		and _expect(fallback_slot != null and fallback_slot.get_meta("occupied", false) == true, "The second priority must become occupied.")
		and _expect(installed_trap is TrapController and installed_trap.trap_type == "dynamite", "Fallback must install the submitted trap type under the marker.")
		and _expect(installed_trap != null and installed_trap.transform == Transform3D.IDENTITY, "TrackManager must attach an installed trap at marker identity.")
	)
	_free_fixture(fixture)
	return passed

func test_reveal_reports_failure_when_every_priority_became_occupied() -> bool:
	var fixture := _create_fixture()
	var manager = fixture["build_manager"]
	var track = fixture["track_manager"]
	manager.begin_secret_phase(1)
	var extension_submitted: bool = manager.submit_extension(1, "straight")
	var modification_submitted: bool = manager.submit_modification(2, "ice", _initial_slot_ids())
	var occupied_all := true
	for slot_id in _initial_slot_ids():
		occupied_all = track.occupy_trap_slot(slot_id, TrapController.new("dynamite")) and occupied_all
	var applied_events: Array[bool] = []
	manager.build_applied.connect(func(success: bool) -> void: applied_events.append(success))
	var applied: bool = manager.reveal_and_apply()
	var passed := (
		_expect(extension_submitted and modification_submitted, "Unavailable-priority handling requires two accepted choices.")
		and _expect(occupied_all, "All snapshotted priorities must become occupied before reveal in this fixture.")
		and _expect(not applied, "The overall build must report failure when no submitted trap priority remains available.")
		and _expect(track.layout.pieces.size() == 2, "A failed modification must not roll back the already-applied canonical extension.")
		and _expect(applied_events == [false], "build_applied must report the failed modification exactly once.")
	)
	_free_fixture(fixture)
	return passed

func test_occupied_slots_persist_and_are_excluded_next_round() -> bool:
	var fixture := _create_fixture()
	var manager = fixture["build_manager"]
	var track = fixture["track_manager"]
	manager.begin_secret_phase(1)
	manager.submit_extension(1, "straight")
	manager.submit_modification(2, "ice", _initial_slot_ids())
	var first_applied: bool = manager.reveal_and_apply()
	var occupied_slot: Marker3D = _slot(track, "piece_0_slot_0")
	var installed_trap = occupied_slot.get_child(0) if occupied_slot != null and occupied_slot.get_child_count() == 1 else null
	var next_began: bool = manager.begin_secret_phase(2)
	var priorities_with_occupied_slot: Array[String] = ["piece_0_slot_0", "piece_0_slot_1", "piece_0_slot_2"]
	var occupied_rejected: bool = not manager.submit_modification(
		1,
		"dynamite",
		priorities_with_occupied_slot,
	)
	var passed := (
		_expect(first_applied, "The initial build and trap placement must apply before persistence is checked.")
		and _expect(next_began, "A later round must snapshot the expanded persistent track.")
		and _expect(occupied_rejected, "An occupied marker must be absent from the next phase snapshot.")
		and _expect(occupied_slot != null and occupied_slot.get_meta("occupied", false) == true, "An installed slot must remain occupied across rounds.")
		and _expect(occupied_slot != null and occupied_slot.get_child_count() == 1 and occupied_slot.get_child(0) == installed_trap, "The same trap node must persist under its marker across rounds.")
	)
	_free_fixture(fixture)
	return passed

func test_submitted_priority_list_is_isolated_from_caller_mutation() -> bool:
	var fixture := _create_fixture()
	var manager = fixture["build_manager"]
	var track = fixture["track_manager"]
	manager.begin_secret_phase(1)
	manager.submit_extension(1, "straight")
	var caller_priorities: Array[String] = _initial_slot_ids()
	var submitted: bool = manager.submit_modification(2, "ice", caller_priorities)
	caller_priorities[0] = "piece_99_slot_0"
	caller_priorities.reverse()
	var applied: bool = manager.reveal_and_apply()
	var first_slot: Marker3D = _slot(track, "piece_0_slot_0")
	var passed := (
		_expect(submitted and applied, "A valid copied priority list must remain applicable.")
		and _expect(first_slot != null and first_slot.get_meta("occupied", false) == true, "Mutating the caller array must not change the stored first priority.")
	)
	_free_fixture(fixture)
	return passed

func test_ice_remains_armed_after_repeated_triggers() -> bool:
	var fixture := _create_fixture()
	var trap = TrapController.new("ice")
	fixture["root"].add_child(trap)
	var first_triggered: bool = trap.try_trigger()
	var second_triggered: bool = trap.try_trigger()
	trap.reset_for_round()
	var passed := (
		_expect(first_triggered and second_triggered, "Ice must trigger on every collision.")
		and _expect(trap.is_armed, "Ice must remain armed continuously, including after round reset.")
		and _expect(not trap.used_this_round, "Ice must not consume the dynamite-only per-round flag.")
	)
	_free_fixture(fixture)
	return passed

func test_dynamite_triggers_once_and_build_manager_rearms_it() -> bool:
	var fixture := _create_fixture()
	var manager = fixture["build_manager"]
	var track = fixture["track_manager"]
	manager.begin_secret_phase(1)
	manager.submit_extension(1, "straight")
	manager.submit_modification(2, "dynamite", _initial_slot_ids())
	var applied: bool = manager.reveal_and_apply()
	var trap = _slot(track, "piece_0_slot_0").get_child(0)
	var first_triggered: bool = trap.try_trigger()
	var second_triggered: bool = trap.try_trigger()
	var disarmed_after_use: bool = not trap.is_armed and trap.used_this_round
	manager.reset_traps_for_racing()
	var passed := (
		_expect(applied, "Dynamite must be installed before its round lifecycle is checked.")
		and _expect(first_triggered and not second_triggered, "Dynamite must trigger only once per racing phase.")
		and _expect(disarmed_after_use, "Used dynamite must remain installed but disarmed for the rest of the round.")
		and _expect(trap.is_armed and not trap.used_this_round, "BuildManager must rearm persistent dynamite for a new racing phase.")
		and _expect(trap.try_trigger(), "Rearmed dynamite must trigger in the next racing phase.")
	)
	_free_fixture(fixture)
	return passed

func test_empty_option_snapshot_emits_track_build_blocked() -> bool:
	var fixture := _create_fixture()
	var manager = fixture["build_manager"]
	var track = fixture["track_manager"]
	var path_built := (
		_apply_variant(track, "curve_left")
		and _apply_variant(track, "curve_left")
		and _apply_variant(track, "curve_left")
	)
	var blocked_events: Array[bool] = []
	manager.track_build_blocked.connect(func() -> void: blocked_events.append(true))
	var began: bool = manager.begin_secret_phase(4)
	var passed := (
		_expect(path_built, "The real track fixture must reach a geometrically blocked end.")
		and _expect(not began, "A phase with no canonical extension options must not begin.")
		and _expect(blocked_events.size() == 1, "An empty option snapshot must emit track_build_blocked exactly once.")
		and _expect(not manager.submit_extension(2, "straight"), "A blocked phase must not accept an extension choice.")
	)
	_free_fixture(fixture)
	return passed

func _create_fixture() -> Dictionary:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var temporary_root := Node3D.new()
	temporary_root.name = "BuildManagerTestRoot"
	scene_tree.root.add_child(temporary_root)
	var track_manager = TrackManager.new()
	temporary_root.add_child(track_manager)
	track_manager.create_initial_track()
	var race_state = RaceState.new()
	var build_manager = BuildManager.new(race_state, track_manager)
	temporary_root.add_child(build_manager)
	return {
		"root": temporary_root,
		"track_manager": track_manager,
		"race_state": race_state,
		"build_manager": build_manager,
	}

func _free_fixture(fixture: Dictionary) -> void:
	var temporary_root: Node3D = fixture["root"]
	var scene_tree := Engine.get_main_loop() as SceneTree
	if temporary_root.get_parent() == scene_tree.root:
		scene_tree.root.remove_child(temporary_root)
	temporary_root.free()

func _initial_slot_ids() -> Array[String]:
	return ["piece_0_slot_0", "piece_0_slot_1", "piece_0_slot_2"]

func _slot(track_manager, slot_id: String) -> Marker3D:
	for slot in track_manager.get_existing_trap_slots():
		if slot.get_meta("slot_id", "") == slot_id:
			return slot
	return null

func _apply_variant(track_manager, variant_id: String) -> bool:
	for option in track_manager.layout.get_valid_options():
		if option.variant_id == variant_id:
			return track_manager.apply_extension(option)
	return false

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
