class_name PlayerRoundState
extends RefCounted

const STARTING_LIVES := 3
const STARTING_BOOST_CHARGES := 1

var lives := STARTING_LIVES
var boost_charges := STARTING_BOOST_CHARGES
var deaths := 0
var is_dead := false
var is_eliminated := false
var last_safe_respawn := Transform3D.IDENTITY

func reset_for_round(initial_safe_respawn: Transform3D = Transform3D.IDENTITY) -> void:
	lives = STARTING_LIVES
	boost_charges = STARTING_BOOST_CHARGES
	deaths = 0
	is_dead = false
	is_eliminated = false
	last_safe_respawn = initial_safe_respawn

func try_consume_boost() -> bool:
	if boost_charges <= 0:
		return false
	boost_charges -= 1
	return true

func lose_life() -> bool:
	if is_dead:
		return lives > 0
	lives = maxi(lives - 1, 0)
	deaths += 1
	is_dead = true
	is_eliminated = lives == 0
	return not is_eliminated

func respawn(safe_transform: Transform3D) -> bool:
	if lives <= 0 or is_eliminated:
		return false
	last_safe_respawn = safe_transform
	is_dead = false
	return true
