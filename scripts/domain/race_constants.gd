class_name RaceConstants
extends RefCounted

const MAX_ROUNDS := 5
const TARGET_SCORE := 20
const ROUND_TIME_SECONDS := 120.0
const FINAL_WINDOW_SECONDS := 15.0

const TRACK_PIECE_LENGTH_METERS := 20.0
const TRACK_CURVE_RADIUS_METERS := 20.0
const TRACK_UPHILL_RISE_METERS := 5.0
const TRACK_HALF_WIDTH_METERS := 3.0
const TRACK_SAFETY_MARGIN_METERS := 1.0

const TRACK_VARIANTS := [
	{"variant_id": "straight", "allows_checkpoint": true},
	{"variant_id": "curve_left", "allows_checkpoint": false},
	{"variant_id": "curve_right", "allows_checkpoint": false},
	{"variant_id": "uphill", "allows_checkpoint": true},
]
