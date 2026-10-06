extends SceneTree

const Game = preload("res://scripts/game.gd")
const Rules = preload("res://scripts/rules.gd")
var failures := 0
var checks := 0
var game: Node3D

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	game = Node3D.new()
	game.set_script(Game)
	root.add_child(game)
	game.set_physics_process(false)
	await physics_frame
	await physics_frame
	game.set_paused(false)
	game.fire(Vector3(0, 1.2, 0), 0.5, 0.0)
	for i in range(300):
		game._physics_process(1.0 / 120.0)
		if game.phase == Game.Phase.RESULT:
			break
	check(game.goals == 1 and game.shots_completed == 1, "Centre shot scores once in actual 3D scene")
	game.finish_attempt("goal")
	check(game.goals == 1, "Result cannot count twice")
	game.reset_attempt()
	check(not game.ball.live and game.ball.velocity == Vector3.ZERO, "Reset clears ball motion")
	check(game.spin == 0 and not game.dash_used and game.catch_cooldown == 0, "Reset clears modifiers")
	game.fire(Vector3(4, 1.2, 0), 0.5, 0)
	for i in range(800):
		game._physics_process(1.0 / 120.0)
		if game.phase == Game.Phase.RESULT:
			break
	check(game.goals == 1 and game.shots_completed == 2, "Wide shot is a miss")
	game.reset_attempt()
	game.fire(Vector3(0, 1.2, 0), 0.5, 0)
	game.set_paused(true)
	var before: Vector3 = game.ball.position
	game._physics_process(0.5)
	check(game.ball.position == before, "Pause stops physics")
	game.set_paused(false)
	game.set_mode(Game.Mode.KEEPER)
	check(game.phase == Game.Phase.READY and not game.ball.live, "Changing role clears old flight")
	game.fire(Vector3(0, 1.2, 0), 0.35, 0)
	for i in range(300):
		game._physics_process(1.0 / 120.0)
		if game.phase == Game.Phase.RESULT:
			break
	check(game.keeper_completed == 1, "Keeper flight ends")
	check(game.ball.position.y >= Rules.RADIUS - 0.02, "Ball remains above floor")
	game.reset_attempt()
	game.fire(Vector3(0, 1.2, 0), 0.5, -1)
	for i in range(30):
		game._physics_process(1.0 / 120.0)
	check(game.ball.position.x < 0, "Left curve bends left in world coordinates")
	print("Scene: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

