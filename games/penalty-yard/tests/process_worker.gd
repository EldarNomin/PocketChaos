extends SceneTree
## Uses the production scene and its ordinary /root/PenaltyYard/Session RPC path.
const Session = preload("res://scripts/session.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var is_host := args[0] == "host"
	var game: Node3D = load("res://main.tscn").instantiate()
	root.add_child(game)
	var network: Node = game.network
	if is_host:
		network.countdown_duration = 0.06
		network.prepare_duration = 0.06
		network.result_duration = 0.06
		network.build_duration = 0.06
	var error: int = network.start_host(int(args[1])) if is_host else network.join_room("127.0.0.1", int(args[1]))
	var voted := -1
	var deadline := Time.get_ticks_msec() + 25000
	var success := false
	while error == OK and network.online and Time.get_ticks_msec() < deadline:
		if network.connected and network.state == Session.State.READY and network.attempt_id != voted:
			voted = network.attempt_id
			network.ready_or_rematch()
		if network.state == Session.State.FINISHED:
			success = network.match_rules.attempts == 20 and network.match_rules.scores == [0,0] and network.match_rules.winner() == -1
			break
		await create_timer(0.01).timeout
	print("Process %s: %s" % [args[0], "PASS: full match and draw" if success else "FAIL: match incomplete"])
	# Give the other process time to receive the final reliable state.
	await create_timer(0.5).timeout
	if network.online:
		network.close_session("Test completed")
	game.queue_free()
	await process_frame
	quit(0 if success else 1)
