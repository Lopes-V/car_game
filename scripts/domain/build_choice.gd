class_name BuildOption
extends RefCounted

const Constants = preload("res://scripts/domain/race_constants.gd")

const LEFT_TURN_BASIS := Basis(
	Vector3(0.0, 0.0, -1.0),
	Vector3.UP,
	Vector3(1.0, 0.0, 0.0),
)
const RIGHT_TURN_BASIS := Basis(
	Vector3(0.0, 0.0, 1.0),
	Vector3.UP,
	Vector3(-1.0, 0.0, 0.0),
)
const CURVE_CENTERLINE_SEGMENTS := 12

var variant_id: String
var allows_checkpoint: bool
var transform: Transform3D
var output_transform: Transform3D
var length_meters: float
var footprint: AABB
var centerline_points: PackedVector3Array

func _init(
	requested_variant_id: String,
	checkpoint_allowed: bool,
	input_transform: Transform3D = Transform3D.IDENTITY,
) -> void:
	assert(_is_supported_variant(requested_variant_id), "Unsupported track variant: %s" % requested_variant_id)
	variant_id = requested_variant_id
	allows_checkpoint = checkpoint_allowed
	transform = input_transform
	output_transform = input_transform * _local_output_transform(requested_variant_id)
	centerline_points = _local_centerline_points(requested_variant_id)
	length_meters = _centerline_length(centerline_points)
	footprint = _transform_aabb(_local_footprint(requested_variant_id), input_transform)

static func _is_supported_variant(candidate_id: String) -> bool:
	for variant in Constants.TRACK_VARIANTS:
		if variant["variant_id"] == candidate_id:
			return true
	return false

static func _local_centerline_points(candidate_id: String) -> PackedVector3Array:
	var points := PackedVector3Array()
	if candidate_id == "curve_left" or candidate_id == "curve_right":
		for segment_index in range(CURVE_CENTERLINE_SEGMENTS + 1):
			var angle := float(segment_index) / CURVE_CENTERLINE_SEGMENTS * PI * 0.5
			var horizontal := Constants.TRACK_CURVE_RADIUS_METERS * (1.0 - cos(angle))
			points.append(Vector3(
				-horizontal if candidate_id == "curve_left" else horizontal,
				0.0,
				-Constants.TRACK_CURVE_RADIUS_METERS * sin(angle),
			))
		return points
	points.append(Vector3.ZERO)
	points.append(_local_output_transform(candidate_id).origin)
	return points

static func _centerline_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for point_index in range(1, points.size()):
		total += points[point_index - 1].distance_to(points[point_index])
	return total

static func _local_output_transform(candidate_id: String) -> Transform3D:
	match candidate_id:
		"curve_left":
			return Transform3D(
				LEFT_TURN_BASIS,
				Vector3(-Constants.TRACK_CURVE_RADIUS_METERS, 0.0, -Constants.TRACK_CURVE_RADIUS_METERS),
			)
		"curve_right":
			return Transform3D(
				RIGHT_TURN_BASIS,
				Vector3(Constants.TRACK_CURVE_RADIUS_METERS, 0.0, -Constants.TRACK_CURVE_RADIUS_METERS),
			)
		"uphill":
			return Transform3D(Basis.IDENTITY, Vector3(0.0, Constants.TRACK_UPHILL_RISE_METERS, -Constants.TRACK_PIECE_LENGTH_METERS))
		_:
			return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -Constants.TRACK_PIECE_LENGTH_METERS))

static func _local_footprint(candidate_id: String) -> AABB:
	var clearance := Constants.TRACK_HALF_WIDTH_METERS + Constants.TRACK_SAFETY_MARGIN_METERS
	var vertical_size := Constants.TRACK_SAFETY_MARGIN_METERS * 2.0
	if candidate_id == "uphill":
		vertical_size += Constants.TRACK_UPHILL_RISE_METERS
	var forward_length := Constants.TRACK_PIECE_LENGTH_METERS
	match candidate_id:
		"curve_left":
			return AABB(
				Vector3(-Constants.TRACK_CURVE_RADIUS_METERS, -Constants.TRACK_SAFETY_MARGIN_METERS, -Constants.TRACK_CURVE_RADIUS_METERS - clearance),
				Vector3(Constants.TRACK_CURVE_RADIUS_METERS + clearance, vertical_size, Constants.TRACK_CURVE_RADIUS_METERS + clearance),
			)
		"curve_right":
			return AABB(
				Vector3(-clearance, -Constants.TRACK_SAFETY_MARGIN_METERS, -Constants.TRACK_CURVE_RADIUS_METERS - clearance),
				Vector3(Constants.TRACK_CURVE_RADIUS_METERS + clearance, vertical_size, Constants.TRACK_CURVE_RADIUS_METERS + clearance),
			)
		_:
			return AABB(
				Vector3(-clearance, -Constants.TRACK_SAFETY_MARGIN_METERS, -forward_length),
				Vector3(clearance * 2.0, vertical_size, forward_length),
			)

static func _transform_aabb(local_box: AABB, world_transform: Transform3D) -> AABB:
	var first_corner := world_transform * local_box.position
	var minimum := first_corner
	var maximum := first_corner
	for x_offset in [0.0, local_box.size.x]:
		for y_offset in [0.0, local_box.size.y]:
			for z_offset in [0.0, local_box.size.z]:
				var corner := world_transform * (local_box.position + Vector3(x_offset, y_offset, z_offset))
				minimum = minimum.min(corner)
				maximum = maximum.max(corner)
	return AABB(minimum, maximum - minimum)
