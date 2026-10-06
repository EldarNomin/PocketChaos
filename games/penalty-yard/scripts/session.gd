extends Node
## Host-authoritative, two-player ENet session. Clients send input, not outcomes.

const MatchRules = preload("res://scripts/match_rules.gd")
const Rules = preload("res://scripts/rules.gd")
const Tuning = preload("res://scripts/tuning.gd")
const FieldRules = preload("res://scripts/field_rules.gd")
const GameAudio = preload("res://scripts/audio.gd")
const Settings = preload("res://scripts/settings.gd")
const PROTOCOL := 4
const DEFAULT_PORT := 24567
enum State { WAITING, READY, COUNTDOWN, AIM, FLIGHT, RESULT, FINISHED, BUILD }

var game: Node3D
var peer: ENetMultiplayerPeer
var online := false
var host := false
var connected := false
var guest_id := 0
var pending_id := 0
var match_rules := MatchRules.new()
var active_shooter_slot := 0
var state := State.WAITING
var attempt_id := 0
var snapshot_seq := 0
var last_snapshot_seq := -1
var applied_attempt := -1
var ready_votes: Array[bool] = [false, false]
var rematch_votes: Array[bool] = [false, false]
var timer := 0.0
var countdown_duration := 2.0
var result_duration := 1.5
var prepare_duration := 10.0
var input_clock := 0.0
var snapshot_clock := 0.0
var connection_clock := 0.0
var clock := 0.0
var charge_start := -1.0
var keeper_axis := 0.0
var keeper_offset := Vector3(0, 1.2, Rules.CATCH_PLANE)
var keeper_input_age := 0.0
var input_seq := 0
var last_input_seq := -1
var remote_ball_position := Rules.SHOT_ORIGIN
var remote_ball_velocity := Vector3.ZERO
var remote_keeper_x := 0.0
var remote_hands := Vector3(0, 1.2, Rules.CATCH_PLANE)
var snapshot_age := 0.0
var event_id := 0
var last_event_id := 0
var last_outcome := ""
var message := ""
var local_ready := false
var local_rematch := false
var client_dash_time := 0.0
var client_dash_axis := 0.0
var local_dash_pending := false
var accepted_shots := 0
var rejected_commands := 0
var build_duration := 15.0
var build_round := -1
var build_turn := 0
var build_slot := 0
var field_revision := 0
var room_panel: Control
var room_status: Label
var address_field: LineEdit
var port_field: SpinBox
var host_button: Button
var join_button: Button
var leave_button: Button

func _ready() -> void:
	game = get_parent()
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	build_room_ui()

func build_room_ui() -> void:
	room_panel = Control.new()
	room_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui_root.add_child(room_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_panel.add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_panel.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", game.panel_style())
	centre.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	panel.add_child(stack)
	stack.add_child(game.label("Игра с другом", 28))
	stack.add_child(game.label("Один создаёт комнату. Второй вводит его IP и порт.", 17))
	var row := HBoxContainer.new()
	address_field = LineEdit.new()
	address_field.text = str(game.settings.get("last_address", "127.0.0.1"))
	address_field.placeholder_text = "IP хозяина комнаты"
	address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_field.custom_minimum_size = Vector2(310, 40)
	row.add_child(address_field)
	port_field = SpinBox.new()
	port_field.min_value = 1024
	port_field.max_value = 65535
	port_field.value = int(game.settings.get("last_port", DEFAULT_PORT))
	row.add_child(port_field)
	stack.add_child(row)
	var actions := HBoxContainer.new()
	host_button = game.button("Создать", func(): start_host(int(port_field.value)))
	join_button = game.button("Подключиться", func(): join_room(address_field.text.strip_edges(), int(port_field.value)))
	leave_button = game.button("Выйти из комнаты", func(): close_session("Ты вышел из комнаты."))
	actions.add_child(host_button)
	actions.add_child(join_button)
	actions.add_child(leave_button)
	stack.add_child(actions)
	room_status = game.label("", 17)
	room_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_status.custom_minimum_size = Vector2(580, 64)
	stack.add_child(room_status)
	var help: Label = game.label("127.0.0.1 — два окна на одном ПК. Для двух ПК в одной сети нужен локальный IP хозяина. Между разными сетями нужен доступный адрес хозяина и UDP-порт.", 15)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 580
	stack.add_child(help)
	stack.add_child(game.button("Вернуться к игре", func(): room_panel.hide()))
	room_panel.hide()
	refresh_room()

func show_room() -> void:
	game.charging = false
	game.power = 0.0
	if online:
		send_command("cancel", {})
	refresh_room()
	room_panel.show()

func refresh_room() -> void:
	if room_status == null:
		return
	room_status.text = message if message != "" else "Комната ещё не создана. Можно продолжить локальную тренировку."
	host_button.disabled = online
	join_button.disabled = online
	leave_button.disabled = not online
	address_field.editable = not online
	port_field.editable = not online

func start_host(port: int) -> Error:
	if online or port < 1024 or port > 65535:
		return ERR_INVALID_PARAMETER
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 1, 3)
	if error != OK:
		message = "Не удалось создать комнату. Возможно, порт уже занят."
		refresh_room()
		return error
	online = true
	host = true
	connected = false
	state = State.WAITING
	guest_id = 0
	pending_id = 0
	connection_clock = 0.0
	multiplayer.multiplayer_peer = peer
	game.field.clear()
	field_revision = game.field.revision
	build_round = -1
	var addresses: Array[String] = []
	for address in IP.get_local_addresses():
		if ":" not in address and not address.begins_with("127."):
			addresses.append(address)
	message = "Ждём друга. Порт: %d. Адреса этого ПК: %s" % [port, ", ".join(addresses)]
	game.reset_attempt(true)
	game.set_paused(false)
	refresh_room()
	game.update_ui()
	return OK

func join_room(address: String, port: int) -> Error:
	if online or not address.is_valid_ip_address() or port < 1024 or port > 65535:
		message = "Введи корректный IP и порт (1024–65535)."
		refresh_room()
		return ERR_INVALID_PARAMETER
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port, 3)
	if error != OK:
		message = "Не удалось начать подключение. Проверь адрес и порт."
		refresh_room()
		return error
	game.settings.last_address = address
	game.settings.last_port = port
	Settings.save_config(game.settings)
	online = true
	host = false
	connected = false
	state = State.WAITING
	last_snapshot_seq = -1
	applied_attempt = -1
	last_event_id = 0
	connection_clock = 0.0
	multiplayer.multiplayer_peer = peer
	game.field.clear()
	# Force the first authoritative layout to replace any local training field.
	game.field.revision = -1
	message = "Подключаемся к %s:%d…" % [address, port]
	game.reset_attempt(true)
	game.set_paused(false)
	refresh_room()
	game.update_ui()
	return OK

func close_session(reason := "Комната закрыта.") -> void:
	online = false
	connected = false
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null
	guest_id = 0
	pending_id = 0
	state = State.WAITING
	message = reason
	game.field.clear()
	game.mode = game.Mode.SHOOTER
	game.reset_attempt(true)
	game.set_paused(false)
	refresh_room()
	room_panel.show()

func _peer_connected(id: int) -> void:
	if online and host:
		pending_id = id
		connection_clock = 0.0

func _connected_to_server() -> void:
	if online and not host:
		_handshake.rpc_id(1, PROTOCOL)

func _connection_failed() -> void:
	if online:
		close_session("Не удалось подключиться. Проверь адрес, порт и доступность комнаты.")

func _server_disconnected() -> void:
	if online and not host:
		close_session("Хозяин комнаты отключился. Матч прерван.")

func _peer_disconnected(id: int) -> void:
	if online and host and id in [guest_id, pending_id]:
		close_session("Друг отключился. Матч прерван; можно создать новую комнату.")

@rpc("any_peer", "call_remote", "reliable", 0)
func _handshake(version: int) -> void:
	if not online or not host or connected:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != pending_id or version != PROTOCOL:
		peer.disconnect_peer(sender)
		return
	guest_id = sender
	connected = true
	message = "Друг подключился. Оба нажмите «Готов» или R."
	match_rules.reset(randi_range(0, 1))
	rematch_votes = [false, false]
	local_rematch = false
	_prepare_attempt()
	room_panel.hide()
	refresh_room()

func local_slot() -> int:
	return 0 if host else 1

func local_shooter() -> bool:
	return active_shooter_slot == local_slot()

func shooter_peer() -> int:
	return 1 if active_shooter_slot == 0 else guest_id

func keeper_peer() -> int:
	return guest_id if active_shooter_slot == 0 else 1

func _prepare_attempt() -> void:
	if match_rules.shot_in_round == 0 and match_rules.round_index in [1,2,3,4] and build_round != match_rules.round_index:
		_begin_build()
		return
	game.field.hide_builder()
	attempt_id += 1
	active_shooter_slot = match_rules.shooter_slot()
	ready_votes = [false, false]
	local_ready = false
	state = State.READY
	timer = 0.0
	charge_start = -1.0
	keeper_axis = 0.0
	keeper_offset = Vector3(0, 1.2, Rules.CATCH_PLANE)
	keeper_input_age = 0.0
	last_input_seq = -1
	input_seq = 0
	last_outcome = ""
	_apply_local_role()
	_publish(true)

func _begin_build() -> void:
	build_round = match_rules.round_index
	build_turn = 0
	_start_build_turn()

func _start_build_turn() -> void:
	# Build turns use distinct nonces, so late commands cannot affect another turn.
	attempt_id += 1
	state = State.BUILD
	build_slot = (build_round + build_turn) % 2
	timer = build_duration
	charge_start = -1.0
	game.reset_attempt(true)
	game.field.show_builder()
	applied_attempt = attempt_id
	_publish(true)

func _next_builder() -> void:
	build_turn += 1
	if build_turn < 2:
		_start_build_turn()
	else:
		_prepare_attempt()

func _apply_local_role() -> void:
	game.mode = game.Mode.SHOOTER if local_shooter() else game.Mode.KEEPER
	game.reset_attempt(true)
	applied_attempt = attempt_id
	game.opponent_keeper.visible = local_shooter()
	game.opponent_hands.visible = local_shooter()
	local_dash_pending = false

func ready_or_rematch() -> void:
	if not online or not connected:
		return
	if state == State.FINISHED:
		send_command("rematch", {})
	elif state == State.READY:
		send_command("ready", {})

func send_command(operation: String, data: Dictionary) -> void:
	if not online or not connected:
		return
	if host:
		_accept_command(1, attempt_id, operation, data)
	else:
		_command.rpc_id(1, attempt_id, operation, data)

@rpc("any_peer", "call_remote", "reliable", 0)
func _command(nonce: int, operation: String, data: Dictionary) -> void:
	if online and host:
		_accept_command(multiplayer.get_remote_sender_id(), nonce, operation, data)

func _accept_command(sender: int, nonce: int, operation: String, data: Dictionary) -> void:
	if not connected or sender not in [1, guest_id] or nonce != attempt_id:
		rejected_commands += 1
		return
	var slot := 0 if sender == 1 else 1
	if state == State.BUILD and slot == build_slot:
		if operation == "skip":
			_next_builder()
			return
		if operation == "place":
			if not (data.get("slot") is int and data.get("kind") is String and data.get("cell") is int and data.get("rotation") is int):
				rejected_commands += 1
				return
			var error := FieldRules.placement_error(game.field.layout,slot,int(data.slot),str(data.kind),int(data.cell),int(data.rotation))
			if error != "":
				rejected_commands += 1
				if sender == 1:
					game.field.last_error = error
				else:
					_build_error.rpc_id(sender,attempt_id,error)
				return
			var layout: Array = game.field.layout.duplicate(true)
			layout[slot*2+int(data.slot)] = {"owner":slot,"kind":str(data.kind),"cell":int(data.cell),"rotation":int(data.rotation)}
			field_revision += 1
			game.field.apply_layout(layout,field_revision)
			event_id += 1
			game.play_sound("place")
			_next_builder()
			return
	if operation == "ready" and state == State.READY:
		ready_votes[slot] = true
		local_ready = ready_votes[local_slot()]
		if ready_votes[0] and ready_votes[1]:
			state = State.COUNTDOWN
			timer = countdown_duration
			game.phase = game.Phase.COUNTDOWN
			event_id += 1
			game.play_sound("whistle")
		_publish(true)
		return
	if operation == "rematch" and state == State.FINISHED:
		rematch_votes[slot] = true
		local_rematch = rematch_votes[local_slot()]
		if rematch_votes[0] and rematch_votes[1]:
			var first := 1 - match_rules.initial_first
			match_rules.reset(first)
			rematch_votes = [false, false]
			local_rematch = false
			game.field.clear()
			field_revision = game.field.revision
			build_round = -1
			_prepare_attempt()
		else:
			_publish(true)
		return
	if sender == shooter_peer() and state == State.AIM:
		if operation == "begin":
			if charge_start < 0.0:
				charge_start = clock
			return
		if operation == "cancel":
			charge_start = -1.0
			return
		if operation == "release" and charge_start >= 0.0:
			var target_value: Variant = data.get("target")
			var curve_value: Variant = data.get("spin")
			if not (target_value is Vector3) or not target_value.is_finite() or not (curve_value is int):
				rejected_commands += 1
				return
			var target: Vector3 = target_value
			target = Vector3(clampf(target.x, -4.2, 4.2), clampf(target.y, 0.25, 3.4), 0)
			var strength := clampf((clock - charge_start) / Tuning.CHARGE_TIME, 0, 1)
			charge_start = -1.0
			state = State.FLIGHT
			game.fire(target, strength, float(clampi(curve_value, -1, 1)))
			accepted_shots += 1
			event_id += 1
			_publish(true)
			return
	if sender == keeper_peer() and state in [State.COUNTDOWN, State.AIM, State.FLIGHT]:
		if operation == "catch" and state == State.FLIGHT and game.catch_cooldown <= 0.0:
			game.catch_remaining = Tuning.CATCH_DURATION
			game.catch_cooldown = Tuning.CATCH_COOLDOWN
			return
		if operation == "dash" and not game.dash_used:
			var axis_value: Variant = data.get("axis")
			if not (axis_value is float or axis_value is int) or not is_finite(float(axis_value)) or float(axis_value) == 0.0:
				rejected_commands += 1
				return
			game.dash_direction = signf(float(axis_value))
			game.dash_remaining = Tuning.DASH_DURATION
			game.dash_used = true
			return
	rejected_commands += 1

@rpc("authority", "call_remote", "reliable", 0)
func _build_error(nonce: int, error: String) -> void:
	if online and state == State.BUILD and nonce == attempt_id:
		game.field.last_error = error

func send_pose(nonce: int, axis: float, offset: Vector3, sequence: int) -> void:
	if not online or not connected:
		return
	if host:
		_accept_pose(1, nonce, axis, offset, sequence)
	else:
		_keeper_input.rpc_id(1, nonce, axis, offset, sequence)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _keeper_input(nonce: int, axis: float, offset: Vector3, sequence: int) -> void:
	if online and host:
		_accept_pose(multiplayer.get_remote_sender_id(), nonce, axis, offset, sequence)

func _accept_pose(sender: int, nonce: int, axis: float, offset: Vector3, sequence: int) -> void:
	if not connected or sender != keeper_peer() or nonce != attempt_id or sequence <= last_input_seq:
		return
	if not is_finite(axis) or not offset.is_finite():
		return
	last_input_seq = sequence
	keeper_axis = clampf(axis, -1, 1)
	keeper_offset = Vector3(clampf(offset.x, -Tuning.HAND_REACH, Tuning.HAND_REACH), clampf(offset.y, 0.3, 2.3), Rules.CATCH_PLANE)
	keeper_input_age = 0.0

func handle_input(event: InputEvent) -> void:
	if not connected or room_panel.visible:
		return
	if state == State.BUILD:
		game.field.handle_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			ready_or_rematch()
		elif local_shooter() and state == State.AIM:
			if event.keycode == KEY_Q:
				game.spin = maxi(-1, game.spin - 1)
			elif event.keycode == KEY_E:
				game.spin = mini(1, game.spin + 1)
		elif not local_shooter() and event.keycode == KEY_SPACE and state in [State.COUNTDOWN, State.AIM, State.FLIGHT]:
			var axis: float = game.movement_axis()
			if not game.dash_used and axis != 0.0:
				send_command("dash", {"axis": axis})
				if not host:
					client_dash_time = Tuning.DASH_DURATION
					client_dash_axis = axis
					game.dash_used = true
					local_dash_pending = true
	if event is InputEventMouseButton:
		if local_shooter() and state == State.AIM:
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				game.charging = false
				game.power = 0.0
				send_command("cancel", {})
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					game.charging = true
					game.power = 0.0
					send_command("begin", {})
				elif game.charging:
					game.charging = false
					send_command("release", {"target": game.aim, "spin": game.spin})
		elif not local_shooter() and state == State.FLIGHT and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if game.catch_cooldown <= 0:
				send_command("catch", {})
				if not host:
					game.catch_remaining = Tuning.CATCH_DURATION
					game.catch_cooldown = Tuning.CATCH_COOLDOWN

func tick(delta: float) -> void:
	clock += delta
	connection_clock += delta
	if not connected:
		if (not host or pending_id != 0) and connection_clock > 10.0:
			close_session("Подключение не завершилось. Проверь доступность комнаты и версию игры.")
		game.update_ui()
		return
	if game.charging and not game.paused:
		game.power = minf(1.0, game.power + delta / Tuning.CHARGE_TIME)
	var blocked: bool = game.paused or room_panel.visible or game.overlay_open()
	var local_axis: float = 0.0 if blocked else game.movement_axis()
	if not blocked and state != State.BUILD:
		game.update_pointer()
	if not local_shooter() and state != State.BUILD:
		input_clock += delta
		if input_clock >= 1.0 / 30.0:
			input_clock = 0.0
			input_seq += 1
			send_pose(attempt_id, local_axis, game.hand_target - Vector3(game.keeper_x, 0, 0), input_seq)
	if host:
		_tick_host(delta)
	else:
		_tick_client(delta, local_axis)
	game.update_ui()

func _tick_host(delta: float) -> void:
	game.catch_remaining = maxf(0, game.catch_remaining - delta)
	game.catch_cooldown = maxf(0, game.catch_cooldown - delta)
	keeper_input_age += delta
	if keeper_input_age > 0.25:
		keeper_axis = 0.0
	if state in [State.COUNTDOWN, State.AIM, State.FLIGHT]:
		var movement := keeper_axis * Tuning.KEEPER_SPEED
		if game.dash_remaining > 0:
			movement = game.dash_direction * Tuning.DASH_SPEED
			game.dash_remaining = maxf(0, game.dash_remaining - delta)
		game.keeper_x = clampf(game.keeper_x - movement * delta, -2.7, 2.7)
	game.hand_target = Vector3(game.keeper_x, 0, 0) + keeper_offset
	if not local_shooter() and state != State.BUILD:
		game.camera.position.x = game.keeper_x
		game.gloves.position = game.hand_target
	game.opponent_keeper.position.x = game.keeper_x
	game.opponent_hands.position = game.hand_target
	game.update_keeper_arms()
	if state == State.BUILD:
		timer -= delta
		if timer <= 0:
			_next_builder()
	elif state == State.COUNTDOWN:
		timer -= delta
		if timer <= 0:
			state = State.AIM
			timer = prepare_duration
			game.phase = game.Phase.READY
			_publish(true)
	elif state == State.AIM:
		timer -= delta
		if timer <= 0:
			state = State.FLIGHT
			game.phase = game.Phase.FLIGHT
			finish_attempt("miss")
	elif state == State.FLIGHT:
		game.step_flight(delta, true)
	elif state == State.RESULT:
		timer -= delta
		if timer <= 0:
			if match_rules.finished:
				state = State.FINISHED
				_publish(true)
			else:
				_prepare_attempt()
	snapshot_clock += delta
	if snapshot_clock >= 1.0 / 30.0:
		snapshot_clock = 0.0
		_publish(false)

func _tick_client(delta: float, axis: float) -> void:
	snapshot_age += delta
	if state == State.FLIGHT:
		# Extrapolate only the visual ball briefly. Never decide outcomes locally.
		var ahead := minf(snapshot_age, 0.065)
		var predicted := remote_ball_position + remote_ball_velocity * ahead
		game.ball.position = game.ball.position.lerp(predicted, minf(1, delta * 35))
	else:
		game.ball.position = remote_ball_position
	game.catch_remaining = maxf(0, game.catch_remaining - delta)
	game.catch_cooldown = maxf(0, game.catch_cooldown - delta)
	if not local_shooter() and state != State.BUILD:
		if state in [State.COUNTDOWN, State.AIM, State.FLIGHT]:
			var speed := axis * Tuning.KEEPER_SPEED
			if client_dash_time > 0:
				speed = client_dash_axis * Tuning.DASH_SPEED
				client_dash_time = maxf(0, client_dash_time - delta)
			game.keeper_x = clampf(game.keeper_x - speed * delta, -2.7, 2.7)
		game.keeper_x = lerpf(game.keeper_x, remote_keeper_x, minf(1, delta * 8))
		game.camera.position.x = game.keeper_x
		if not game.paused and not room_panel.visible:
			game.update_pointer()
	game.opponent_keeper.position.x = remote_keeper_x
	game.opponent_hands.position = remote_hands
	game.update_keeper_arms()
	if state == State.FLIGHT:
		game.record_trail(delta)

func finish_attempt(outcome: String) -> void:
	if not host or state != State.FLIGHT:
		return
	state = State.RESULT
	timer = result_duration
	last_outcome = outcome
	charge_start = -1.0
	game.ball.live = false
	game.ball.velocity = Vector3.ZERO
	game.phase = game.Phase.RESULT
	game.charging = false
	match_rules.record(outcome == "goal")
	event_id += 1
	game.play_sound(GameAudio.outcome_sound(outcome))
	_publish(true)

func _snapshot() -> Dictionary:
	snapshot_seq += 1
	return {
		"seq": snapshot_seq, "attempt": attempt_id, "guest": guest_id,
		"state": state, "timer": timer, "scores": match_rules.scores.duplicate(), "shooter": active_shooter_slot,
		"first": match_rules.initial_first, "round": match_rules.round_index,
		"shot": match_rules.shot_in_round, "attempts": match_rules.attempts,
		"finished": match_rules.finished, "ready": ready_votes.duplicate(),
		"rematch": rematch_votes.duplicate(), "ball": game.ball.position,
		"velocity": game.ball.velocity, "keeper": game.keeper_x,
		"hands": game.hand_target, "dash": game.dash_used,
		"catch": game.catch_remaining, "cooldown": game.catch_cooldown,
		"event": event_id, "outcome": last_outcome,
		"field": game.field.layout.duplicate(true), "field_revision": field_revision,
		"build_round": build_round, "build_turn": build_turn, "build_slot": build_slot,
	}

func _publish(reliable: bool) -> void:
	if not connected or guest_id == 0:
		return
	var data := _snapshot()
	if reliable:
		_state_reliable.rpc_id(guest_id, data)
	else:
		_state_stream.rpc_id(guest_id, data)

@rpc("authority", "call_remote", "reliable", 0)
func _state_reliable(data: Dictionary) -> void:
	_apply_state(data)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _state_stream(data: Dictionary) -> void:
	_apply_state(data)

func _apply_state(data: Dictionary) -> void:
	if not online or host or int(data.get("seq", -1)) <= last_snapshot_seq:
		return
	var was_connected := connected
	last_snapshot_seq = int(data.seq)
	connected = true
	guest_id = int(data.guest)
	state = int(data.state)
	active_shooter_slot = int(data.shooter)
	attempt_id = int(data.attempt)
	timer = float(data.timer)
	match_rules.scores.assign(data.scores)
	match_rules.initial_first = int(data.first)
	match_rules.round_index = int(data.round)
	match_rules.shot_in_round = int(data.shot)
	match_rules.attempts = int(data.attempts)
	match_rules.finished = bool(data.finished)
	ready_votes.assign(data.ready)
	rematch_votes.assign(data.rematch)
	local_ready = ready_votes[1]
	local_rematch = rematch_votes[1]
	build_round = int(data.build_round)
	build_turn = int(data.build_turn)
	build_slot = int(data.build_slot)
	field_revision = int(data.field_revision)
	game.field.apply_layout(data.field,field_revision)
	if applied_attempt != attempt_id:
		if state == State.BUILD:
			game.reset_attempt(true)
			game.field.show_builder()
			applied_attempt = attempt_id
		else:
			game.field.hide_builder()
			_apply_local_role()
		input_seq = 0
		client_dash_time = 0
	remote_ball_position = data.ball
	remote_ball_velocity = data.velocity
	remote_keeper_x = float(data.keeper)
	remote_hands = data.hands
	snapshot_age = 0
	if local_shooter():
		game.keeper_x = remote_keeper_x
		game.hand_target = remote_hands
	game.dash_used = bool(data.dash) or local_dash_pending
	if host or local_shooter():
		game.catch_remaining = float(data.catch)
		game.catch_cooldown = float(data.cooldown)
	else:
		game.catch_cooldown = maxf(game.catch_cooldown, float(data.cooldown))
	if state != State.FLIGHT:
		game.ball.position = remote_ball_position
	game.phase = game.Phase.FLIGHT if state == State.FLIGHT else (game.Phase.RESULT if state in [State.RESULT, State.FINISHED] else game.Phase.READY)
	if state != State.AIM:
		game.charging = false
	if int(data.event) > last_event_id:
		last_event_id = int(data.event)
		match int(data.state):
			State.FLIGHT: game.play_sound("kick")
			State.COUNTDOWN: game.play_sound("whistle")
			State.RESULT: game.play_sound(GameAudio.outcome_sound(str(data.outcome)))
			State.BUILD: game.play_sound("place")
	last_outcome = str(data.outcome)
	message = "Друг подключился. Матч на двоих."
	if not was_connected:
		room_panel.hide()
	game.update_ui()

func draw_ui() -> void:
	game.shooter_button.disabled = true
	game.keeper_button.disabled = true
	game.power_bar.visible = local_shooter() and state == State.AIM
	game.power_bar.value = game.power
	game.repeat_button.text = "Реванш · R" if state == State.FINISHED else "Готов · R"
	game.repeat_button.disabled = not connected or state not in [State.READY, State.FINISHED]
	game.pause_note.text = "Матч продолжается, пока открыто меню."
	if not connected:
		game.header.text = "Ждём подключения"
		game.stats.text = "Сетевая дуэль · версия 0.7"
		game.status.text = "Открой «Онлайн», чтобы увидеть состояние комнаты"
		game.detail.text = message
		game.controls.text = "Локальная тренировка доступна после выхода из комнаты"
		return
	var slot := local_slot()
	game.header.text = "Твой удар" if local_shooter() else "Ты защищаешь ворота"
	game.stats.text = "Ты %d : %d Друг   ·   %s   ·   Онлайн 0.7" % [match_rules.scores[slot], match_rules.scores[1 - slot], "Раунд %d / 5" % (match_rules.round_index + 1) if match_rules.round_index < 5 else "Дополнительные попытки"]
	game.detail.text = "Подкрутка: %s   ·   Сила: %d%%" % [["влево", "нет", "вправо"][game.spin + 1], int(game.power * 100)] if local_shooter() else "Рывок: %s   ·   Ловля: %s" % ["использован" if game.dash_used else "готов", "активна" if game.catch_remaining > 0 else "готова"]
	game.controls.text = "Мышь — прицел   ·   ЛКМ удержать и отпустить — удар   ·   Q / E — подкрутка   ·   ПКМ — отмена" if local_shooter() else "A / D — движение   ·   Мышь — руки   ·   ЛКМ — ловля   ·   Space + A / D — рывок"
	match state:
		State.BUILD:
			game.header.text = "Меняем площадку"
			game.status.text = "Твой ход: %d сек." % maxi(1,int(ceil(timer))) if build_slot == slot else "Друг размещает предмет: %d сек." % maxi(1,int(ceil(timer)))
			game.detail.text = "До двух предметов от каждого. Поле одинаковое для обоих ударов."
			game.controls.text = "Выбери предмет слева   ·   Клик по площадке — поставить   ·   Q / E — угол   ·   R — пропустить"
		State.READY: game.status.text = "Ждём готовности друга" if ready_votes[slot] else "Нажми «Готов» или R"
		State.COUNTDOWN: game.status.text = "Приготовься: %d…" % maxi(1, int(ceil(timer)))
		State.AIM: game.status.text = "На удар осталось %d сек." % maxi(1, int(ceil(timer))) if local_shooter() else "Следи за мячом — друг готовит удар"
		State.FLIGHT: game.status.text = "Мяч в игре" if local_shooter() else "Лови!"
		State.RESULT: game.status.text = {"goal": "ГОЛ!", "save": "Мяч пойман!", "miss": "Мимо ворот"}.get(last_outcome, "Попытка завершена")
		State.FINISHED:
			var winner: int = match_rules.winner()
			game.header.text = "Ничья" if winner < 0 else ("Ты выиграл!" if winner == slot else "Друг выиграл")
			game.status.text = "Ждём согласия друга на реванш" if rematch_votes[slot] else "Матч завершён. Реванш — R"

func _exit_tree() -> void:
	if peer != null:
		peer.close()
