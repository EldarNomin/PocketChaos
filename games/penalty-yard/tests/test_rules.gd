extends SceneTree

const Rules = preload("res://scripts/rules.gd")
var failures := 0
var checks := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _init() -> void:
	check(Rules.goal_crossing(Vector3(0, 1, 0.1), Vector3(0, 1, -0.4)), "A whole ball crossing the goal mouth is a goal")
	check(not Rules.goal_crossing(Vector3(0, 1, 0.1), Vector3(0, 1, -0.1)), "Partial crossing is not a goal")
	check(not Rules.goal_crossing(Vector3(3, 1, 0.1), Vector3(3, 1, -0.4)), "Outside post is not a goal")
	check(not Rules.goal_crossing(Vector3(0, 2.5, 0.1), Vector3(0, 2.5, -0.4)), "Above bar is not a goal")
	check(not Rules.goal_crossing(Vector3(0, 1, -0.4), Vector3(0, 1, 0.4)), "Returning through goal mouth does not score")
	var hands := Vector3(0, 1, Rules.CATCH_PLANE)
	check(Rules.attempt_result(Vector3(0, 1, 1), Vector3(0, 1, -1), hands, true) == "save", "Catch before goal wins even over one long step")
	check(Rules.attempt_result(Vector3(0, 1, 1), Vector3(0, 1, -1), hands, false) == "goal", "Hands require active catch")
	check(Rules.attempt_result(Vector3(2, 1, 1), Vector3(2, 1, -1), hands, true) == "goal", "Hands cannot reach a distant shot")
	check(Rules.segment_distance(Vector3.ZERO, Vector3.ZERO, Vector3.ONE) > 1.0, "Zero-length swept segment is safe")
	var low := Rules.launch_velocity(Vector3(1.5, 1.7, 0), 0)
	var high := Rules.launch_velocity(Vector3(1.5, 1.7, 0), 1)
	check(absf(high.z) > absf(low.z), "Power changes speed")
	for power in [0.0, 0.5, 1.0]:
		var target := Vector3(1.5, 1.7, 0)
		var velocity := Rules.launch_velocity(target, power)
		var time := -Rules.SHOT_ORIGIN.z / velocity.z
		var landing := Rules.SHOT_ORIGIN + velocity * time + Vector3(0, -4.9 * time * time, 0)
		check(landing.distance_to(target) < 0.001, "Uncurved shot targets the same point at every power")
	print("Rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

