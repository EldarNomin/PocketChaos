extends RefCounted
## Pure rules: usable by both training and the future authoritative host.
const Tuning = preload("res://scripts/tuning.gd")

const RADIUS := 0.22
const HALF_GOAL := 3.0
const GOAL_HEIGHT := 2.5
const CATCH_PLANE := 0.60
const SHOT_ORIGIN := Vector3(0, RADIUS + 0.01, 10)

static func plane_crossing(from: Vector3, to: Vector3, z: float) -> float:
	if from.z > z and to.z <= z:
		return (from.z - z) / (from.z - to.z)
	return -1.0

static func goal_crossing(from: Vector3, to: Vector3) -> bool:
	var t := plane_crossing(from, to, -RADIUS)
	if t < 0.0:
		return false
	var point := from.lerp(to, t)
	return absf(point.x) <= HALF_GOAL - RADIUS and point.y >= RADIUS and point.y <= GOAL_HEIGHT - RADIUS

static func segment_distance(from: Vector3, to: Vector3, point: Vector3) -> float:
	var segment := to - from
	var length_sq := segment.length_squared()
	if length_sq < 0.000001:
		return from.distance_to(point)
	var t := clampf((point - from).dot(segment) / length_sq, 0.0, 1.0)
	return from.lerp(to, t).distance_to(point)

static func launch_velocity(target: Vector3, power: float) -> Vector3:
	# Target is where a gravity-only shot would reach the goal plane.
	# Curve and physical collisions can move the final result away from it.
	var speed := lerpf(Tuning.MIN_SHOT_SPEED, Tuning.MAX_SHOT_SPEED, clampf(power, 0.0, 1.0))
	var flight_time := SHOT_ORIGIN.z / speed
	var result := (target - SHOT_ORIGIN) / flight_time
	result.y += 0.5 * Tuning.GRAVITY * flight_time
	return result

static func attempt_result(from: Vector3, to: Vector3, hands: Vector3, catching: bool) -> String:
	# Catch plane precedes the goal plane. Ignore hands behind the line.
	var t := plane_crossing(from, to, CATCH_PLANE)
	if catching and t >= 0.0:
		var point := from.lerp(to, t)
		if point.distance_to(hands) <= RADIUS + Tuning.HAND_RADIUS:
			return "save"
	if goal_crossing(from, to):
		return "goal"
	return ""
