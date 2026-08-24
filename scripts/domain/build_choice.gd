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

var variant_id: String
var allows_checkpoint: bool
var transform: Transform3D
var output_transform: Transform3D
var length_meters: float
var footprint: AABB

func _init(
	requested_variant_id: String,
	checkpoint_allowed: bool,
	input_transform: Transform3D = Transform3D.IDENTITY,
) -> void:
	assert(_is_supported_variant(requested_variant_id), "Unsupported track variant: %s" % requested_variant_id)
	variant_id = requested_variant_id
	allows_checkpoint = checkpoint_allowed
	transform = input_transform
	length_meters = _variant_length(requested_variant_id)
	output_transform = input_transform * _local_output_transform(requested_variant_id)
	footprint = _transform_aabb(_local_footprint(requested_variant_id), input_transform)

static func _is_supported_variant(candidate_id: String) -> bool:
	for variant in Constants.TRACK_VARIANTS:
		if variant["variant_id"] == candidate_id:
			return true
	return false

static func _variant_length(candidate_id: String) -> float:
	if candidate_id == "curve_left" or candidate_id == "curve_right":
		return PI * Constants.TRACK_CURVE_RADIUS_METERS * 0.5
	return Constants.TRACK_PIECE_LENGTH_METERS

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
	var vertical_extent := Constants.TRACK_COLLISION_VERTICAL_EXTENT_METERS
	var forward_length := Constants.TRACK_PIECE_LENGTH_METERS
	match candidate_id:
		"curve_left":
			return AABB(
				Vector3(-Constants.TRACK_CURVE_RADIUS_METERS, -vertical_extent, -Constants.TRACK_CURVE_RADIUS_METERS),
				Vector3(Constants.TRACK_CURVE_RADIUS_METERS + clearance, vertical_extent * 2.0, Constants.TRACK_CURVE_RADIUS_METERS),
			)
		"curve_right":
			return AABB(
				Vector3(-clearance, -vertical_extent, -Constants.TRACK_CURVE_RADIUS_METERS),
				Vector3(Constants.TRACK_CURVE_RADIUS_METERS + clearance, vertical_extent * 2.0, Constants.TRACK_CURVE_RADIUS_METERS),
			)
		_:
			return AABB(
				Vector3(-clearance, -vertical_extent, -forward_length),
				Vector3(clearance * 2.0, vertical_extent * 2.0, forward_length),
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
