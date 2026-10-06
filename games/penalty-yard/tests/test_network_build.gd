extends SceneTree
const Fixture = preload("res://tests/network_fixture.gd")
const Session = preload("res://scripts/session.gd")
const FieldRules = preload("res://scripts/field_rules.gd")
var h: Node
var c: Node
var host_game: Node3D
var client_game: Node3D
var host_root: Node
var client_root: Node
var checks := 0
var failures := 0
var last_h_vote := -1
var last_c_vote := -1
var latency := false

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func wait_for(predicate: Callable, seconds := 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		if h.connected and h.state == Session.State.READY and h.attempt_id != last_h_vote:
			last_h_vote = h.attempt_id
			h.ready_or_rematch()
		if c.connected and c.state == Session.State.READY and c.attempt_id != last_c_vote:
			last_c_vote = c.attempt_id
			c.ready_or_rematch()
		await create_timer(0.01).timeout
	check(false,"Timed out waiting for shared build state")
	return false

func both_build(round_index: int, turn: int) -> bool:
	return h.state == Session.State.BUILD and c.state == Session.State.BUILD and h.build_round == round_index and c.build_round == round_index and h.build_turn == turn and c.build_turn == turn

func builder() -> Node:
	return h if h.build_slot == 0 else c

func place(slot: int, kind: String, cell: int) -> void:
	builder().send_command("place",{"slot":slot,"kind":kind,"cell":cell,"rotation":2})

func _init() -> void:
	latency = OS.get_cmdline_user_args().has("--latency")
	call_deferred("run")

func run() -> void:
	host_root = Node.new(); host_root.name = "Host"; root.add_child(host_root)
	client_root = Node.new(); client_root.name = "Client"; root.add_child(client_root)
	set_multiplayer(MultiplayerAPI.create_default_interface(),host_root.get_path())
	set_multiplayer(MultiplayerAPI.create_default_interface(),client_root.get_path())
	host_game = Node3D.new(); host_game.set_script(Fixture); host_game.name = "PenaltyYard"; host_root.add_child(host_game)
	client_game = Node3D.new(); client_game.set_script(Fixture); client_game.delay_network = latency; client_game.name = "PenaltyYard"; client_root.add_child(client_game)
	h = host_game.network; c = client_game.network
	h.countdown_duration = 0.06; h.prepare_duration = 0.06; h.result_duration = 0.3; h.build_duration = 4.0
	var port := 31000 + randi_range(0,4000)
	h.start_host(port); c.join_room("127.0.0.1",port)
	if not await wait_for(func(): return both_build(1,0)):
		await cleanup(); return
	check(h.match_rules.attempts == 2 and host_game.field.layout == FieldRules.empty_layout(),"Round one has two attempts and no items")
	var original_builder: int = h.build_slot
	var original_nonce: int = h.attempt_id
	h.prepare_duration = 4.0
	var other: Node = c if original_builder == 0 else h
	other.send_command("place",{"slot":0,"kind":"shield","cell":1,"rotation":2})
	await create_timer(0.1).timeout
	check(host_game.field.layout == FieldRules.empty_layout(),"Non-builder cannot place items")
	place(2,"shield",1)
	place(0,"shield",12)
	await create_timer(0.1).timeout
	check(host_game.field.layout == FieldRules.empty_layout() and h.build_turn == 0,"Reject foreign slot and blocked corridors without consuming turn")
	place(0,"shield",1)
	if not await wait_for(func(): return both_build(1,1)):
		await cleanup(); return
	check(h.build_slot != original_builder,"Second player receives a build turn")
	# Repeat the first player's stale command after the turn switched.
	c._command.rpc_id(1,original_nonce,"place",{"slot":0,"kind":"shield","cell":4,"rotation":2})
	place(0,"fan_right",9)
	if not await wait_for(func(): return h.state == Session.State.AIM and c.state == Session.State.AIM):
		await cleanup(); return
	var frozen: Array = host_game.field.layout.duplicate(true)
	check(frozen == client_game.field.layout,"Installed shield and fan agree on both peers")
	check(frozen[original_builder*2].kind == "shield" and frozen[(1-original_builder)*2].kind == "fan_right","Each item belongs to its builder")
	h.send_command("place",{"slot":0,"kind":"fan_left","cell":4,"rotation":2})
	c.send_command("place",{"slot":0,"kind":"fan_left","cell":4,"rotation":2})
	await create_timer(0.1).timeout
	check(host_game.field.layout == frozen,"Placement commands cannot change field during shots")
	var shooter: Node = h if h.local_shooter() else c
	shooter.send_command("begin",{})
	await create_timer(0.35).timeout
	shooter.send_command("release",{"target":Vector3(-2,0.8,0),"spin":0})
	if not await wait_for(func(): return h.state == Session.State.FLIGHT and host_game.ball.velocity.z > 0):
		await cleanup(); return
	check(true,"Real network shot rebounds off installed shield")
	h.prepare_duration = 0.06
	if not await wait_for(func(): return h.state == Session.State.RESULT and c.state == Session.State.RESULT):
		await cleanup(); return
	check(host_game.ball.position.distance_to(client_game.ball.position) < 0.01 and h.last_outcome == c.last_outcome,"Both peers receive the same physical obstacle result")
	if not await wait_for(func(): return h.match_rules.attempts == 3 and c.match_rules.attempts == 3):
		await cleanup(); return
	check(host_game.field.layout == frozen and client_game.field.layout == frozen,"Field stays identical after first shot of pair")
	if not await wait_for(func(): return both_build(2,0)):
		await cleanup(); return
	check(h.build_slot != original_builder,"Starting builder alternates next round")
	place(1,"fan_left",4)
	if not await wait_for(func(): return both_build(2,1)):
		await cleanup(); return
	place(1,"fan_right",10)
	if not await wait_for(func(): return both_build(3,0)):
		await cleanup(); return
	check(host_game.field.layout.filter(func(x): return not x.is_empty()).size() == 4,"Four-item cap: two items from each player")
	var before: Array = host_game.field.layout.duplicate(true)
	var owner: int = h.build_slot
	var own_cell: int = before[owner*2].cell
	place(0,"fan_left",own_cell)
	if not await wait_for(func(): return both_build(3,1)):
		await cleanup(); return
	check(host_game.field.layout[owner*2].kind == "fan_left","Full owner inventory can replace its own item")
	check(host_game.field.layout[(1-owner)*2] == before[(1-owner)*2] and host_game.field.layout[(1-owner)*2+1] == before[(1-owner)*2+1],"Replacement preserves opponent items")
	var replacement: Array = host_game.field.layout.duplicate(true)
	h.build_duration = 0.06
	h.timer = 0.06
	if not await wait_for(func(): return h.state == Session.State.FINISHED and c.state == Session.State.FINISHED,20.0):
		await cleanup(); return
	check(h.match_rules.attempts == 20,"Tied match completes all five extra pairs")
	check(h.build_round == 4,"Extra pairs do not allow more construction")
	check(host_game.field.layout == replacement and client_game.field.layout == replacement,"Build time-outs skip turns and extra pairs freeze the field")
	h.ready_or_rematch(); c.ready_or_rematch()
	await wait_for(func(): return h.match_rules.attempts == 0 and c.match_rules.attempts == 0)
	check(host_game.field.layout == FieldRules.empty_layout() and client_game.field.layout == FieldRules.empty_layout(),"Rematch clears shared field on both peers")
	h.build_duration = 4.0
	if await wait_for(func(): return both_build(1,0)):
		c.close_session("Leave during construction")
		await wait_for(func(): return not h.online,7.0)
		check(not h.online and not c.online and not host_game.field.panel.visible,"Disconnect during construction closes the shared field")
	await cleanup()

func cleanup() -> void:
	if h.online: h.close_session("Test cleanup")
	if c.online: c.close_session("Test cleanup")
	await create_timer(0.2).timeout
	host_root.queue_free(); client_root.queue_free()
	await process_frame
	print("Network build%s: %d checks, %d failures" % [" (+120 ms commands/state)" if latency else "",checks,failures])
	quit(1 if failures else 0)
