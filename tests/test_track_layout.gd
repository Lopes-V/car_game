extends RefCounted

var BuildOption
var TrackLayout

func run() -> bool:
	BuildOption = load("res://scripts/domain/build_choice.gd")
	TrackLayout = load("res://scripts/domain/track_layout.gd")
	if BuildOption == null or TrackLayout == null:
		push_error("TrackLayout and BuildOption must be defined.")
		return false
	var all_passed := true
	all_passed = test_build_option_constructor_fully_initializes_geometry() and all_passed
	all_passed = test_curve_footprints_include_output_tangent_clearance() and all_passed
	all_passed = test_initial_straight_uses_the_track_coordinate_convention() and all_passed
	all_passed = test_initial_connector_offers_every_discrete_variant() and all_passed
	all_passed = test_curve_options_have_expected_end_connectors_and_lengths() and all_passed
	all_passed = test_option_that_intersects_existing_piece_is_not_offered() and all_passed
	all_passed = test_blocked_end_returns_no_build_options() and all_passed
	all_passed = test_xz_overlap_is_rejected_despite_extreme_height_separation() and all_passed
	all_passed = test_checkpoint_waits_for_first_allowed_new_piece_after_threshold() and all_passed
	all_passed = test_global_progress_uses_clamped_distance_units_only() and all_passed
	return all_passed

func test_build_option_constructor_fully_initializes_geometry() -> bool:
	var option = BuildOption.new("uphill", true)
	return (
		_expect(option.variant_id == "uphill", "A build option must preserve its variant identifier.")
		and _expect(option.allows_checkpoint, "A build option must preserve checkpoint eligibility.")
		and _expect(option.transform == Transform3D.IDENTITY, "A default build option must start at the identity transform.")
		and _expect(option.output_transform.origin.is_equal_approx(Vector3(0.0, 5.0, -20.0)), "A build option must initialize its output transform.")
		and _expect(is_equal_approx(option.length_meters, 20.0), "A build option must initialize its path length.")
		and _expect(option.footprint.has_volume(), "A build option must initialize a collision footprint.")
	)

func test_curve_footprints_include_output_tangent_clearance() -> bool:
	var left = BuildOption.new("curve_left", false)
	var right = BuildOption.new("curve_right", false)
	return (
		_expect(is_equal_approx(left.footprint.position.x, -20.0), "A left curve footprint must stop at its output connector plane.")
		and _expect(is_equal_approx(left.footprint.position.z, -24.0), "A left curve footprint must include four meters of output-tangent clearance.")
		and _expect(is_equal_approx(left.footprint.end.x, 4.0), "A left curve footprint must include four meters of input-tangent clearance.")
		and _expect(is_zero_approx(left.footprint.end.z), "A left curve footprint must keep its input seam unpadded.")
		and _expect(is_equal_approx(right.footprint.position.x, -4.0), "A right curve footprint must include four meters of input-tangent clearance.")
		and _expect(is_equal_approx(right.footprint.position.z, -24.0), "A right curve footprint must include four meters of output-tangent clearance.")
		and _expect(is_equal_approx(right.footprint.end.x, 20.0), "A right curve footprint must stop at its output connector plane.")
		and _expect(is_zero_approx(right.footprint.end.z), "A right curve footprint must keep its input seam unpadded.")
	)

func test_initial_straight_uses_the_track_coordinate_convention() -> bool:
	var layout = TrackLayout.with_initial_straight()
	if not _expect(layout.pieces.size() == 1, "The layout must start with exactly one straight piece."):
		return false
	var initial_piece = layout.pieces[0]
	return (
		_expect(initial_piece.variant_id == "straight", "The initial piece must be straight.")
		and _expect(initial_piece.transform == Transform3D.IDENTITY, "The initial straight must start at the origin.")
		and _expect(initial_piece.output_transform.origin.is_equal_approx(Vector3(0.0, 0.0, -20.0)), "The initial straight must end 20 meters along local -Z.")
		and _expect(is_equal_approx(initial_piece.length_meters, 20.0), "The initial straight must be 20 meters long.")
	)

func test_initial_connector_offers_every_discrete_variant() -> bool:
	var layout = TrackLayout.with_initial_straight()
	var ids := _option_ids(layout.get_valid_options())
	return _expect(
		ids == ["straight", "curve_left", "curve_right", "uphill"],
		"A clear connector must offer the four discrete variants in catalogue order.",
	)

func test_curve_options_have_expected_end_connectors_and_lengths() -> bool:
	var layout = TrackLayout.with_initial_straight()
	var options = layout.get_valid_options()
	var left = _find_option(options, "curve_left")
	var right = _find_option(options, "curve_right")
	var uphill = _find_option(options, "uphill")
	if not _expect(left != null and right != null and uphill != null, "Curve and uphill options must be offered on a clear connector."):
		return false
	return (
		_expect(left.transform.origin.is_equal_approx(Vector3(0.0, 0.0, -20.0)), "An option input must snap to the current end connector.")
		and _expect(left.output_transform.origin.is_equal_approx(Vector3(-20.0, 0.0, -40.0)), "A left curve must end 20 meters left and forward.")
		and _expect((left.output_transform.basis * Vector3.FORWARD).is_equal_approx(Vector3.LEFT), "A left curve output must face local left.")
		and _expect(right.output_transform.origin.is_equal_approx(Vector3(20.0, 0.0, -40.0)), "A right curve must end 20 meters right and forward.")
		and _expect((right.output_transform.basis * Vector3.FORWARD).is_equal_approx(Vector3.RIGHT), "A right curve output must face local right.")
		and _expect(is_equal_approx(left.length_meters, PI * 10.0), "A quarter curve with radius 20 must have PI * 10 meters of path.")
		and _expect(uphill.output_transform.origin.is_equal_approx(Vector3(0.0, 5.0, -40.0)), "An uphill must rise 5 meters over its 20-meter run.")
		and _expect(is_equal_approx(uphill.length_meters, 20.0), "An uphill path must use the specified 20-meter logical length.")
	)

func test_option_that_intersects_existing_piece_is_not_offered() -> bool:
	var layout = TrackLayout.with_initial_straight()
	if not _append_offered(layout, "curve_left"):
		return false
	if not _append_offered(layout, "curve_left"):
		return false
	if not _append_offered(layout, "curve_left"):
		return false
	return _expect(
		not _option_ids(layout.get_valid_options()).has("curve_left"),
		"A fourth left curve that returns into occupied geometry must not be offered.",
	)

func test_blocked_end_returns_no_build_options() -> bool:
	var layout = TrackLayout.with_initial_straight()
	for variant_id in ["curve_left", "curve_left", "curve_left"]:
		if not _append_offered(layout, variant_id):
			return false
	return _expect(
		layout.get_valid_options().is_empty(),
		"A boxed-in end must return an empty list after the straight fallback also collides.",
	)

func test_xz_overlap_is_rejected_despite_extreme_height_separation() -> bool:
	var layout = TrackLayout.with_initial_straight()
	for _piece_index in range(401):
		if not _append_offered(layout, "uphill"):
			return false
	if not _append_offered(layout, "curve_left"):
		return false
	if not _append_offered(layout, "curve_left"):
		return false
	for _piece_index in range(401):
		if not _append_offered(layout, "straight"):
			return false
	if not _append_offered(layout, "curve_left"):
		return false
	return _expect(
		layout.get_valid_options().is_empty(),
		"XZ overlap must be rejected even when candidate and occupied geometry differ by 2005 vertical meters.",
	)

func test_checkpoint_waits_for_first_allowed_new_piece_after_threshold() -> bool:
	var layout = TrackLayout.with_initial_straight()
	if not _append_offered(layout, "curve_left"):
		return false
	if not _expect(layout.next_checkpoint_index() == -1, "A disallowed second piece must defer checkpoint placement."):
		return false
	if not _append_offered(layout, "uphill"):
		return false
	if not _expect(layout.next_checkpoint_index() == 2, "The next allowed piece must receive the deferred checkpoint."):
		return false
	if not _append_offered(layout, "straight"):
		return false
	return _expect(layout.next_checkpoint_index() == -1, "A later append below the threshold must not repeat the prior checkpoint.")

func test_global_progress_uses_clamped_distance_units_only() -> bool:
	var layout = TrackLayout.with_initial_straight()
	if not _append_offered(layout, "straight"):
		return false
	return (
		_expect(is_equal_approx(layout.global_progress(1, 4.0), 24.0), "Progress must add local meters to accumulated path meters.")
		and _expect(is_equal_approx(layout.global_progress(1, -3.0), 20.0), "Progress must clamp negative local distance to the piece start.")
		and _expect(is_equal_approx(layout.global_progress(1, 25.0), 40.0), "Progress must clamp excess local distance to the piece length.")
	)

func _append_offered(layout, variant_id: String) -> bool:
	var option = _find_option(layout.get_valid_options(), variant_id)
	if not _expect(option != null, "Expected offered option: %s" % variant_id):
		return false
	layout.append(option)
	return true

func _find_option(options: Array, variant_id: String):
	for option in options:
		if option.variant_id == variant_id:
			return option
	return null

func _option_ids(options: Array) -> Array[String]:
	var ids: Array[String] = []
	for option in options:
		ids.append(option.variant_id)
	return ids

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
