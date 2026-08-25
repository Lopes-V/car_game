class_name RaceHUD
extends CanvasLayer

signal extension_locked(option_id: String)
signal modification_locked(trap_id: String, slot_ids: Array[String])
signal reveal_requested()
signal continue_requested()

@onready var phase_label: Label = %PhaseLabel
@onready var timer_label: Label = %TimerLabel
@onready var player_one_label: Label = %PlayerOneLabel
@onready var player_two_label: Label = %PlayerTwoLabel
@onready var build_panel: PanelContainer = %BuildPanel
@onready var build_prompt: Label = %BuildPrompt
@onready var extension_select: OptionButton = %ExtensionSelect
@onready var trap_select: OptionButton = %TrapSelect
@onready var slot_one: OptionButton = %SlotOne
@onready var slot_two: OptionButton = %SlotTwo
@onready var slot_three: OptionButton = %SlotThree
@onready var lock_button: Button = %LockButton
@onready var reveal_panel: PanelContainer = %RevealPanel
@onready var reveal_label: Label = %RevealLabel
@onready var reveal_button: Button = %RevealButton
@onready var countdown_label: Label = %CountdownLabel
@onready var results_panel: PanelContainer = %ResultsPanel
@onready var results_label: Label = %ResultsLabel
@onready var continue_button: Button = %ContinueButton

var _builder_id := 0
var _modifier_id := 0
var _awaiting_modifier := false
var _extension_locked := false
var _modification_locked := false

func _ready() -> void:
	layer = 10
	lock_button.pressed.connect(_on_lock_pressed)
	reveal_button.pressed.connect(func() -> void: reveal_requested.emit())
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	_hide_phase_panels()

func show_build_state(builder_id: int, modifier_id: int, option_ids: Array[String], slot_ids: Array[String]) -> void:
	_builder_id = builder_id
	_modifier_id = modifier_id
	_awaiting_modifier = false
	_extension_locked = false
	_modification_locked = false
	_fill(extension_select, option_ids)
	_fill(slot_one, slot_ids)
	_fill(slot_two, slot_ids)
	_fill(slot_three, slot_ids)
	if slot_ids.size() >= 3:
		slot_one.select(0)
		slot_two.select(1)
		slot_three.select(2)
	trap_select.select(0)
	build_prompt.text = "Jogador %d: escolha a extensao em segredo" % builder_id
	_set_extension_controls_visible(true)
	build_panel.visible = true
	reveal_panel.visible = false
	results_panel.visible = false
	countdown_label.visible = false
	lock_button.disabled = option_ids.is_empty()

func show_reveal(extension_id: String, trap_id: String, slot_priorities: Array[String]) -> void:
	build_panel.visible = false
	reveal_panel.visible = true
	var priority_lines: Array[String] = []
	for priority_index in slot_priorities.size():
		priority_lines.append("%d. %s" % [priority_index + 1, slot_priorities[priority_index]])
	reveal_label.text = "Revelado:\nExtensao: %s\nArmadilha: %s\nPrioridades:\n%s" % [
		extension_id,
		trap_id,
		"\n".join(priority_lines),
	]
	reveal_button.disabled = false

func show_countdown(seconds_remaining: float) -> void:
	_hide_phase_panels()
	countdown_label.visible = true
	countdown_label.text = str(maxi(ceili(seconds_remaining), 1))

func show_race_state(phase_name: String, seconds_remaining: float, states: Dictionary, scores: Dictionary) -> void:
	_hide_phase_panels()
	phase_label.text = phase_name
	timer_label.text = "Tempo: %.1f" % maxf(seconds_remaining, 0.0)
	player_one_label.text = _player_line(1, states, scores)
	player_two_label.text = _player_line(2, states, scores)

func show_results(order: Array, awards: Dictionary, scores: Dictionary, winner_id: int, reason: String, can_continue: bool) -> void:
	_hide_phase_panels()
	results_panel.visible = true
	phase_label.text = "NEXT_ROUND - RESULTS" if can_continue else "MATCH_END - %s" % reason
	var lines: Array[String] = []
	if reason == "TRACK_BUILD_BLOCKED":
		lines.append("TRACK_BUILD_BLOCKED")
	else:
		for index in order.size():
			var entry = order[index]
			var player_id := int(entry.get("id", 0)) if entry is Dictionary else int(entry)
			lines.append("%d. P%d  +%d  total %d" % [index + 1, player_id, int(awards.get(player_id, 0)), int(scores.get(player_id, 0))])
	if winner_id > 0:
		lines.append("Vencedor: P%d (%s)" % [winner_id, reason])
	results_label.text = "\n".join(lines)
	continue_button.visible = can_continue
	continue_button.disabled = not can_continue

func set_phase_text(value: String) -> void:
	phase_label.text = value

func _on_lock_pressed() -> void:
	if not _awaiting_modifier:
		if extension_select.item_count == 0:
			return
		_extension_locked = true
		extension_locked.emit(extension_select.get_item_text(extension_select.selected))
		_awaiting_modifier = true
		build_prompt.text = "Passe para o Jogador %d: escolha a sabotagem" % _modifier_id
		_set_extension_controls_visible(false)
		lock_button.disabled = false
		return
	if _modification_locked:
		return
	var chosen: Array[String] = []
	for select in [slot_one, slot_two, slot_three]:
		if select.item_count == 0:
			continue
		var slot_id: String = select.get_item_text(select.selected)
		if not chosen.has(slot_id):
			chosen.append(slot_id)
	if slot_one.item_count < 3:
		chosen.clear()
		for item_index in slot_one.item_count:
			chosen.append(slot_one.get_item_text(item_index))
	var unique := {}
	for slot_id in chosen:
		unique[slot_id] = true
	if slot_one.item_count >= 3 and unique.size() != 3:
		build_prompt.text = "Escolha tres slots diferentes"
		return
	_modification_locked = true
	lock_button.disabled = true
	modification_locked.emit(trap_select.get_item_text(trap_select.selected), chosen)

func show_build_error(message: String) -> void:
	_modification_locked = false
	lock_button.disabled = false
	build_prompt.text = message

func _set_extension_controls_visible(extension_turn: bool) -> void:
	extension_select.visible = extension_turn
	trap_select.visible = not extension_turn
	slot_one.visible = not extension_turn
	slot_two.visible = not extension_turn
	slot_three.visible = not extension_turn

func _fill(select: OptionButton, values: Array[String]) -> void:
	select.clear()
	for value in values:
		select.add_item(value)

func _hide_phase_panels() -> void:
	build_panel.visible = false
	reveal_panel.visible = false
	countdown_label.visible = false
	results_panel.visible = false

func _player_line(player_id: int, states: Dictionary, scores: Dictionary) -> String:
	var state = states.get(player_id)
	var lives := int(state.lives) if state != null else 0
	var boosts := int(state.boost_charges) if state != null else 0
	return "P%d  Vidas %d  Boost %d  Pontos %d" % [player_id, lives, boosts, int(scores.get(player_id, 0))]
