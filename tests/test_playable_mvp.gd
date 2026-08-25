extends RefCounted

const RaceState = preload("res://scripts/domain/race_state.gd")

func run() -> bool:
	var all_passed := true
	all_passed = await test_main_scene_boots_real_secret_build_flow() and all_passed
	all_passed = await test_reveal_renders_immutable_ordered_slot_priorities() and all_passed
	all_passed = await test_real_ui_builds_counts_down_scores_and_alternates_roles() and all_passed
	all_passed = await test_finish_gate_records_once_and_stops_finisher() and all_passed
	all_passed = await test_runtime_traps_and_saved_respawn_move_real_car() and all_passed
	all_passed = await test_runtime_progress_samples_current_piece_path() and all_passed
	all_passed = await test_hud_forwards_available_slots_when_fewer_than_three_exist() and all_passed
	all_passed = await test_all_eliminated_ends_race_without_waiting_for_deadline() and all_passed
	all_passed = await test_hud_defaults_to_three_distinct_slot_priorities() and all_passed
	all_passed = await test_ice_effect_does_not_leak_into_next_round() and all_passed
	all_passed = await test_partial_trap_failure_keeps_extension_and_counts_down() and all_passed
	all_passed = await test_extension_apply_failure_ends_in_controlled_result() and all_passed
	all_passed = await test_composed_match_reaches_target_score_match_end() and all_passed
	all_passed = await test_composed_match_reaches_fifth_round_match_end() and all_passed
	all_passed = await test_initial_track_build_blocked_result_is_not_overwritten() and all_passed
	all_passed = await test_composed_finish_and_trap_receive_real_body_entered() and all_passed
	return all_passed

func test_reveal_renders_immutable_ordered_slot_priorities() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	var hud = main.get_node("HUD")
	var priorities: Array[String] = ["piece_0_slot_2", "piece_0_slot_0", "piece_0_slot_1"]
	var extension_locked: bool = game.build_manager.submit_extension(1, "straight")
	var modification_locked: bool = game.build_manager.submit_modification(2, "dynamite", priorities)
	var revealed: bool = game.build_manager.reveal_choices()
	var reveal_label: Label = hud.get_node("Overlay/RevealPanel/VBox/RevealLabel")
	var expected := "Revelado:\nExtensao: straight\nArmadilha: dynamite\nPrioridades:\n1. piece_0_slot_2\n2. piece_0_slot_0\n3. piece_0_slot_1"
	var text_before_mutation: String = reveal_label.text
	priorities[0] = "piece_99_slot_0"
	priorities.reverse()
	await fixture["tree"].process_frame
	var passed := (
		_expect(extension_locked and modification_locked and revealed, "The composed reveal fixture must accept and reveal both locked choices.")
		and _expect(hud.get_node("Overlay/RevealPanel").visible and text_before_mutation == expected, "REVEAL must visibly render extension, trap, and all three ordered priorities before apply; got %s." % text_before_mutation)
		and _expect(reveal_label.text == expected, "Mutating the original submitted array must not alter the visible revealed choice; got %s." % reveal_label.text)
	)
	await _free_main(fixture)
	return passed

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
	var reveal_panel: Control = hud.get_node("Overlay/RevealPanel")
	var reveal_passed := (
		_expect(game.race_state.phase == RaceState.Phase.REVEAL, "The second secret lock must stop in durable REVEAL.")
		and _expect(reveal_panel.visible and not hud.get_node("Overlay/RevealPanel/VBox/RevealButton").disabled, "The revealed choices and explicit apply action must stay visible.")
		and _expect(track.layout.pieces.size() == 1 and _installed_trap_count(track) == 0, "No physical build may occur before explicit apply.")
	)
	hud.get_node("Overlay/RevealPanel/VBox/RevealButton").pressed.emit()
	var build_passed := (
		_expect(game.race_state.phase == RaceState.Phase.COUNTDOWN, "Explicit reveal apply must enter COUNTDOWN.")
		and _expect(hud.get_node("Overlay/PhaseLabel").text == "COUNTDOWN", "A normal build must replace the large BUILD_SECRET phase label with COUNTDOWN.")
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
	game.update_race(game.race_state.race_end_time)
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
	return reveal_passed and build_passed and racing_passed and results_passed and next_round_passed

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
	var extension_select: OptionButton = hud.get_node("Overlay/BuildPanel/VBox/ExtensionSelect")
	for item_index in extension_select.item_count:
		if extension_select.get_item_text(item_index) == "straight":
			extension_select.select(item_index)
			break
	lock_button.pressed.emit()
	var trap_select: OptionButton = hud.get_node("Overlay/BuildPanel/VBox/TrapSelect")
	trap_select.select(1 if trap_id == "dynamite" else 0)
	hud.get_node("Overlay/BuildPanel/VBox/SlotOne").select(0)
	hud.get_node("Overlay/BuildPanel/VBox/SlotTwo").select(1)
	hud.get_node("Overlay/BuildPanel/VBox/SlotThree").select(2)
	lock_button.pressed.emit()
	hud.get_node("Overlay/RevealPanel/VBox/RevealButton").pressed.emit()

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
	game.update_race(game.race_state.race_end_time)
	main.get_node("HUD/Overlay/ResultsPanel/VBox/ContinueButton").pressed.emit()
	var passed := (
		_expect(triggered, "The real ice trap must trigger for a configured car during RACING.")
		and _expect(game.player_states[1].lives == 3, "Ice must never consume a life.")
		and _expect(is_zero_approx(car.low_grip_time_remaining), "A new round must clear the previous race's temporary low-grip effect.")
	)
	await _free_main(fixture)
	return passed

func test_partial_trap_failure_keeps_extension_and_counts_down() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	var track = main.get_node("TrackManager")
	var hud = main.get_node("HUD")
	var lock_button: Button = hud.get_node("Overlay/BuildPanel/VBox/LockButton")
	lock_button.pressed.emit()
	lock_button.pressed.emit()
	for slot_id in ["piece_0_slot_0", "piece_0_slot_1", "piece_0_slot_2"]:
		track.occupy_trap_slot(slot_id, (load("res://scenes/traps/dynamite.tscn") as PackedScene).instantiate())
	hud.get_node("Overlay/RevealPanel/VBox/RevealButton").pressed.emit()
	var passed := (
		_expect(game.race_state.phase == RaceState.Phase.COUNTDOWN, "A kept extension with failed modification must continue into COUNTDOWN.")
		and _expect(game.build_manager.last_extension_applied and not game.build_manager.last_trap_applied, "Runtime orchestration must preserve separate partial-application results.")
		and _expect(track.layout.pieces.size() == 2, "A modification failure must not roll back the valid extension.")
		and _expect("MODIFICATION_FAILED" in hud.get_node("Overlay/PhaseLabel").text, "The HUD must report the failed modification during countdown.")
	)
	await _free_main(fixture)
	return passed

func test_extension_apply_failure_ends_in_controlled_result() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	var track = main.get_node("TrackManager")
	var hud = main.get_node("HUD")
	var lock_button: Button = hud.get_node("Overlay/BuildPanel/VBox/LockButton")
	lock_button.pressed.emit()
	lock_button.pressed.emit()
	track.apply_extension(track.layout.get_valid_options()[0])
	hud.get_node("Overlay/RevealPanel/VBox/RevealButton").pressed.emit()
	var passed := (
		_expect(game.race_state.phase == RaceState.Phase.MATCH_END and game.end_reason == "TRACK_BUILD_BLOCKED", "An invalidated revealed extension must end through the controlled build-failure path.")
		and _expect(hud.get_node("Overlay/ResultsPanel").visible and not hud.get_node("Overlay/BuildPanel").visible, "Controlled extension failure must show results without deadlocking APPLY_BUILD.")
	)
	await _free_main(fixture)
	return passed

func test_composed_match_reaches_target_score_match_end() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	for round_number in range(1, 5):
		_lock_first_build(main, "ice")
		game.start_racing(Time.get_ticks_msec() / 1000.0)
		var finish_gate = main.get_node("TrackManager").finish.get_node("FinishGate")
		var car = main.get_node("Player1")
		car.velocity = finish_gate.global_basis * Vector3.FORWARD * 10.0
		finish_gate.handle_body_crossing(car)
		game.update_race(game.race_state.race_end_time)
		if round_number < 4:
			main.get_node("HUD/Overlay/ResultsPanel/VBox/ContinueButton").pressed.emit()
	var passed := (
		_expect(game.race_state.phase == RaceState.Phase.MATCH_END and game.end_reason == "TARGET_SCORE", "Four composed winning rounds must reach target-score MATCH_END through real finish-window deadlines.")
		and _expect(game.winner_id == 1 and int(game.total_scores[1]) >= 20, "Target-score match end must retain the highest awarded total and winner.")
		and _expect(main.get_node("HUD/Overlay/PhaseLabel").text == "MATCH_END - TARGET_SCORE", "The HUD phase label must expose the terminal target-score state.")
		and _expect("TARGET_SCORE" in main.get_node("HUD/Overlay/ResultsPanel/VBox/ResultsLabel").text, "The result panel must visibly expose the target-score reason.")
	)
	await _free_main(fixture)
	return passed

func test_composed_match_reaches_fifth_round_match_end() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var game = main.get_node("GameController")
	for round_number in range(1, 6):
		_lock_first_build(main, "ice")
		game.start_racing(Time.get_ticks_msec() / 1000.0)
		main.get_node("Player1").global_position.y = -25.0
		main.get_node("Player2").global_position.y = -25.0
		await fixture["tree"].process_frame
		var finisher_id := 1 if round_number % 2 == 1 else 2
		var finish_gate = main.get_node("TrackManager").finish.get_node("FinishGate")
		var car = main.get_node("Player%d" % finisher_id)
		car.velocity = finish_gate.global_basis * Vector3.FORWARD * 10.0
		finish_gate.handle_body_crossing(car)
		game.update_race(game.race_state.race_end_time)
		if round_number < 5:
			main.get_node("HUD/Overlay/ResultsPanel/VBox/ContinueButton").pressed.emit()
	var passed := (
		_expect(game.race_state.phase == RaceState.Phase.MATCH_END and game.end_reason == "MAX_ROUNDS", "A below-target composed match must end after the fifth scored round.")
		and _expect(game.winner_id == 1 and int(game.total_scores[1]) < 20 and int(game.total_scores[2]) < 20, "Fifth-round termination must resolve the higher below-target total.")
		and _expect(main.get_node("HUD/Overlay/PhaseLabel").text == "MATCH_END - MAX_ROUNDS", "The HUD phase label must expose the five-round terminal reason.")
	)
	await _free_main(fixture)
	return passed

func test_initial_track_build_blocked_result_is_not_overwritten() -> bool:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	var main = packed.instantiate()
	var game = main.get_node("GameController")
	game.owner = null
	main.remove_child(game)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(main)
	await tree.process_frame
	var track = main.get_node("TrackManager")
	track.create_initial_track()
	for _index in 3:
		var left_options = track.layout.get_valid_options().filter(func(option): return option.variant_id == "curve_left")
		track.apply_extension(left_options[0])
	main.add_child(game)
	await tree.process_frame
	var passed := (
		_expect(game.race_state.phase == RaceState.Phase.MATCH_END and game.end_reason == "TRACK_BUILD_BLOCKED", "An initially blocked real track must terminate during scene boot.")
		and _expect(main.get_node("HUD/Overlay/ResultsPanel").visible and not main.get_node("HUD/Overlay/BuildPanel").visible, "Boot orchestration must not overwrite TRACK_BUILD_BLOCKED results with build UI.")
		and _expect(main.get_node("HUD/Overlay/PhaseLabel").text == "MATCH_END - TRACK_BUILD_BLOCKED", "Blocked boot must remain visible in the HUD phase label.")
	)
	main.queue_free()
	await tree.process_frame
	return passed

func test_composed_finish_and_trap_receive_real_body_entered() -> bool:
	var fixture := await _instantiate_main()
	var main = fixture["main"]
	var tree: SceneTree = fixture["tree"]
	var game = main.get_node("GameController")
	_lock_first_build(main, "ice")
	game.start_racing(Time.get_ticks_msec() / 1000.0)
	var trap = _first_installed_trap(main.get_node("TrackManager"))
	var trap_events: Array[int] = []
	trap.triggered.connect(func(player_id: int, _trap_type: String) -> void: trap_events.append(player_id))
	var car_one = main.get_node("Player1")
	car_one.controls_enabled = false
	car_one.global_position = trap.global_position + Vector3(0.0, 0.0, 5.0)
	await tree.physics_frame
	await tree.process_frame
	car_one.global_position = trap.global_position - Vector3(0.0, 0.6, 0.0)
	await tree.physics_frame
	await tree.process_frame
	await tree.physics_frame
	await tree.process_frame
	var finish_gate = main.get_node("TrackManager").finish.get_node("FinishGate")
	var finish_events: Array[int] = []
	finish_gate.crossed.connect(func(player_id: int) -> void: finish_events.append(player_id))
	var car_two = main.get_node("Player2")
	car_two.global_transform = finish_gate.global_transform.translated_local(Vector3(0.0, 0.9, 3.0))
	car_two.velocity = finish_gate.global_basis * Vector3.FORWARD * 12.0
	await tree.physics_frame
	await tree.process_frame
	for _frame_index in 30:
		await tree.physics_frame
		await tree.process_frame
		if game.race_state.finish_times.has(2):
			break
	var trap_received: bool = car_one.low_grip_time_remaining > 0.0 and game.player_states[1].lives == 3
	var finish_received: bool = game.race_state.phase == RaceState.Phase.FINAL_WINDOW and game.race_state.finish_times.has(2)
	var passed := (
		_expect(trap_received, "The composed ice Area3D must receive a real physics body_entered event and apply low grip without life loss; overlaps=%s events=%s grip=%s lives=%s." % [trap.get_overlapping_bodies(), trap_events, car_one.low_grip_time_remaining, game.player_states[1].lives])
		and _expect(finish_received, "The composed finish Area3D must receive a real forward body_entered event and open FINAL_WINDOW; overlaps=%s events=%s velocity=%s local=%s layer=%s mask=%s." % [finish_gate.get_overlapping_bodies(), finish_events, car_two.velocity, finish_gate.to_local(car_two.global_position), car_two.collision_layer, car_two.collision_mask])
	)
	await _free_main(fixture)
	return passed

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
