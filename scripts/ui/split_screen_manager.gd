class_name SplitScreenManager
extends Control

const PLAYER_IDS: Array[int] = [1, 2]
const CAMERA_OFFSET := Vector3(0.0, 4.0, 8.0)
const CAMERA_LOOK_HEIGHT := Vector3(0.0, 1.0, 0.0)

var _viewports: Dictionary = {}
var _cameras: Dictionary = {}
var _targets: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_viewport(1, "TopView", 0.0, 0.5)
	_ensure_viewport(2, "BottomView", 0.5, 1.0)

func configure(first_target: Node3D, second_target: Node3D) -> void:
	_ensure_viewport(1, "TopView", 0.0, 0.5)
	_ensure_viewport(2, "BottomView", 0.5, 1.0)
	_targets[1] = first_target
	_targets[2] = second_target
	_share_main_world()
	_update_cameras()

func get_viewport_for_player(player_id: int) -> SubViewport:
	return _viewports.get(player_id) as SubViewport

func get_camera_for_player(player_id: int) -> Camera3D:
	return _cameras.get(player_id) as Camera3D

func get_target_for_player(player_id: int) -> Node3D:
	return _targets.get(player_id) as Node3D

func _process(_delta: float) -> void:
	_update_cameras()

func _ensure_viewport(player_id: int, container_name: String, top_anchor: float, bottom_anchor: float) -> void:
	if _viewports.has(player_id):
		return
	var container := SubViewportContainer.new()
	container.name = container_name
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.anchor_top = top_anchor
	container.anchor_bottom = bottom_anchor
	container.stretch = true
	add_child(container)

	var player_viewport := SubViewport.new()
	player_viewport.name = "Player%dViewport" % player_id
	player_viewport.size = Vector2i(2, 2)
	player_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(player_viewport)

	var camera := Camera3D.new()
	camera.name = "Player%dCamera" % player_id
	camera.current = true
	player_viewport.add_child(camera)
	_viewports[player_id] = player_viewport
	_cameras[player_id] = camera

func _share_main_world() -> void:
	var shared_world := get_viewport().world_3d
	for player_id in PLAYER_IDS:
		var player_viewport := get_viewport_for_player(player_id)
		if player_viewport != null:
			player_viewport.world_3d = shared_world

func _update_cameras() -> void:
	for player_id in PLAYER_IDS:
		var target := get_target_for_player(player_id)
		var camera := get_camera_for_player(player_id)
		if target == null or camera == null:
			continue
		camera.global_position = target.global_transform * CAMERA_OFFSET
		camera.look_at(target.global_position + CAMERA_LOOK_HEIGHT, Vector3.UP)
