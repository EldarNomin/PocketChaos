extends SceneTree
const Fixture = preload("res://tests/network_fixture.gd")
const Session = preload("res://scripts/session.gd")
var checks := 0
var failures := 0
var host_game: Node3D
var client_game: Node3D
var host_root: Node
var client_root: Node
var h: Node
var c: Node
var latency := false

func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(text)

func wait_for(predicate: Callable, seconds := 4.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if predicate.call():
			return true
		await create_timer(0.01).timeout
	check(false, "Timed out waiting for network condition")
	return false

func _init() -> void:
	latency = OS.get_cmdline_user_args().has("--latency")
	call_deferred("run")

func run() -> void:
	host_root = Node.new()
	host_root.name = "Host"
	root.add_child(host_root)
	client_root = Node.new()
	client_root.name = "Client"
	root.add_child(client_root)
	set_multiplayer(MultiplayerAPI.create_default_interface(), host_root.get_path())
	set_multiplayer(MultiplayerAPI.create_default_interface(), client_root.get_path())
	host_game = Node3D.new()
	host_game.set_script(Fixture)
	host_game.name = "PenaltyYard"
	host_root.add_child(host_game)
	client_game = Node3D.new()
	client_game.set_script(Fixture)
	client_game.name = "PenaltyYard"
	client_game.delay_network = latency
	client_root.add_child(client_game)
	h = host_game.network
	c = client_game.network
	h.countdown_duration = 0.06
	h.result_duration = 0.5 if latency else 0.25
	h.prepare_duration = 4.0
	h.build_duration = 0.06
	var port := 25000 + randi_range(0, 5000)
	check(h.start_host(port) == OK, "Host opens UDP room")
	check(c.join_room("127.0.0.1", port) == OK, "Client starts real ENet connection")
	if not await wait_for(func(): return h.connected and c.connected):
		await clean_up()
		return
	check(h.guest_id == c.multiplayer.get_unique_id(), "Handshake binds actual peer ID")
	check(h.active_shooter_slot == c.active_shooter_slot, "Both peers agree on first shooter")
	var first: int = h.active_shooter_slot
	var shooter: Node = h if first == 0 else c
	var keeper: Node = c if first == 0 else h
	shooter.send_command("release", {"target": Vector3(2,1.8,0), "spin": 0})
	await create_timer(0.16).timeout
	check(h.accepted_shots == 0, "Cannot shoot before readiness and charge")
	h.ready_or_rematch()
	c.ready_or_rematch()
	if not await wait_for(func(): return h.state == Session.State.AIM and c.state == Session.State.AIM):
		await clean_up()
		return
	check(h.ready_votes == [true,true], "Both players must agree to start")
	shooter.send_command("begin", {})
	await create_timer(0.32).timeout
	shooter.send_command("release", {"target": Vector3(2,1.8,0), "spin": 0, "power": 999})
	if not await wait_for(func(): return h.accepted_shots == 1 and c.state == Session.State.FLIGHT):
		await clean_up()
		return
	shooter.send_command("release", {"target": Vector3(2,1.8,0), "spin": 0})
	keeper.send_command("release", {"target": Vector3(0,1.8,0), "spin": 0})
	check(absf(host_game.ball.velocity.z) <= 18.0, "Host computes power; claimed power is ignored")
	if not await wait_for(func(): return h.state == Session.State.RESULT and c.state == Session.State.RESULT):
		await clean_up()
		return
	check(h.accepted_shots == 1, "Duplicate and wrong-role shots are rejected")
	check(h.last_outcome == "goal", "Actual ball physics produces a goal")
	check(h.match_rules.scores[first] == 1, "Correct player receives goal")
	check(h.match_rules.scores == c.match_rules.scores, "Score matches after network result")
	check(host_game.ball.position.distance_to(client_game.ball.position) < 0.01, "Terminal ball position matches")
	var previous_attempt: int = h.attempt_id
	if not await wait_for(func(): return h.state == Session.State.READY and c.state == Session.State.READY and c.attempt_id > previous_attempt):
		await clean_up()
		return
	check(h.active_shooter_slot != first and host_game.mode != client_game.mode, "Roles switch for second shot")
	c._command.rpc_id(1, previous_attempt, "begin", {})
	h.ready_or_rematch()
	c.ready_or_rematch()
	if not await wait_for(func(): return h.state == Session.State.AIM and c.state == Session.State.AIM):
		await clean_up()
		return
	check(h.charge_start < 0, "Stale command cannot charge a new attempt")
	shooter = h if h.local_shooter() else c
	keeper = c if h.local_shooter() else h
	var keeper_game: Node3D = client_game if h.local_shooter() else host_game
	keeper_game.test_hands = Vector3(0, 1.8, 0.6)
	shooter.send_command("begin", {})
	await create_timer(0.32).timeout
	shooter.send_command("release", {"target": Vector3(0,1.8,0), "spin": 0})
	if not await wait_for(func(): return h.state == Session.State.FLIGHT and host_game.ball.position.z < 3.0):
		await clean_up()
		return
	keeper.send_command("catch", {})
	if not await wait_for(func(): return h.state == Session.State.RESULT and c.state == Session.State.RESULT):
		await clean_up()
		return
	check(h.last_outcome == "save", "Keeper command catches actual network shot")
	check(h.match_rules.scores == c.match_rules.scores and h.match_rules.scores[first] == 1 and h.match_rules.scores[1-first] == 0, "Save adds no goal and agrees on both peers")
	# Finish the remaining real match using preparation time-outs.
	h.prepare_duration = 0.06
	h.result_duration = 0.06
	var host_voted := -1
	var client_voted := -1
	var deadline := Time.get_ticks_msec() + 16000
	while h.state != Session.State.FINISHED and Time.get_ticks_msec() < deadline:
		if h.state == Session.State.READY and h.attempt_id != host_voted:
			host_voted = h.attempt_id
			h.ready_or_rematch()
		if c.state == Session.State.READY and c.attempt_id != client_voted:
			client_voted = c.attempt_id
			c.ready_or_rematch()
		await create_timer(0.01).timeout
	check(h.state == Session.State.FINISHED and h.match_rules.attempts == 10, "Full five-round match completes")
	await wait_for(func(): return c.state == Session.State.FINISHED)
	check(h.match_rules.scores == c.match_rules.scores and h.match_rules.winner() == c.match_rules.winner(), "Both peers agree on winner")
	var old_first: int = h.match_rules.initial_first
	h.ready_or_rematch()
	await create_timer(0.18).timeout
	check(h.state == Session.State.FINISHED, "One rematch vote cannot restart match")
	c.ready_or_rematch()
	await wait_for(func(): return h.state == Session.State.READY and c.state == Session.State.READY)
	check(h.match_rules.scores == [0,0] and c.match_rules.scores == [0,0], "Rematch clears both scores")
	check(h.match_rules.initial_first == 1-old_first, "Rematch alternates starting player")
	c.close_session("Test leave")
	await wait_for(func(): return not h.online, 7.0)
	check(not h.online and not c.online, "Disconnect interrupts match on both peers")
	await clean_up()

func clean_up() -> void:
	if h.online:
		h.close_session("Test cleanup")
	if c.online:
		c.close_session("Test cleanup")
	await create_timer(0.2).timeout
	host_root.queue_free()
	client_root.queue_free()
	await process_frame
	print("Network%s: %d checks, %d failures" % [" (+120 ms each way)" if latency else "", checks, failures])
	quit(1 if failures else 0)
