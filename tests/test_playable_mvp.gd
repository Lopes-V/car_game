extends RefCounted

const RaceState = preload("res://scripts/domain/race_state.gd")

func run() -> bool:
	var all_passed := true
	all_passed = await test_main_scene_boots_real_secret_build_flow() and all_passed
	all_passed = await test_real_ui_builds_counts_down_scores_and_alternates_roles() and all_passed
	all_passed = await test_finish_gate_records_once_and_stops_finisher() and all_passed
	all_passed = await test_runtime_traps_and_saved_respawn_move_real_car() and all_passed
	all_passed = await test_runtime_progress_samples_current_piece_path() and all_passed
	all_passed = await test_hud_forwards_available_slots_when_fewer_than_three_exist() and all_passed
	all_passed = await test_all_eliminated_ends_race_without_waiting_for_deadline() and all_passed
	all_passed = await test_hud_defaults_to_three_distinct_slot_priorities() and all_passed
	all_passed = await test_ice_effect_does_not_leak_into_next_round() and all_passed
	return all_passed

func test_main_scene_boots_real_secret_build_flow() -> bool:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	var main = packed.instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(main)
	await tree.process_frame
	var game = main.get_node_or_null("GameController")
	var track = main.get_node_or_null("TrackManager")
	var hud = main.get_node_or_null("HUD")
	var split_screen = main.get_node_or_null("SplitScreenManager")
	var passed := (
		_expect(game != null and game.race_state != null, "The playable scene must create its authoritative race state.")
		and _expect(game != null and game.race_state.phase == RaceState.Phase.BUILD_SECRET, "The playable scene must begin round one in BUILD_SECRET.")
		and _expect(track != null and track.layout != null and track.layout.pieces.size() == 1, "The playable scene must create the initial linear track.")
		and _expect(main.has_node("Player1") and main.has_node("Player2"), "The playable scene must contain both local cars.")
		and _expect(split_screen != null and split_screen.get_target_for_player(1) == main.get_node("Player1"), "The top camera must follow player one.")
		and _expect(split_screen != null and split_screen.get_target_for_player(2) == main.get_node("Player2"), "The bottom camera must follow player two.")
		and _expect(hud != null and hud.has_method("show_build_state"), "The playable scene must expose the real pass-and-play HUD.")
	)
	main.queue_free()
	await tree.process_frame
	return passed

func test_real_ui_builds_counts_down_scores_and_alternates_roles() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var tree: SceneTree = fixture["tree"]
	var game = main.get_node("GameController")
	var track = main.get_node("TrackManager")
	var hud = main.get_node("HUD")
	var original_finish: Transform3D = track.finish.global_transform
	var lock_button: Button = hud.get_node("Overlay/BuildPanel/VBox/LockButton")
	lock_button.pressed.emit()
	var slot_one: OptionButton = hud.get_node("Overlay/BuildPanel/VBox/SlotOne")
	var slot_two: OptionButton = hud.get_node("Overlay/BuildPanel/VBox/SlotTwo")
	var slot_three: OptionButton = hud.get_node("Overlay/BuildPanel/VBox/SlotThree")
	slot_one.select(0)
	slot_two.select(1)
	slot_three.select(2)
	lock_button.pressed.emit()
	var build_passed := (
		_expect(game.race_state.phase == RaceState.Phase.COUNTDOWN, "Two real locked UI choices must apply and enter COUNTDOWN.")
		and _expect(track.layout.pieces.size() == 2, "The first UI build must append exactly one canonical extension.")
		and _expect(not track.finish.global_transform.is_equal_approx(original_finish), "Applying the UI extension must move the persistent finish.")
		and _expect(_installed_trap_count(track) == 1, "The modifier UI must install one trap in a phase-start slot.")
	)
	await tree.create_timer(3.2).timeout
	var racing_passed := (
		_expect(game.race_state.phase == RaceState.Phase.RACING, "The real three-second countdown must enter RACING.")
		and _expect(main.get_node("Player1").controls_enabled and main.get_node("Player2").controls_enabled, "Both live cars must receive controls in RACING.")
		and _expect(game.player_states[1].boost_charges == 1 and game.player_states[2].boost_charges == 1, "Each player must begin the race with one boost charge.")
	)
	game.race_state.phase = RaceState.Phase.RESULTS
	game.finish_round()
	var results_panel: Control = hud.get_node("Overlay/ResultsPanel")
	var results_passed := _expect(results_panel.visible, "Finishing through the public orchestration API must display round results.")
	var continue_button: Button = hud.get_node("Overlay/ResultsPanel/VBox/ContinueButton")
	continue_button.pressed.emit()
	var next_round_passed := (
		_expect(game.race_state.phase == RaceState.Phase.BUILD_SECRET and game.race_state.round_number == 2, "The explicit continue button must start round two.")
		and _expect(game.build_manager.builder_player_id == 2 and game.build_manager.modifier_player_id == 1, "Build roles must alternate in round two.")
		and _expect(_installed_trap_count(track) == 1, "The installed trap must persist into round two.")
		and _expect(game.player_states[1].boost_charges == 1 and game.player_states[2].boost_charges == 1, "Continue must restore exactly one boost per player.")
	)
	await _free_main(fixture)
	return build_passed and racing_passed and results_passed and next_round_passed

func _instantiate_main() -> Dictionary:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	var main = packed.instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(main)
	await tree.process_frame
	return {"main": main, "tree": tree}

func _free_main(fixture: Dictionary) -> void:
	var main = fixture["main"]
	var tree: SceneTree = fixture["tree"]
	main.queue_free()
	await tree.process_frame

func _installed_trap_count(track) -> int:
	var count := 0
	for slot in track.get_existing_trap_slots():
		if slot.get_meta("occupied", false):
			count += 1
	return count

func test_finish_gate_records_once_and_stops_finisher() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	_lock_first_build(main, "ice")
	game.start_racing(Time.get_ticks_msec() / 1000.0)
	await fixture["tree"].process_frame
	var finish_gate = main.get_node("TrackManager").finish.get_node("FinishGate")
	var car = main.get_node("Player1")
	car.velocity = finish_gate.global_basis * Vector3.FORWARD * 10.0
	var first_crossing: bool = finish_gate.handle_body_crossing(car)
	var first_time: float = float(game.race_state.finish_times.get(1, -1.0))
	var duplicate_crossing: bool = finish_gate.handle_body_crossing(car)
	var car_two = main.get_node("Player2")
	car_two.velocity = finish_gate.global_basis * Vector3.BACK * 10.0
	var reverse_crossing: bool = finish_gate.handle_body_crossing(car_two)
	var passed := (
		_expect(first_crossing and game.race_state.phase == RaceState.Phase.FINAL_WINDOW, "A forward first crossing must open FINAL_WINDOW.")
		and _expect(first_time >= 0.0 and game.race_state.finish_times.size() == 1, "The finish gate must record exactly one timestamp for the finisher.")
		and _expect(not duplicate_crossing and not reverse_crossing, "Duplicate and reverse finish crossings must be ignored.")
		and _expect(not car.controls_enabled, "A finished car must stop accepting controls immediately.")
	)
	await _free_main(fixture)
	return passed

func test_runtime_traps_and_saved_respawn_move_real_car() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	var track = main.get_node("TrackManager")
	_lock_first_build(main, "dynamite")
	game.start_racing(Time.get_ticks_msec() / 1000.0)
	await fixture["tree"].process_frame
	var trap = _first_installed_trap(track)
	var car_one = main.get_node("Player1")
	var car_two = main.get_node("Player2")
	var triggered: bool = trap.handle_body_crossing(car_one)
	var death_passed := (
		_expect(triggered and game.player_states[1].lives == 2 and game.player_states[1].is_dead, "Armed dynamite must remove exactly one life and mark the real car dead.")
		and _expect(not car_one.visible and not car_one.controls_enabled, "A dead car must be hidden and unable to drive while waiting.")
		and _expect(not trap.handle_body_crossing(car_one), "Dynamite must not fire twice in one race.")
	)
	var saved := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, -6.0))
	game.player_states[1].last_safe_respawn = saved
	var activated: bool = game.progress_tracker.try_activate_respawn(2, "respawn_initial", 0, Transform3D.IDENTITY)
	var respawn_passed := (
		_expect(activated and not game.player_states[1].is_dead, "A surviving opponent's valid respawn activation must revive the dead player.")
		and _expect(car_one.visible and car_one.controls_enabled, "Physical respawn must restore visibility and controls during the race.")
		and _expect(absf(car_one.global_position.z + 6.0) < 0.01 and absf(car_one.global_position.x + 1.2) < 0.01, "Physical respawn must use the dead player's own saved transform plus stable lane offset.")
		and _expect(car_one.velocity.is_zero_approx(), "Physical respawn must clear velocity.")
	)
	car_two.global_position.y = -25.0
	await fixture["tree"].process_frame
	var kill_plane_passed := _expect(game.player_states[2].lives == 2 and game.player_states[2].is_dead, "Falling below the kill plane must use the same one-life death path.")
	await _free_main(fixture)
	return death_passed and respawn_passed and kill_plane_passed

func test_runtime_progress_samples_current_piece_path() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	var track = main.get_node("TrackManager")
	_lock_first_build(main, "ice")
	game.start_racing(Time.get_ticks_msec() / 1000.0)
	var piece = track.get_piece(0)
	main.get_node("Player1").global_position = piece.global_transform * Vector3(0.0, 0.8, -10.0)
	await fixture["tree"].process_frame
	var sampled := float(game.progress_tracker.high_water_progress_by_player.get(1, 0.0))
	var passed := _expect(sampled > 9.5 and sampled < 10.5, "Runtime progress must use the current piece ProgressPath distance in meters.")
	await _free_main(fixture)
	return passed

func _lock_first_build(main: Node, trap_id: String) -> void:
	var hud = main.get_node("HUD")
	var lock_button: Button = hud.get_node("Overlay/BuildPanel/VBox/LockButton")
	lock_button.pressed.emit()
	var trap_select: OptionButton = hud.get_node("Overlay/BuildPanel/VBox/TrapSelect")
	trap_select.select(1 if trap_id == "dynamite" else 0)
	hud.get_node("Overlay/BuildPanel/VBox/SlotOne").select(0)
	hud.get_node("Overlay/BuildPanel/VBox/SlotTwo").select(1)
	hud.get_node("Overlay/BuildPanel/VBox/SlotThree").select(2)
	lock_button.pressed.emit()

func _first_installed_trap(track):
	for slot in track.get_existing_trap_slots():
		if slot.get_meta("occupied", false) and slot.get_child_count() > 0:
			return slot.get_child(0)
	return null

func test_hud_forwards_available_slots_when_fewer_than_three_exist() -> bool:
	var hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(hud)
	await tree.process_frame
	var submitted: Array = []
	hud.modification_locked.connect(func(_trap_id: String, slot_ids: Array[String]) -> void: submitted.append(slot_ids))
	var options: Array[String] = ["straight"]
	var slots: Array[String] = ["slot_a", "slot_b"]
	hud.show_build_state(1, 2, options, slots)
	var lock_button: Button = hud.get_node("Overlay/BuildPanel/VBox/LockButton")
	lock_button.pressed.emit()
	hud.get_node("Overlay/BuildPanel/VBox/SlotOne").select(0)
	hud.get_node("Overlay/BuildPanel/VBox/SlotTwo").select(1)
	lock_button.pressed.emit()
	var passed := _expect(submitted == [["slot_a", "slot_b"]], "The HUD must forward every available distinct priority so BuildManager can reject fewer than three slots predictably.")
	hud.queue_free()
	await tree.process_frame
	return passed

func test_all_eliminated_ends_race_without_waiting_for_deadline() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	_lock_first_build(main, "ice")
	game.start_racing(Time.get_ticks_msec() / 1000.0)
	for _death_index in 3:
		main.get_node("Player1").global_position.y = -25.0
		main.get_node("Player2").global_position.y = -25.0
		await fixture["tree"].process_frame
	var results_visible: bool = main.get_node("HUD/Overlay/ResultsPanel").visible
	var passed := (
		_expect(game.player_states[1].is_eliminated and game.player_states[2].is_eliminated, "Three kill-plane deaths must eliminate both players only for the current round.")
		and _expect(game.race_state.phase == RaceState.Phase.NEXT_ROUND, "All-player elimination must score and end the race without waiting for 120 seconds.")
		and _expect(results_visible, "All-player elimination must show the round results and explicit continue action.")
	)
	main.get_node("HUD/Overlay/ResultsPanel/VBox/ContinueButton").pressed.emit()
	passed = (
		_expect(main.get_node("Player1").visible and main.get_node("Player2").visible, "A new round must restore both eliminated car bodies.")
		and _expect(main.get_node("Player1").collision_layer == 1 and main.get_node("Player2").collision_layer == 1, "A new round must restore car collision layers.")
		and passed
	)
	await _free_main(fixture)
	return passed

func test_hud_defaults_to_three_distinct_slot_priorities() -> bool:
	var hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(hud)
	await tree.process_frame
	var options: Array[String] = ["straight"]
	var slots: Array[String] = ["slot_a", "slot_b", "slot_c"]
	hud.show_build_state(1, 2, options, slots)
	hud.get_node("Overlay/BuildPanel/VBox/LockButton").pressed.emit()
	var selected := [
		hud.get_node("Overlay/BuildPanel/VBox/SlotOne").get_selected_id(),
		hud.get_node("Overlay/BuildPanel/VBox/SlotTwo").get_selected_id(),
		hud.get_node("Overlay/BuildPanel/VBox/SlotThree").get_selected_id(),
	]
	var passed := _expect(selected == [0, 1, 2], "The modifier phase must default to three distinct priorities so a valid secret choice is immediately actionable.")
	hud.queue_free()
	await tree.process_frame
	return passed

func test_ice_effect_does_not_leak_into_next_round() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	_lock_first_build(main, "ice")
	game.start_racing(Time.get_ticks_msec() / 1000.0)
	var car = main.get_node("Player1")
	var trap = _first_installed_trap(main.get_node("TrackManager"))
	var triggered: bool = trap.handle_body_crossing(car)
	game.race_state.phase = RaceState.Phase.RESULTS
	game.finish_round()
	main.get_node("HUD/Overlay/ResultsPanel/VBox/ContinueButton").pressed.emit()
	var passed := (
		_expect(triggered, "The real ice trap must trigger for a configured car during RACING.")
		and _expect(game.player_states[1].lives == 3, "Ice must never consume a life.")
		and _expect(is_zero_approx(car.low_grip_time_remaining), "A new round must clear the previous race's temporary low-grip effect.")
	)
	await _free_main(fixture)
	return passed

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
