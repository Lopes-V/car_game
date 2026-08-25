class_name TrackPiece
extends Node3D

const BuildOption = preload("res://scripts/domain/build_choice.gd")
const Constants = preload("res://scripts/domain/race_constants.gd")

const ROAD_HEIGHT := 0.5
const CURVE_SEGMENTS := BuildOption.CURVE_CENTERLINE_SEGMENTS
const SAFE_ZONE_FRACTION := 0.12
const TRAP_SLOT_FRACTIONS := [0.4, 0.6, 0.8]

var option: BuildOption
var piece_index := -1

func configure(build_option: BuildOption, configured_piece_index: int) -> void:
	option = build_option
	piece_index = configured_piece_index
	name = "TrackPiece_%d" % piece_index
	global_transform = option.transform
	get_node("InputConnector").transform = Transform3D.IDENTITY
	get_node("OutputConnector").transform = option.transform.affine_inverse() * option.output_transform
	_configure_progress_path()
	_configure_road_geometry()
	_configure_safe_respawn_zone()
	_configure_trap_slots()
	_configure_output_gate()

func get_trap_slots() -> Array:
	var slots: Array = []
	for slot in get_node("TrapSlots").get_children():
		slots.append(slot)
	return slots

func _configure_progress_path() -> void:
	var curve := Curve3D.new()
	for centerline_point in option.centerline_points:
		curve.add_point(centerline_point)
	get_node("ProgressPath").curve = curve

func _configure_road_geometry() -> void:
	var visuals: Node3D = get_node("RoadVisuals")
	var collision: StaticBody3D = get_node("RoadCollision")
	_clear_children(visuals)
	_clear_children(collision)
	if option.variant_id == "curve_left" or option.variant_id == "curve_right":
		var segment_angle := PI * 0.5 / CURVE_SEGMENTS
		var outer_radius := Constants.TRACK_CURVE_RADIUS_METERS + Constants.TRACK_HALF_WIDTH_METERS
		var segment_length := 2.0 * outer_radius * tan(segment_angle * 0.5) + 0.02
		for segment_index in range(CURVE_SEGMENTS):
			var midpoint_fraction := (float(segment_index) + 0.5) / CURVE_SEGMENTS
			_add_road_segment(visuals, collision, _path_transform(midpoint_fraction), segment_length, segment_index)
		return
	var output := _local_output_transform().origin
	var midpoint := output * 0.5
	var pitch := atan2(output.y, -output.z)
	var segment_transform := Transform3D(Basis(Vector3.RIGHT, pitch), midpoint)
	_add_road_segment(visuals, collision, segment_transform, output.length(), 0)

func _add_road_segment(
	visuals: Node3D,
	collision: StaticBody3D,
	segment_transform: Transform3D,
	segment_length: float,
	segment_index: int,
) -> void:
	var road_size := Vector3(Constants.TRACK_HALF_WIDTH_METERS * 2.0, ROAD_HEIGHT, segment_length)
	var surface_transform := segment_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, -ROAD_HEIGHT * 0.5, 0.0))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RoadSurface_%d" % segment_index
	var box_mesh := BoxMesh.new()
	box_mesh.size = road_size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.27, 0.31)
	material.roughness = 0.9
	box_mesh.material = material
	mesh_instance.mesh = box_mesh
	mesh_instance.transform = surface_transform
	visuals.add_child(mesh_instance)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "RoadShape_%d" % segment_index
	var box_shape := BoxShape3D.new()
	box_shape.size = road_size
	collision_shape.shape = box_shape
	collision_shape.transform = surface_transform
	collision.add_child(collision_shape)

func _configure_safe_respawn_zone() -> void:
	var safe_zone: Area3D = get_node("SafeRespawnZone")
	safe_zone.transform = _path_transform(SAFE_ZONE_FRACTION)
	safe_zone.set_meta("piece_index", piece_index)
	var safe_shape: BoxShape3D = safe_zone.get_node("CollisionShape3D").shape
	safe_shape.size = Vector3(Constants.TRACK_HALF_WIDTH_METERS * 2.0, 3.0, 3.0)

func _configure_trap_slots() -> void:
	var slots_root: Node3D = get_node("TrapSlots")
	_clear_children(slots_root)
	for slot_index in range(TRAP_SLOT_FRACTIONS.size()):
		var marker := Marker3D.new()
		var slot_id := "piece_%d_slot_%d" % [piece_index, slot_index]
		marker.name = slot_id
		marker.transform = _path_transform(TRAP_SLOT_FRACTIONS[slot_index])
		marker.position.y += 0.2
		marker.set_meta("slot_id", slot_id)
		marker.set_meta("piece_index", piece_index)
		marker.set_meta("slot_index", slot_index)
		marker.set_meta("occupied", false)
		slots_root.add_child(marker)

func _configure_output_gate() -> void:
	var gate: Area3D = get_node("OutputGate")
	gate.transform = get_node("OutputConnector").transform
	gate.set_meta("piece_index", piece_index)
	gate.set_meta("forward_only", true)
	gate.set_meta("forward_direction", gate.global_basis * Vector3.FORWARD)
	var gate_shape: BoxShape3D = gate.get_node("CollisionShape3D").shape
	gate_shape.size = Vector3(Constants.TRACK_HALF_WIDTH_METERS * 2.0, 3.0, 0.4)

func _path_position(fraction: float) -> Vector3:
	var clamped_fraction := clampf(fraction, 0.0, 1.0)
	match option.variant_id:
		"curve_left":
			var angle := clamped_fraction * PI * 0.5
			return Vector3(
				-Constants.TRACK_CURVE_RADIUS_METERS + Constants.TRACK_CURVE_RADIUS_METERS * cos(angle),
				0.0,
				-Constants.TRACK_CURVE_RADIUS_METERS * sin(angle),
			)
		"curve_right":
			var angle := clamped_fraction * PI * 0.5
			return Vector3(
				Constants.TRACK_CURVE_RADIUS_METERS - Constants.TRACK_CURVE_RADIUS_METERS * cos(angle),
				0.0,
				-Constants.TRACK_CURVE_RADIUS_METERS * sin(angle),
			)
		_:
			return _local_output_transform().origin * clamped_fraction

func _path_transform(fraction: float) -> Transform3D:
	var clamped_fraction := clampf(fraction, 0.0, 1.0)
	var basis := Basis.IDENTITY
	if option.variant_id == "curve_left":
		basis = Basis(Vector3.UP, clamped_fraction * PI * 0.5)
	elif option.variant_id == "curve_right":
		basis = Basis(Vector3.UP, -clamped_fraction * PI * 0.5)
	elif option.variant_id == "uphill":
		var output := _local_output_transform().origin
		basis = Basis(Vector3.RIGHT, atan2(output.y, -output.z))
	return Transform3D(basis, _path_position(clamped_fraction))

func _local_output_transform() -> Transform3D:
	return option.transform.affine_inverse() * option.output_transform

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()
