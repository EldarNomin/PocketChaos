extends SceneTree
const FieldRules = preload("res://scripts/field_rules.gd")
const Game = preload("res://scripts/game.gd")
var failures := 0
var checks := 0
var game: Node3D

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func item(owner: int, kind: String, cell: int, angle := 2) -> Dictionary:
	return {"owner":owner,"kind":kind,"cell":cell,"rotation":angle}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var layout := FieldRules.empty_layout()
	check(FieldRules.has_clear_corridor(layout),"Empty field has clear corridors")
	check(FieldRules.placement_error(layout,0,0,"shield",7,2) == "","Central shield away from striker permits side shots")
	check(FieldRules.placement_error(layout,0,0,"shield",12,2) != "","Shield cannot close every shooting corridor")
	for bad in [[-1,0,"shield",0,2],[0,2,"shield",0,2],[0,0,"spring",0,2],[0,0,"shield",15,2],[0,0,"shield",0,5]]:
		check(FieldRules.placement_error(layout,bad[0],bad[1],bad[2],bad[3],bad[4]) != "","Reject invalid placement %s" % str(bad))
	layout[0] = item(0,"shield",1)
	check(FieldRules.placement_error(layout,1,0,"fan_right",1,2) != "","Reject overlapping opponent item")
	check(FieldRules.placement_error(layout,0,0,"fan_left",1,2) == "","Owner may replace own item in same place")
	check(FieldRules.placement_error(layout,0,1,"shield",0,2) != "","Reject too-close adjacent items")
	layout = [item(0,"fan_right",7),{},{},{}]
	check(FieldRules.wind_acceleration(layout,Vector3(0,1,5)) == Vector3(9,0,0),"Right fan accelerates in visible volume")
	check(FieldRules.wind_acceleration(layout,Vector3(0,3,5)) == Vector3.ZERO,"No wind above volume")
	check(FieldRules.wind_acceleration(layout,Vector3(0,1,7)) == Vector3.ZERO,"No wind beyond volume")
	layout[2] = item(1,"fan_left",7)
	check(FieldRules.wind_acceleration(layout,Vector3(0,1,5)) == Vector3.ZERO,"Opposite winds combine deterministically")
	game = Node3D.new()
	game.set_script(Game)
	root.add_child(game)
	game.set_physics_process(false)
	game.field.apply_layout([item(0,"shield",7),{},{},{}],100)
	await physics_frame
	await physics_frame
	game.fire(Vector3(0,1,0),1,0)
	var bounced := false
	for step in range(100):
		game.ball.step(1.0/120.0)
		if game.ball.velocity.z > 0:
			bounced = true
			break
	check(bounced,"Actual swept ball rebounds off shield collider")
	for angle in [0,4]:
		game.field.apply_layout([item(0,"shield",7,angle),{},{},{}],200+angle)
		await physics_frame
		await physics_frame
		game.reset_attempt()
		game.fire(Vector3(0,1,0),1,0)
		for step in range(100):
			game.ball.step(1.0/120.0)
			if absf(game.ball.velocity.x) > 5: break
		check(game.ball.velocity.x < -5 if angle == 0 else game.ball.velocity.x > 5,"Shield orientation controls sideways rebound")
	game.field.apply_layout([item(0,"fan_right",7),{},{},{}],101)
	await physics_frame
	var path_a := shoot_with_wind()
	var path_b := shoot_with_wind()
	check(path_a[-1].x > 0.2,"Real flight bends right through fan volume")
	check(path_a == path_b,"Reset and replay produce identical wind trajectories")
	check(game.field.layout[0].kind == "fan_right","Attempt reset preserves installed field")
	var previous_revision: int = game.field.revision
	game.field.clear()
	check(game.field.layout == FieldRules.empty_layout() and game.field.revision > previous_revision,"Clear removes items and advances revision")
	print("Field: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

func shoot_with_wind() -> Array[Vector3]:
	game.reset_attempt()
	game.fire(Vector3(0,1,0),0.5,0)
	var path: Array[Vector3] = []
	for step in range(95):
		game.ball.step(1.0/120.0,game.field.wind_acceleration(game.ball.position))
		path.append(game.ball.position)
	return path
