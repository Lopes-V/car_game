extends RefCounted

const CarController = preload("res://scripts/car/car_controller.gd")
const PlayerRoundState = preload("res://scripts/domain/player_round_state.gd")
const SplitScreenManager = preload("res://scripts/ui/split_screen_manager.gd")
const TrackLayout = preload("res://scripts/domain/track_layout.gd")
const TrackManager = preload("res://scripts/track/track_manager.gd")
const ProgressTracker = preload("res://scripts/domain/progress_tracker.gd")
const RaceCheckpoint = preload("res://scripts/track/race_checkpoint.gd")
const RespawnPoint = preload("res://scripts/track/respawn_point.gd")
const ScoreManager = preload("res://scripts/domain/score_manager.gd")
const RaceState = preload("res://scripts/domain/race_state.gd")
const GameController = preload("res://scripts/game/game_controller.gd")
const BuildManager = preload("res://scripts/build/build_manager.gd")
const TrapController = preload("res://scripts/traps/trap_controller.gd")

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
	all_passed = test_piece_gates_reject_skips_duplicates_and_reverse_progress() and all_passed
	all_passed = test_global_progress_uses_only_current_logical_piece_distance() and all_passed
	all_passed = test_global_progress_does_not_decrease_when_local_distance_moves_backward() and all_passed
	all_passed = test_checkpoint_first_claim_resets_each_round() and all_passed
	all_passed = test_real_triggers_accept_only_forward_car_crossings() and all_passed
	all_passed = test_runtime_output_gates_advance_only_to_an_existing_next_piece() and all_passed
	all_passed = test_initial_respawn_and_runtime_points_have_stable_identity() and all_passed
	all_passed = test_survivor_respawns_dead_opponent_at_opponents_saved_transform() and all_passed
	all_passed = test_all_dead_recovery_excludes_eliminated_players() and all_passed
	all_passed = await test_area_triggers_receive_real_body_entered_events() and all_passed
	all_passed = test_finishers_rank_before_dnfs_and_finish_time_wins() and all_passed
	all_passed = test_exact_rank_ties_use_progress_then_stable_id() and all_passed
	all_passed = test_dnfs_rank_by_progress_then_stable_id() and all_passed
	all_passed = test_score_results_awards_every_source() and all_passed
	all_passed = test_bare_id_score_fixture_remains_compatible() and all_passed
	all_passed = test_current_round_tie_order_is_deterministic() and all_passed
	all_passed = test_finish_round_snapshots_ranks_and_scores_real_round_state() and all_passed
	all_passed = test_target_score_uses_highest_total_after_all_awards() and all_passed
	all_passed = test_equal_target_totals_use_current_round_tie_order() and all_passed
	all_passed = test_round_five_uses_totals_then_current_round_tie_order() and all_passed
	all_passed = test_finish_round_is_idempotent_and_rejects_invalid_phase() and all_passed
	all_passed = test_next_round_and_racing_reset_only_transient_round_state() and all_passed
	all_passed = test_track_build_blocked_ends_once_without_race_awards() and all_passed
	all_passed = test_real_round_one_build_flow_reaches_racing_without_phase_shortcuts() and all_passed
	all_passed = test_failed_build_application_does_not_start_countdown() and all_passed
	all_passed = test_equal_target_tie_uses_progress_after_equivalent_placement() and all_passed
	all_passed = test_equal_target_tie_uses_fewer_deaths_after_equal_progress() and all_passed
	all_passed = test_equal_target_tie_uses_stable_id_after_exact_round_tie() and all_passed
	return all_passed

func test_equal_target_tie_uses_progress_after_equivalent_placement() -> bool:
	var fixture := _create_game_fixture(3)
	var game = fixture["game"]
	var state = fixture["race_state"]
	game.total_scores = {1: 16, 2: 14}
	state.finish_times = {1: 10.0, 2: 10.0}
	fixture["tracker"].high_water_progress_by_player = {1: 70.0, 2: 80.0}
	state.phase = RaceState.Phase.RESULTS
	game.finish_round()
	var passed := (
		_expect(game.total_scores == {1: 20, 2: 20}, "The progress tie fixture must finish on equal target totals.")
		and _expect(game.winner_id == 2, "Equivalent finish placement must next prefer higher meter progress.")
	)
	_free_game_fixture(fixture)
	return passed

func test_equal_target_tie_uses_fewer_deaths_after_equal_progress() -> bool:
	var fixture := _create_game_fixture(3)
	var game = fixture["game"]
	var state = fixture["race_state"]
	game.total_scores = {1: 15, 2: 16}
	state.finish_times = {1: 10.0, 2: 10.0}
	fixture["tracker"].high_water_progress_by_player = {1: 80.0, 2: 80.0}
	fixture["players"][1].deaths = 2
	fixture["players"][2].deaths = 0
	state.phase = RaceState.Phase.RESULTS
	game.finish_round()
	var passed := (
		_expect(game.total_scores == {1: 20, 2: 20}, "The deaths tie fixture must finish on equal target totals.")
		and _expect(game.winner_id == 2, "Equal placement and progress must next prefer fewer deaths, despite display ordering by ID.")
	)
	_free_game_fixture(fixture)
	return passed

func test_equal_target_tie_uses_stable_id_after_exact_round_tie() -> bool:
	var fixture := _create_game_fixture(3)
	var game = fixture["game"]
	var state = fixture["race_state"]
	game.total_scores = {1: 14, 2: 16}
	state.finish_times = {1: 10.0, 2: 10.0}
	fixture["tracker"].high_water_progress_by_player = {1: 80.0, 2: 80.0}
	state.phase = RaceState.Phase.RESULTS
	game.finish_round()
	var passed := (
		_expect(game.total_scores == {1: 20, 2: 20}, "The stable-id fixture must finish on equal target totals.")
		and _expect(game.winner_id == 1, "An exact placement/progress/deaths tie must prefer lower stable id.")
	)
	_free_game_fixture(fixture)
	return passed

func test_real_round_one_build_flow_reaches_racing_without_phase_shortcuts() -> bool:
	var fixture := _create_real_build_game_fixture()
	var game = fixture["game"]
	var state = fixture["race_state"]
	var build = fixture["build_manager"]
	game.start_match()
	var option_id: String = fixture["track_manager"].layout.get_valid_options()[0].variant_id
	var extension_locked: bool = build.submit_extension(1, option_id)
	var modification_locked: bool = build.submit_modification(2, "ice", _initial_slot_ids_for_round_flow())
	var applied: bool = build.reveal_and_apply()
	var countdown_reached: bool = state.phase == RaceState.Phase.COUNTDOWN
	var racing_started: bool = game.start_racing(5.0)
	var passed := (
		_expect(build.builder_player_id == 1 and build.modifier_player_id == 2, "start_match must initialize real round-one roles through BuildManager exactly once.")
		and _expect(extension_locked and modification_locked and applied, "Real secret round-one choices must lock, reveal, and apply successfully.")
		and _expect(countdown_reached, "A successful real build application must enter COUNTDOWN without a test phase assignment.")
		and _expect(racing_started and state.phase == RaceState.Phase.RACING, "The guarded COUNTDOWN boundary must allow GameController to start RACING.")
		and _expect(state.round_number == 1 and is_equal_approx(state.race_end_time, 125.0), "Round one must be initialized once and retain the 120-second racing deadline.")
	)
	_free_real_build_game_fixture(fixture)
	return passed

func test_failed_build_application_does_not_start_countdown() -> bool:
	var fixture := _create_real_build_game_fixture()
	var game = fixture["game"]
	var state = fixture["race_state"]
	var build = fixture["build_manager"]
	var track = fixture["track_manager"]
	game.start_match()
	var option_id: String = track.layout.get_valid_options()[0].variant_id
	build.submit_extension(1, option_id)
	build.submit_modification(2, "dynamite", _initial_slot_ids_for_round_flow())
	for slot_id in _initial_slot_ids_for_round_flow():
		track.occupy_trap_slot(slot_id, TrapController.new("ice"))
	var applied: bool = build.reveal_and_apply()
	var racing_started: bool = game.start_racing(5.0)
	var passed := (
		_expect(not applied, "The real fixture must fail when all phase-snapshot trap preferences become occupied.")
		and _expect(state.phase == RaceState.Phase.APPLY_BUILD, "A failed build application must remain outside COUNTDOWN.")
		and _expect(not racing_started and is_zero_approx(state.race_end_time), "A failed application must not permit RACING or create a deadline.")
	)
	_free_real_build_game_fixture(fixture)
	return passed

func _create_real_build_game_fixture() -> Dictionary:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var root := Node3D.new()
	scene_tree.root.add_child(root)
	var track := TrackManager.new()
	root.add_child(track)
	track.create_initial_track()
	var players := {1: PlayerRoundState.new(), 2: PlayerRoundState.new()}
	var tracker := ProgressTracker.new(track.layout, players)
	track.configure_progress_tracker(tracker)
	var race_state := RaceState.new()
	var build := BuildManager.new(race_state, track)
	root.add_child(build)
	var game := GameController.new(race_state, tracker, players, build)
	root.add_child(game)
	return {
		"root": root,
		"game": game,
		"race_state": race_state,
		"build_manager": build,
		"track_manager": track,
	}

func _free_real_build_game_fixture(fixture: Dictionary) -> void:
	var root: Node3D = fixture["root"]
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.remove_child(root)
	root.free()

func _initial_slot_ids_for_round_flow() -> Array[String]:
	return ["piece_0_slot_0", "piece_0_slot_1", "piece_0_slot_2"]

func test_finishers_rank_before_dnfs_and_finish_time_wins() -> bool:
	var ranked := ScoreManager.rank([
		{"id": 2, "finish_time": -1.0, "progress": 99.0},
		{"id": 1, "finish_time": 12.0, "progress": 30.0},
		{"id": 3, "finish_time": 11.0, "progress": 20.0},
	])
	return _expect(
		_ranked_ids(ranked) == [3, 1, 2],
		"Finishers must precede DNFs, with lower finish time winning among finishers.",
	)

func test_exact_rank_ties_use_progress_then_stable_id() -> bool:
	var ranked := ScoreManager.rank([
		{"id": 3, "finish_time": 10.0, "progress": 50.0},
		{"id": 2, "finish_time": 10.0, "progress": 60.0},
		{"id": 1, "finish_time": 10.0, "progress": 60.0},
	])
	return _expect(
		_ranked_ids(ranked) == [1, 2, 3],
		"Equal finish times must use higher meter progress, then lower stable id.",
	)

func test_dnfs_rank_by_progress_then_stable_id() -> bool:
	var ranked := ScoreManager.rank([
		{"id": 2, "finish_time": -1.0, "progress": 70.0},
		{"id": 3, "finish_time": -1.0, "progress": 80.0},
		{"id": 1, "finish_time": -1.0, "progress": 80.0},
	])
	return _expect(
		_ranked_ids(ranked) == [1, 3, 2],
		"DNFs must rank by higher meter progress, then lower stable id.",
	)

func test_score_results_awards_every_source() -> bool:
	var scores := ScoreManager.score_results(
		[
			{"id": 1, "finish_time": 12.0, "progress": 80.0},
			{"id": 2, "finish_time": -1.0, "progress": 60.0},
		],
		{"checkpoint_1": 1, "checkpoint_2": 1, "checkpoint_3": 2},
		{1: 0, 2: 2},
	)
	return (
		_expect(scores[1] == 8, "First place, finish, two checkpoints, and survival must total eight points.")
		and _expect(scores[2] == 3, "Second place and one checkpoint must total three points without finish/survival bonuses.")
	)

func test_bare_id_score_fixture_remains_compatible() -> bool:
	var scores := ScoreManager.score_results([1, 2], {"checkpoint_1": 1}, {1: 0, 2: 1})
	return _expect(
		scores[1] == 6 and scores[2] == 2,
		"Bare ids are ranked DNFs: the compatibility fixture must award P1 exactly six and no finish bonus.",
	)

func test_current_round_tie_order_is_deterministic() -> bool:
	var ranked := [
		{"id": 2, "finish_time": 15.0, "progress": 50.0},
		{"id": 1, "finish_time": -1.0, "progress": 90.0},
	]
	return _expect(
		ScoreManager.current_round_tie_order(ranked, {1: 0, 2: 3}) == [2, 1],
		"Better current-round rank must lead the match tie order before progress, deaths, and stable id.",
	)

func test_finish_round_snapshots_ranks_and_scores_real_round_state() -> bool:
	var fixture := _create_game_fixture(3)
	var game = fixture["game"]
	var state = fixture["race_state"]
	var tracker = fixture["tracker"]
	state.finish_times = {1: 18.0}
	state.phase = RaceState.Phase.RESULTS
	tracker.high_water_progress_by_player = {1: 55.0, 2: 80.0}
	tracker.claimed_checkpoints = {"checkpoint_1": 2}
	fixture["players"][2].deaths = 1
	game.finish_round()
	tracker.high_water_progress_by_player[1] = 999.0
	fixture["players"][1].deaths = 2
	var passed := (
		_expect(_ranked_ids(game.current_ranked_results) == [1, 2], "A finisher must rank ahead of a farther DNF in the round snapshot.")
		and _expect(game.current_ranked_results[0]["progress"] == 55.0, "Round results must retain the immutable meter snapshot used for scoring.")
		and _expect(game.current_round_scores == {1: 6, 2: 3}, "Finish, placement, checkpoint, and survival sources must produce exact round awards.")
		and _expect(game.total_scores == {1: 6, 2: 3}, "Round awards must be added to cumulative match totals exactly once.")
		and _expect(state.phase == RaceState.Phase.NEXT_ROUND, "A non-terminal scored round must stop at NEXT_ROUND.")
	)
	_free_game_fixture(fixture)
	return passed

func test_target_score_uses_highest_total_after_all_awards() -> bool:
	var fixture := _create_game_fixture(3)
	var game = fixture["game"]
	var state = fixture["race_state"]
	game.total_scores = {1: 15, 2: 19}
	state.finish_times = {1: 10.0, 2: 12.0}
	state.phase = RaceState.Phase.RESULTS
	game.finish_round()
	var passed := (
		_expect(game.total_scores == {1: 21, 2: 23}, "All round awards must apply before simultaneous target evaluation.")
		and _expect(game.winner_id == 2, "When both reach target, the higher cumulative total must beat current-round rank.")
		and _expect(game.end_reason == "TARGET_SCORE", "A target-score victory must expose a stable textual end reason.")
		and _expect(state.phase == RaceState.Phase.MATCH_END, "A resolved target winner must end the match.")
	)
	_free_game_fixture(fixture)
	return passed

func test_equal_target_totals_use_current_round_tie_order() -> bool:
	var fixture := _create_game_fixture(2)
	var game = fixture["game"]
	var state = fixture["race_state"]
	game.total_scores = {1: 17, 2: 14}
	state.finish_times = {2: 9.0}
	state.phase = RaceState.Phase.RESULTS
	game.finish_round()
	var passed := (
		_expect(game.total_scores == {1: 20, 2: 20}, "The fixture must produce equal totals at or above the target.")
		and _expect(game.winner_id == 2, "Equal target totals must select the better current-round rank, not stable id.")
	)
	_free_game_fixture(fixture)
	return passed

func test_round_five_uses_totals_then_current_round_tie_order() -> bool:
	var fixture := _create_game_fixture(5)
	var game = fixture["game"]
	var state = fixture["race_state"]
	game.total_scores = {1: 7, 2: 4}
	state.finish_times = {2: 20.0}
	state.phase = RaceState.Phase.RESULTS
	game.finish_round()
	var passed := (
		_expect(game.total_scores == {1: 10, 2: 10}, "The fifth-round fixture must remain below target with equal cumulative totals.")
		and _expect(game.winner_id == 2, "A fifth-round total tie must use the same current-round tie order.")
		and _expect(game.end_reason == "MAX_ROUNDS", "A fifth-round decision must expose the maximum-round end reason.")
		and _expect(state.phase == RaceState.Phase.MATCH_END, "The fifth scored round must end the match.")
	)
	_free_game_fixture(fixture)
	return passed

func test_finish_round_is_idempotent_and_rejects_invalid_phase() -> bool:
	var fixture := _create_game_fixture(2)
	var game = fixture["game"]
	var state = fixture["race_state"]
	game.finish_round()
	var before_valid: Dictionary = game.total_scores.duplicate()
	state.finish_times = {1: 5.0}
	state.phase = RaceState.Phase.RESULTS
	game.finish_round()
	var after_valid: Dictionary = game.total_scores.duplicate()
	game.finish_round()
	state.record_finish(2, 6.0)
	var passed := (
		_expect(before_valid == {1: 0, 2: 0}, "finish_round outside RESULTS must not award points.")
		and _expect(after_valid == {1: 6, 2: 3}, "The one valid finish_round call must award the exact result once.")
		and _expect(game.total_scores == after_valid, "Repeated finish_round and late terminal calls must be idempotent.")
		and _expect(not state.finish_times.has(2), "Finish crossings after the results transition must be ignored.")
	)
	_free_game_fixture(fixture)
	return passed

func test_next_round_and_racing_reset_only_transient_round_state() -> bool:
	var fixture := _create_game_fixture(1)
	var game = fixture["game"]
	var state = fixture["race_state"]
	var tracker = fixture["tracker"]
	var players: Dictionary = fixture["players"]
	players[1].lose_life()
	players[2].try_consume_boost()
	tracker.claimed_checkpoints = {"checkpoint_1": 1}
	tracker.activated_respawns_by_player[1] = {"respawn_1": true}
	state.phase = RaceState.Phase.NEXT_ROUND
	var initial_safe := Transform3D(Basis.IDENTITY, Vector3(4.0, 1.0, -3.0))
	var advanced: bool = game.begin_next_round(initial_safe)
	state.phase = RaceState.Phase.COUNTDOWN
	var started: bool = game.start_racing(30.0)
	var passed := (
		_expect(advanced and state.round_number == 2 and state.phase == RaceState.Phase.RACING, "Next-round and racing APIs must advance through the explicit pre-race boundary.")
		and _expect(players[1].lives == 3 and players[1].deaths == 0 and players[2].boost_charges == 1, "A new round must restore lives, deaths, and the one boost charge.")
		and _expect(players[1].last_safe_respawn == initial_safe and players[2].last_safe_respawn == initial_safe, "Both players must reset to TrackStart's safe transform.")
		and _expect(tracker.claimed_checkpoints.is_empty() and tracker.activated_respawns_by_player[1].is_empty(), "Starting RACING must reset checkpoint and respawn claims.")
		and _expect(is_equal_approx(state.race_end_time, 150.0), "Starting RACING must establish the 120-second hard deadline.")
	)
	_free_game_fixture(fixture)
	return passed

func test_track_build_blocked_ends_once_without_race_awards() -> bool:
	var race_state := RaceState.new()
	race_state.begin_round(2)
	var track_manager := TrackManager.new()
	var build_manager := BuildManager.new(race_state, track_manager)
	var players := {1: PlayerRoundState.new(), 2: PlayerRoundState.new()}
	var tracker := ProgressTracker.new(null, players)
	var game := GameController.new(race_state, tracker, players, build_manager)
	game.total_scores = {1: 7, 2: 5}
	var transitions: Array = []
	race_state.phase_changed.connect(func(_previous: int, current: int) -> void: transitions.append(current))
	build_manager.track_build_blocked.emit()
	build_manager.track_build_blocked.emit()
	var passed := (
		_expect(game.total_scores == {1: 7, 2: 5} and game.current_round_scores.is_empty(), "A blocked unrun race must not fabricate scoring events.")
		and _expect(game.winner_id == 1 and game.end_reason == "TRACK_BUILD_BLOCKED", "Blocked construction must end deterministically from existing totals.")
		and _expect(transitions == [RaceState.Phase.RESULTS, RaceState.Phase.MATCH_END], "Blocked construction must pass through controlled RESULTS and MATCH_END exactly once.")
	)
	game.free()
	build_manager.free()
	track_manager.free()
	return passed

func _create_game_fixture(round_number: int) -> Dictionary:
	var layout = TrackLayout.with_initial_straight()
	var players := {1: PlayerRoundState.new(), 2: PlayerRoundState.new()}
	players[1].reset_for_round()
	players[2].reset_for_round()
	var tracker := ProgressTracker.new(layout, players)
	var race_state := RaceState.new()
	race_state.begin_round(round_number)
	var game := GameController.new(race_state, tracker, players)
	return {"game": game, "race_state": race_state, "tracker": tracker, "players": players}

func _free_game_fixture(fixture: Dictionary) -> void:
	fixture["game"].free()

func _ranked_ids(ranked: Array) -> Array:
	var ids: Array = []
	for result in ranked:
		ids.append(result["id"])
	return ids

func test_piece_gates_reject_skips_duplicates_and_reverse_progress() -> bool:
	var fixture := _create_progress_fixture(3)
	var tracker = fixture["tracker"]
	return (
		_expect(not tracker.record_piece_gate(1, 2), "A player must not skip directly to a later logical piece.")
		and _expect(tracker.record_piece_gate(1, 1), "The immediate next logical piece must be accepted.")
		and _expect(not tracker.record_piece_gate(1, 1), "A duplicate piece gate must be ignored.")
		and _expect(not tracker.record_piece_gate(1, 0), "A reverse piece gate must be ignored.")
		and _expect(is_equal_approx(tracker.global_progress(1, 4.0), 24.0), "Rejected gates must not decrease or skip the player's logical progress.")
	)

func test_global_progress_uses_only_current_logical_piece_distance() -> bool:
	var fixture := _create_progress_fixture(3)
	var tracker = fixture["tracker"]
	tracker.record_piece_gate(1, 1)
	return (
		_expect(is_equal_approx(tracker.global_progress(1, 3.0), 23.0), "Local path distance must be added to the current piece's accumulated meter length.")
		and _expect(is_equal_approx(tracker.global_progress(1, 999.0), 40.0), "Local distance must clamp to the current piece instead of projecting onto a nearby later piece.")
	)

func test_global_progress_does_not_decrease_when_local_distance_moves_backward() -> bool:
	var fixture := _create_progress_fixture(3)
	var tracker = fixture["tracker"]
	var forward_progress: float = tracker.global_progress(1, 15.0)
	var backward_sample: float = tracker.global_progress(1, 3.0)
	tracker.record_piece_gate(1, 1)
	var next_piece_start: float = tracker.global_progress(1, 0.0)
	tracker.reset_round_claims()
	var reset_progress: float = tracker.global_progress(1, 2.0)
	return (
		_expect(is_equal_approx(forward_progress, 15.0), "A forward sample must establish the player's meter high-water mark.")
		and _expect(is_equal_approx(backward_sample, 15.0), "Driving backward on the same piece must not decrease timeout-ranking progress.")
		and _expect(is_equal_approx(next_piece_start, 20.0), "Entering the next piece must advance the high-water mark to that piece's accumulated start distance.")
		and _expect(is_equal_approx(reset_progress, 2.0), "Starting a new round must clear the prior race's progress high-water mark.")
	)

func test_checkpoint_first_claim_resets_each_round() -> bool:
	var fixture := _create_progress_fixture(2)
	var tracker = fixture["tracker"]
	var first_claim: bool = tracker.try_claim_checkpoint(1, "checkpoint_1", 1)
	var duplicate_claim: bool = tracker.try_claim_checkpoint(2, "checkpoint_1", 1)
	var first_respawn: bool = tracker.try_activate_respawn(1, "respawn_0", 0)
	var duplicate_respawn: bool = tracker.try_activate_respawn(1, "respawn_0", 0)
	tracker.record_piece_gate(1, 1)
	tracker.reset_round_claims()
	var next_round_claim: bool = tracker.try_claim_checkpoint(2, "checkpoint_1", 1)
	var next_round_respawn: bool = tracker.try_activate_respawn(1, "respawn_0", 0)
	return (
		_expect(first_claim, "The first valid player must claim a checkpoint.")
		and _expect(not duplicate_claim, "A checkpoint must award only one first claim per round.")
		and _expect(next_round_claim, "Resetting round claims must rearm persistent checkpoint nodes.")
		and _expect(first_respawn and not duplicate_respawn and next_round_respawn, "Round reset must clear each player's respawn activation set.")
		and _expect(tracker.current_piece_indexes[1] == 0, "A new race must reset each player's logical progress to TrackStart.")
	)

func test_real_triggers_accept_only_forward_car_crossings() -> bool:
	var fixture := _create_progress_fixture(2)
	var tracker = fixture["tracker"]
	var scene_tree := Engine.get_main_loop() as SceneTree
	var trigger_root := Node3D.new()
	scene_tree.root.add_child(trigger_root)
	var checkpoint = RaceCheckpoint.new()
	var respawn = RespawnPoint.new()
	trigger_root.add_child(checkpoint)
	trigger_root.add_child(respawn)
	checkpoint.configure("checkpoint_0", 0, tracker)
	respawn.configure("respawn_0", 0, tracker, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -2.0)))
	var car := CarController.new()
	car.configure(1, "p1")
	car.velocity = Vector3(0.0, 0.0, 5.0)
	var reverse_checkpoint: bool = checkpoint.handle_body_crossing(car)
	var reverse_respawn: bool = respawn.handle_body_crossing(car)
	car.velocity = Vector3(0.0, 0.0, -5.0)
	var forward_checkpoint: bool = checkpoint.handle_body_crossing(car)
	var forward_respawn: bool = respawn.handle_body_crossing(car)
	var repeated_respawn: bool = respawn.handle_body_crossing(car)
	car.free()
	scene_tree.root.remove_child(trigger_root)
	trigger_root.free()
	return (
		_expect(not reverse_checkpoint and not reverse_respawn, "Reverse crossings of real Area3D triggers must be ignored.")
		and _expect(forward_checkpoint and forward_respawn, "Forward crossings must reach checkpoint and respawn domain rules.")
		and _expect(not repeated_respawn, "A respawn point must activate at most once per player per round.")
	)

func test_initial_respawn_and_runtime_points_have_stable_identity() -> bool:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var manager = TrackManager.new()
	scene_tree.root.add_child(manager)
	manager.create_initial_track()
	var initial = manager.get_node_or_null("InitialRespawnPoint")
	var option = manager.layout.get_valid_options()[0]
	manager.apply_extension(option)
	var checkpoint = manager.get_node_or_null("Pieces/TrackPiece_1/SafeRespawnZone/RaceCheckpoint")
	var respawn = manager.get_node_or_null("Pieces/TrackPiece_1/SafeRespawnZone/RespawnPoint")
	var progress_fixture := _create_progress_fixture(2)
	manager.configure_progress_tracker(progress_fixture["tracker"])
	progress_fixture["players"][1].last_safe_respawn = Transform3D(Basis.IDENTITY, Vector3(9.0, 0.0, 9.0))
	progress_fixture["tracker"].reset_round_claims()
	var passed := (
		_expect(initial is RespawnPoint and initial.point_id == "respawn_initial" and initial.piece_index == 0, "TrackStart must expose one scripted initial safe respawn with stable identity.")
		and _expect(checkpoint is RaceCheckpoint and checkpoint.checkpoint_id == "checkpoint_1", "Checkpoint nodes must use scripted stable piece-index ids.")
		and _expect(respawn is RespawnPoint and respawn.point_id == "respawn_1", "Respawn nodes must persist with stable piece-index ids.")
		and _expect(checkpoint.progress_tracker == progress_fixture["tracker"] and respawn.progress_tracker == progress_fixture["tracker"], "Configuring the manager must bind every persistent nested trigger to the tracker.")
		and _expect(progress_fixture["players"][1].last_safe_respawn == initial.safe_transform, "Every new race must restore TrackStart as the player's initial safe respawn.")
	)
	scene_tree.root.remove_child(manager)
	manager.free()
	return passed

func test_runtime_output_gates_advance_only_to_an_existing_next_piece() -> bool:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var manager = TrackManager.new()
	scene_tree.root.add_child(manager)
	manager.create_initial_track()
	manager.apply_extension(manager.layout.get_valid_options()[0])
	var players := {1: PlayerRoundState.new(), 2: PlayerRoundState.new()}
	players[1].reset_for_round()
	players[2].reset_for_round()
	var tracker = ProgressTracker.new(manager.layout, players)
	manager.configure_progress_tracker(tracker)
	var car := CarController.new()
	car.configure(1, "p1")
	manager.add_child(car)
	car.velocity = Vector3(0.0, 0.0, -5.0)
	var first_gate: Area3D = manager.get_node("Pieces/TrackPiece_0/OutputGate")
	first_gate.body_entered.emit(car)
	var advanced_once: bool = tracker.current_piece_indexes[1] == 1
	car.velocity = Vector3(0.0, 0.0, 5.0)
	first_gate.body_entered.emit(car)
	var reverse_ignored: bool = tracker.current_piece_indexes[1] == 1
	car.velocity = Vector3(0.0, 0.0, -5.0)
	var last_gate: Area3D = manager.get_node("Pieces/TrackPiece_1/OutputGate")
	last_gate.body_entered.emit(car)
	var nonexistent_next_ignored: bool = tracker.current_piece_indexes[1] == 1
	scene_tree.root.remove_child(manager)
	manager.free()
	return (
		_expect(advanced_once, "A forward output gate crossing must enter exactly the existing immediate next piece.")
		and _expect(reverse_ignored, "A reverse output gate crossing must not change logical progress.")
		and _expect(nonexistent_next_ignored, "The final output gate must not advance beyond the current layout chain.")
	)

func test_survivor_respawns_dead_opponent_at_opponents_saved_transform() -> bool:
	var fixture := _create_progress_fixture(2)
	var tracker = fixture["tracker"]
	var players: Dictionary = fixture["players"]
	var p1_safe := Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, -4.0))
	var p2_safe := Transform3D(Basis.IDENTITY, Vector3(-3.0, 0.0, -7.0))
	players[1].last_safe_respawn = p1_safe
	players[2].last_safe_respawn = p2_safe
	players[2].lose_life()
	var requests: Array = []
	tracker.respawn_requested.connect(func(player_id: int, safe_transform: Transform3D): requests.append([player_id, safe_transform]))
	var activated: bool = tracker.try_activate_respawn(1, "respawn_0", 0, p1_safe)
	return (
		_expect(activated, "A live player's first valid respawn crossing must activate.")
		and _expect(requests == [[2, p2_safe]], "A survivor must request the dead opponent's own saved transform, never the activator's point.")
		and _expect(not players[2].is_dead, "Issuing a valid respawn must restore the opponent's round state.")
	)

func test_all_dead_recovery_excludes_eliminated_players() -> bool:
	var fixture := _create_progress_fixture(2)
	var tracker = fixture["tracker"]
	var players: Dictionary = fixture["players"]
	var p1_safe := Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, -1.0))
	var p2_safe := Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, -2.0))
	players[1].last_safe_respawn = p1_safe
	players[2].last_safe_respawn = p2_safe
	players[1].lose_life()
	for life in range(3):
		if life > 0:
			players[2].respawn(p2_safe)
		players[2].lose_life()
	var requests: Array = []
	tracker.respawn_requested.connect(func(player_id: int, safe_transform: Transform3D): requests.append([player_id, safe_transform]))
	var recovered: bool = tracker.resolve_all_dead()
	return (
		_expect(recovered, "All-dead resolution must recover every non-eliminated dead player.")
		and _expect(requests == [[1, p1_safe]], "All-dead recovery must use each eligible player's saved transform and exclude eliminated players.")
		and _expect(not players[1].is_dead and players[2].is_eliminated, "Recovery must revive eligible state without reviving eliminated state.")
	)

func test_area_triggers_receive_real_body_entered_events() -> bool:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var root := Node3D.new()
	scene_tree.root.add_child(root)
	var fixture := _create_progress_fixture(2)
	var tracker = fixture["tracker"]
	var checkpoint := RaceCheckpoint.new()
	checkpoint.configure("checkpoint_physics", 0, tracker)
	_add_trigger_shape(checkpoint)
	root.add_child(checkpoint)
	var respawn := RespawnPoint.new()
	respawn.position.x = 10.0
	respawn.configure("respawn_physics", 0, tracker, Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 0.0)))
	_add_trigger_shape(respawn)
	root.add_child(respawn)
	var car_scene := load("res://scenes/car/car.tscn") as PackedScene
	var car = car_scene.instantiate()
	car.configure(1, "p1")
	root.add_child(car)
	var checkpoint_crossings: Array = []
	var respawn_crossings: Array = []
	checkpoint.crossed.connect(func(player_id: int, checkpoint_id: String, piece_index: int): checkpoint_crossings.append([player_id, checkpoint_id, piece_index]))
	respawn.crossed.connect(func(player_id: int, point_id: String, piece_index: int): respawn_crossings.append([player_id, point_id, piece_index]))

	car.position = Vector3(0.0, 0.0, 5.0)
	car.velocity = Vector3(0.0, 0.0, 5.0)
	await _complete_physics_step(scene_tree)
	car.position = Vector3.ZERO
	await _complete_physics_step(scene_tree)
	var reverse_checkpoint_ignored := checkpoint_crossings.is_empty()
	car.position = Vector3(0.0, 0.0, 5.0)
	await _complete_physics_step(scene_tree)
	car.velocity = Vector3(0.0, 0.0, -5.0)
	car.position = Vector3.ZERO
	await _complete_physics_step(scene_tree)
	var forward_checkpoint_received := checkpoint_crossings == [[1, "checkpoint_physics", 0]]

	car.position = Vector3(10.0, 0.0, 5.0)
	car.velocity = Vector3(0.0, 0.0, 5.0)
	await _complete_physics_step(scene_tree)
	car.position = Vector3(10.0, 0.0, 0.0)
	await _complete_physics_step(scene_tree)
	var reverse_respawn_ignored := respawn_crossings.is_empty()
	car.position = Vector3(10.0, 0.0, 5.0)
	await _complete_physics_step(scene_tree)
	car.velocity = Vector3(0.0, 0.0, -5.0)
	car.position = Vector3(10.0, 0.0, 0.0)
	await _complete_physics_step(scene_tree)
	var forward_respawn_received := respawn_crossings == [[1, "respawn_physics", 0]]

	scene_tree.root.remove_child(root)
	root.free()
	return (
		_expect(reverse_checkpoint_ignored and reverse_respawn_ignored, "Real body_entered events must ignore reverse-moving configured cars.")
		and _expect(forward_checkpoint_received and forward_respawn_received, "_ready bindings must forward real body_entered events for forward-moving configured cars; checkpoint=%s respawn=%s." % [checkpoint_crossings, respawn_crossings])
	)

func _add_trigger_shape(trigger: Area3D) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 4.0, 2.0)
	collision.shape = shape
	trigger.add_child(collision)

func _complete_physics_step(scene_tree: SceneTree) -> void:
	await scene_tree.physics_frame
	await scene_tree.process_frame

func _create_progress_fixture(piece_count: int) -> Dictionary:
	var layout = TrackLayout.with_initial_straight()
	while layout.pieces.size() < piece_count:
		var options = layout.get_valid_options()
		var straight = options.filter(func(option): return option.variant_id == "straight")[0]
		layout.append(straight)
	var players := {1: PlayerRoundState.new(), 2: PlayerRoundState.new()}
	players[1].reset_for_round()
	players[2].reset_for_round()
	return {"tracker": ProgressTracker.new(layout, players), "players": players}

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
