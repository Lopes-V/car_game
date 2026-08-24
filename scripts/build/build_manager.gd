class_name BuildManager
extends Node

const BuildOption = preload("res://scripts/domain/build_choice.gd")
const RaceState = preload("res://scripts/domain/race_state.gd")
const TrackManager = preload("res://scripts/track/track_manager.gd")
const TrapController = preload("res://scripts/traps/trap_controller.gd")
const TRAP_SCENES := {
	"ice": preload("res://scenes/traps/ice.tscn"),
	"dynamite": preload("res://scenes/traps/dynamite.tscn"),
}

signal choice_locked(player_id: int)
signal choices_revealed(extension_id: String, trap_id: String)
signal build_applied(success: bool)
signal track_build_blocked()

var race_state: RaceState
var track_manager: TrackManager
var builder_player_id := 0
var modifier_player_id := 0

var _phase_started := false
var _option_snapshot: Dictionary = {}
var _slot_id_snapshot: Dictionary = {}
var _extension_choice: BuildOption
var _trap_choice := ""
var _slot_priorities: Array[String] = []

func _init(configured_race_state: RaceState, configured_track_manager: TrackManager) -> void:
	race_state = configured_race_state
	track_manager = configured_track_manager

func begin_secret_phase(round_number: int) -> bool:
	_clear_secret_choices()
	_phase_started = false
	if race_state == null or track_manager == null or track_manager.layout == null:
		return false

	race_state.begin_round(round_number)
	builder_player_id = 1 if round_number % 2 == 1 else 2
	modifier_player_id = 2 if builder_player_id == 1 else 1

	for option in track_manager.layout.get_valid_options():
		_option_snapshot[option.variant_id] = option
	for slot in track_manager.get_existing_trap_slots():
		if slot.get_meta("occupied", false) == true:
			continue
		var slot_id := String(slot.get_meta("slot_id", ""))
		if not slot_id.is_empty():
			_slot_id_snapshot[slot_id] = true

	if _option_snapshot.is_empty():
		track_build_blocked.emit()
		return false
	_phase_started = true
	return true

func submit_extension(player_id: int, option_id: String) -> bool:
	if not _can_submit(player_id, builder_player_id) or _extension_choice != null:
		return false
	if not _option_snapshot.has(option_id):
		return false
	_extension_choice = _option_snapshot[option_id]
	choice_locked.emit(player_id)
	return true

func submit_modification(player_id: int, trap_id: String, preferred_slot_ids: Array[String]) -> bool:
	if not _can_submit(player_id, modifier_player_id) or not _trap_choice.is_empty():
		return false
	if not TRAP_SCENES.has(trap_id) or preferred_slot_ids.size() != 3:
		return false
	var distinct_slot_ids: Dictionary = {}
	for slot_id in preferred_slot_ids:
		if distinct_slot_ids.has(slot_id) or not _slot_id_snapshot.has(slot_id):
			return false
		distinct_slot_ids[slot_id] = true
	_trap_choice = trap_id
	_slot_priorities = preferred_slot_ids.duplicate()
	choice_locked.emit(player_id)
	return true

func reveal_and_apply() -> bool:
	if (
		not _phase_started
		or race_state.phase != RaceState.Phase.BUILD_SECRET
		or _extension_choice == null
		or _trap_choice.is_empty()
	):
		return false

	race_state.phase = RaceState.Phase.REVEAL
	choices_revealed.emit(_extension_choice.variant_id, _trap_choice)
	race_state.phase = RaceState.Phase.APPLY_BUILD
	_phase_started = false

	var extension_applied := track_manager.apply_extension(_extension_choice)
	var trap_applied := extension_applied and _install_trap()
	var success := extension_applied and trap_applied
	build_applied.emit(success)
	return success

func reset_traps_for_racing() -> void:
	if track_manager == null:
		return
	for slot in track_manager.get_existing_trap_slots():
		for child in slot.get_children():
			if child is TrapController:
				child.reset_for_round()

func get_extension_option_ids() -> Array[String]:
	var ids: Array[String] = []
	for option_id in _option_snapshot:
		ids.append(String(option_id))
	ids.sort()
	return ids

func get_available_slot_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot_id in _slot_id_snapshot:
		ids.append(String(slot_id))
	ids.sort()
	return ids

func _can_submit(player_id: int, assigned_player_id: int) -> bool:
	return (
		_phase_started
		and race_state != null
		and race_state.phase == RaceState.Phase.BUILD_SECRET
		and player_id == assigned_player_id
	)

func _install_trap() -> bool:
	for slot_id in _slot_priorities:
		if not _slot_id_snapshot.has(slot_id):
			continue
		var trap: TrapController = TRAP_SCENES[_trap_choice].instantiate()
		if track_manager.occupy_trap_slot(slot_id, trap):
			return true
		trap.free()
	return false

func _clear_secret_choices() -> void:
	_option_snapshot.clear()
	_slot_id_snapshot.clear()
	_extension_choice = null
	_trap_choice = ""
	_slot_priorities.clear()
