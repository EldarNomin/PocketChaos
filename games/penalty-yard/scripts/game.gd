extends Node3D

const Rules = preload("res://scripts/rules.gd")
const Tuning = preload("res://scripts/tuning.gd")
const BallScript = preload("res://scripts/ball.gd")
const YardScript = preload("res://scripts/yard.gd")
const SessionScript = preload("res://scripts/session.gd")
enum Mode { SHOOTER, KEEPER }
enum Phase { READY, COUNTDOWN, FLIGHT, RESULT }

var mode := Mode.SHOOTER
var phase := Phase.READY
var ball: CharacterBody3D
var camera: Camera3D
var yard: Node3D
var gloves: Node3D
var training_striker: Node3D
var opponent_keeper: Node3D
var opponent_hands: Node3D
var network: Node
var ui_root: Control
var aim_marker: MeshInstance3D
var trail: ImmediateMesh
var trail_points: Array[Vector3] = []
var trail_clock := 0.0
var aim := Vector3(0, 1.1, 0)
var power := 0.0
var charging := false
var spin := 0
var keeper_x := 0.0
var hand_target := Vector3(0, 1.2, Rules.CATCH_PLANE)
var catch_remaining := 0.0
var catch_cooldown := 0.0
var dash_remaining := 0.0
var dash_direction := 0.0
var dash_used := false
var countdown := 0.0
var paused := false
var result_text := ""
var practice_index := 0
var shots_completed := 0
var goals := 0
var keeper_completed := 0
var saves := 0
var header: Label
var status: Label
var stats: Label
var controls: Label
var detail: Label
var power_bar: ProgressBar
var pause_panel: Control
var sound: AudioStreamPlayer
var shooter_button: Button
var keeper_button: Button
var repeat_button: Button
var pause_note: Label

func _ready() -> void:
	yard = Node3D.new()
	yard.set_script(YardScript)
	add_child(yard)
	ball = CharacterBody3D.new()
	ball.set_script(BallScript)
	add_child(ball)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.far = 100.0
	add_child(camera)
	camera.make_current()
	gloves = Node3D.new()
	add_child(gloves)
	for x in [-0.20, 0.20]:
		yard.box(Vector3(0.23, 0.28, 0.13), Vector3.ZERO, Color("e5aa69")).reparent(gloves)
		var glove := gloves.get_child(gloves.get_child_count() - 1) as MeshInstance3D
		glove.position = Vector3(x, 0, 0)
		var cuff: MeshInstance3D = yard.box(Vector3(0.19, 0.10, 0.16), Vector3.ZERO, Color("415863"))
		cuff.reparent(gloves)
		cuff.position = Vector3(x, -0.17, 0)
	# Static training striker visible from the goalkeeper's position.
	training_striker = Node3D.new()
	add_child(training_striker)
	yard.box(Vector3(0.5, 0.7, 0.3), Vector3(0, 1.05, 11), Color("d08256")).reparent(training_striker)
	yard.box(Vector3(0.36, 0.36, 0.36), Vector3(0, 1.62, 11), Color("e4bd91")).reparent(training_striker)
	for x in [-0.16, 0.16]:
		yard.box(Vector3(0.17, 0.65, 0.2), Vector3(x, 0.38, 11), Color("314858")).reparent(training_striker)
	opponent_keeper = Node3D.new()
	add_child(opponent_keeper)
	yard.box(Vector3(0.55, 0.65, 0.3), Vector3(0, 1.0, 0.22), Color("619da5")).reparent(opponent_keeper)
	yard.box(Vector3(0.35, 0.35, 0.35), Vector3(0, 1.5, 0.22), Color("e4bd91")).reparent(opponent_keeper)
	for x in [-0.17, 0.17]:
		yard.box(Vector3(0.18, 0.65, 0.22), Vector3(x, 0.36, 0.22), Color("314858")).reparent(opponent_keeper)
	opponent_hands = Node3D.new()
	add_child(opponent_hands)
	for x in [-0.20, 0.20]:
		yard.box(Vector3(0.23, 0.28, 0.13), Vector3(x, 0, 0), Color("e5aa69")).reparent(opponent_hands)
	aim_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.075
	sphere.height = 0.15
	aim_marker.mesh = sphere
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color("a2e1c1")
	aim_marker.material_override = marker_material
	add_child(aim_marker)
	trail = ImmediateMesh.new()
	var trail_instance := MeshInstance3D.new()
	trail_instance.mesh = trail
	var trail_material := StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.albedo_color = Color("e4b26e")
	trail_instance.material_override = trail_material
	add_child(trail_instance)
	sound = AudioStreamPlayer.new()
	sound.volume_db = -15.0
	add_child(sound)
	build_ui()
	reset_attempt()
	network = Node.new()
	network.set_script(SessionScript)
	network.name = "Session"
	add_child(network, true)

func label(text_value: String, size := 18) -> Label:
	var node := Label.new()
	node.text = text_value
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", Color("e8ede4"))
	return node

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.10, 0.13, 0.92)
	style.set_corner_radius_all(14)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

func button(text_value: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text_value
	node.focus_mode = Control.FOCUS_NONE
	node.custom_minimum_size = Vector2(130, 42)
	node.add_theme_font_size_override("font_size", 17)
	node.pressed.connect(action)
	return node

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	ui_root = root
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 22
	top.offset_top = 18
	top.offset_right = -22
	top.add_theme_stylebox_override("panel", panel_style())
	root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	titles.add_child(label("POCKETCHAOS  /  ДВОРОВЫЕ ПЕНАЛЬТИ", 13))
	header = label("", 25)
	titles.add_child(header)
	stats = label("", 15)
	titles.add_child(stats)
	shooter_button = button("Бьющий · 1", func(): set_mode(Mode.SHOOTER))
	keeper_button = button("Вратарь · 2", func(): set_mode(Mode.KEEPER))
	row.add_child(shooter_button)
	row.add_child(keeper_button)
	repeat_button = button("Повтор · R", reset_attempt)
	row.add_child(repeat_button)
	row.add_child(button("Онлайн", func(): network.show_room()))
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 22
	bottom.offset_right = -22
	bottom.offset_top = -128
	bottom.offset_bottom = -18
	bottom.add_theme_stylebox_override("panel", panel_style())
	root.add_child(bottom)
	var stack := VBoxContainer.new()
	bottom.add_child(stack)
	status = label("", 22)
	stack.add_child(status)
	detail = label("", 15)
	stack.add_child(detail)
	controls = label("", 15)
	stack.add_child(controls)
	power_bar = ProgressBar.new()
	power_bar.max_value = 1.0
	power_bar.show_percentage = false
	power_bar.custom_minimum_size = Vector2(0, 8)
	stack.add_child(power_bar)
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.offset_left = -260
	pause_panel.offset_right = 260
	pause_panel.offset_top = -130
	pause_panel.offset_bottom = 130
	pause_panel.add_theme_stylebox_override("panel", panel_style())
	root.add_child(pause_panel)
	var pause_stack := VBoxContainer.new()
	pause_stack.add_child(label("Пауза", 30))
	pause_note = label("Локальная тренировка", 18)
	pause_stack.add_child(pause_note)
	pause_stack.add_child(button("Продолжить · Esc", func(): set_paused(false)))
	pause_stack.add_child(button("Выход", func(): get_tree().quit()))
	pause_panel.add_child(pause_stack)
	pause_panel.hide()

func set_mode(value: Mode) -> void:
	if network != null and network.online:
		return
	mode = value
	reset_attempt()

func set_paused(value: bool) -> void:
	if value and network != null and network.online and network.local_shooter():
		network.send_command("cancel", {})
	paused = value
	charging = false
	power = 0.0
	pause_panel.visible = paused
	update_ui()

func reset_attempt(local_override := false) -> void:
	if not local_override and network != null and network.online:
		network.ready_or_rematch()
		return
	phase = Phase.READY
	charging = false
	power = 0.0
	spin = 0
	keeper_x = 0.0
	catch_remaining = 0.0
	catch_cooldown = 0.0
	dash_remaining = 0.0
	dash_direction = 0.0
	dash_used = false
	countdown = 0.0
	result_text = ""
	ball.reset_ball()
	trail_points.clear()
	trail.clear_surfaces()
	trail_clock = 0.0
	if mode == Mode.SHOOTER:
		camera.position = Vector3(0, 1.45, 13.7)
		camera.look_at(Vector3(0, 1.15, 0))
	else:
		camera.position = Vector3(0, 1.35, -0.7)
		camera.look_at(Vector3(0, 1.1, 10))
	gloves.visible = mode == Mode.KEEPER
	training_striker.visible = mode == Mode.KEEPER
	opponent_keeper.visible = false
	opponent_hands.visible = false
	update_pointer()
	update_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if network != null and network.room_panel.visible:
			network.room_panel.hide()
		else:
			set_paused(not paused)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if paused or (network != null and network.room_panel.visible):
		return
	if network != null and network.online:
		network.handle_input(event)
		update_ui()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: set_mode(Mode.SHOOTER)
			KEY_2: set_mode(Mode.KEEPER)
			KEY_R: reset_attempt()
			KEY_Q:
				if mode == Mode.SHOOTER and phase == Phase.READY:
					spin = maxi(-1, spin - 1)
			KEY_E:
				if mode == Mode.SHOOTER and phase == Phase.READY:
					spin = mini(1, spin + 1)
			KEY_SPACE:
				if mode == Mode.KEEPER and phase in [Phase.COUNTDOWN, Phase.FLIGHT] and not dash_used:
					var direction := movement_axis()
					if direction != 0.0:
						dash_direction = direction
						dash_remaining = Tuning.DASH_DURATION
						dash_used = true
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			charging = false
			power = 0.0
		if event.button_index == MOUSE_BUTTON_LEFT:
			if mode == Mode.SHOOTER and phase == Phase.READY:
				if event.pressed:
					charging = true
					power = 0.0
				elif charging:
					charging = false
					fire(aim, power, float(spin))
			elif mode == Mode.KEEPER and event.pressed:
				if phase == Phase.READY:
					phase = Phase.COUNTDOWN
					countdown = 2.0
				elif phase == Phase.FLIGHT and catch_cooldown <= 0.0:
					catch_remaining = Tuning.CATCH_DURATION
					catch_cooldown = Tuning.CATCH_COOLDOWN
	update_ui()

func movement_axis() -> float:
	return float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))

func update_pointer() -> void:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var target_z := 0.0 if mode == Mode.SHOOTER else Rules.CATCH_PLANE
	if absf(direction.z) < 0.00001:
		return
	var distance := (target_z - origin.z) / direction.z
	if distance <= 0.0:
		return
	var projected := origin + direction * distance
	if mode == Mode.SHOOTER:
		aim = Vector3(clampf(projected.x, -4.2, 4.2), clampf(projected.y, 0.25, 3.4), 0.0)
		aim_marker.position = aim
	else:
		hand_target = Vector3(clampf(projected.x, keeper_x - Tuning.HAND_REACH, keeper_x + Tuning.HAND_REACH), clampf(projected.y, 0.30, 2.30), Rules.CATCH_PLANE)
		gloves.position = hand_target
	aim_marker.visible = mode == Mode.SHOOTER and phase == Phase.READY

func fire(target: Vector3, strength: float, curve: float) -> void:
	phase = Phase.FLIGHT
	ball.launch(target, strength, curve)
	play_tone(140.0, 0.09)
	update_ui()

func launch_training_shot() -> void:
	var targets := [Vector3(0, 1.2, 0), Vector3(-1.8, 0.7, 0), Vector3(1.8, 1.9, 0), Vector3(-2.3, 1.8, 0), Vector3(2.1, 0.45, 0)]
	var target: Vector3 = targets[practice_index % targets.size()]
	practice_index += 1
	fire(target, 0.35, 0.0)

func _physics_process(delta: float) -> void:
	if network != null and network.online:
		network.tick(delta)
		return
	if paused or (network != null and network.room_panel.visible):
		return
	if charging:
		power = minf(1.0, power + delta / Tuning.CHARGE_TIME)
	catch_remaining = maxf(0.0, catch_remaining - delta)
	catch_cooldown = maxf(0.0, catch_cooldown - delta)
	if mode == Mode.KEEPER and phase != Phase.RESULT:
		var movement := movement_axis() * Tuning.KEEPER_SPEED
		if dash_remaining > 0.0:
			movement = dash_direction * Tuning.DASH_SPEED
			dash_remaining = maxf(0.0, dash_remaining - delta)
		# D means right on screen; the keeper faces +Z, hence world -X.
		keeper_x = clampf(keeper_x - movement * delta, -2.7, 2.7)
		camera.position.x = keeper_x
	update_pointer()
	if phase == Phase.COUNTDOWN:
		countdown -= delta
		if countdown <= 0.0:
			launch_training_shot()
	if phase == Phase.FLIGHT:
		step_flight(delta, mode == Mode.KEEPER)
	update_ui()

func step_flight(delta: float, keeper_enabled: bool) -> void:
	var previous: Vector3 = ball.step(delta)
	var outcome := Rules.attempt_result(previous, ball.position, hand_target, keeper_enabled and catch_remaining > 0.0)
	if outcome != "":
		finish_attempt(outcome)
	elif keeper_enabled:
		var t := Rules.plane_crossing(previous, ball.position, 0.22)
		if t >= 0.0:
			var hit := previous.lerp(ball.position, t)
			if absf(hit.x - keeper_x) < 0.38 + Rules.RADIUS and hit.y < 1.25:
				ball.position.z = 0.24
				ball.velocity.z = absf(ball.velocity.z) * 0.55
				ball.velocity.y += 1.0
				play_tone(95.0, 0.07)
	if phase == Phase.FLIGHT:
		if absf(ball.position.x) > 8.0 or ball.position.z < -2.0 or ball.position.z > 16.0 or ball.position.y > 8.0:
			finish_attempt("miss")
		elif ball.elapsed > Tuning.SHOT_TIMEOUT or (ball.elapsed > 1.0 and ball.velocity.length() < 0.3):
			finish_attempt("miss")
	record_trail(delta)

func record_trail(delta: float) -> void:
	trail_clock += delta
	if trail_clock >= 0.04:
		trail_clock = 0.0
		trail_points.append(ball.position)
		if trail_points.size() > 160:
			trail_points.pop_front()
		redraw_trail()

func finish_attempt(outcome: String) -> void:
	if network != null and network.online:
		network.finish_attempt(outcome)
		return
	if phase != Phase.FLIGHT:
		return
	phase = Phase.RESULT
	ball.live = false
	ball.velocity = Vector3.ZERO
	charging = false
	if mode == Mode.SHOOTER:
		shots_completed += 1
		if outcome == "goal":
			goals += 1
	else:
		keeper_completed += 1
		if outcome != "goal":
			saves += 1
	match outcome:
		"goal": result_text = "ГОЛ!" if mode == Mode.SHOOTER else "Пропущен гол"
		"save": result_text = "ПОЙМАЛ!"
		"miss": result_text = "Мимо ворот" if mode == Mode.SHOOTER else "Ворота защищены"
	play_tone(660.0 if outcome in ["goal", "save"] else 220.0, 0.18)
	update_ui()

func redraw_trail() -> void:
	trail.clear_surfaces()
	if trail_points.size() < 2:
		return
	trail.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in trail_points:
		trail.surface_add_vertex(point)
	trail.surface_end()

func update_ui() -> void:
	if header == null:
		return
	if network != null and network.online:
		network.draw_ui()
		return
	header.text = "Тренировка удара" if mode == Mode.SHOOTER else "Тренировка вратаря"
	stats.text = "Голы: %d / %d   ·   Защищённые попытки: %d / %d   ·   Тренировка 0.3" % [goals, shots_completed, saves, keeper_completed]
	repeat_button.text = "Повтор · R"
	repeat_button.disabled = false
	pause_note.text = "Локальная тренировка"
	shooter_button.disabled = mode == Mode.SHOOTER
	keeper_button.disabled = mode == Mode.KEEPER
	power_bar.visible = mode == Mode.SHOOTER
	power_bar.value = power
	if mode == Mode.SHOOTER:
		controls.text = "Мышь — прицел   ·   ЛКМ удержать и отпустить — удар   ·   Q / E — подкрутка   ·   ПКМ — отмена   ·   Esc — пауза"
		var curve_text := "без подкрутки"
		if spin < 0:
			curve_text = "подкрутка влево"
		elif spin > 0:
			curve_text = "подкрутка вправо"
		detail.text = "%s   ·   Сила: %d%%   ·   Зелёная точка — прицел до влияния подкрутки" % [curve_text, int(power * 100)]
	else:
		controls.text = "A / D — движение   ·   Мышь — руки   ·   ЛКМ — ловля   ·   Space + A / D — рывок   ·   Esc — пауза"
		detail.text = "Рывок: %s   ·   Ловля: %s   ·   Руки достают только рядом с телом" % ["использован" if dash_used else "готов", "активна" if catch_remaining > 0.0 else ("пауза" if catch_cooldown > 0.0 else "готова")]
	match phase:
		Phase.READY: status.text = "Выбери направление и силу" if mode == Mode.SHOOTER else "Нажми ЛКМ, чтобы начать попытку"
		Phase.COUNTDOWN: status.text = "Удар через %d…" % maxi(1, int(ceil(countdown)))
		Phase.FLIGHT: status.text = "Мяч в игре" if mode == Mode.SHOOTER else "Лови!"
		Phase.RESULT: status.text = result_text + "   ·   R — следующая попытка"

func play_tone(frequency: float, duration: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	sound.stop()
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 16000
	var count := int(duration * stream.mix_rate)
	var samples := PackedByteArray()
	samples.resize(count * 2)
	for i in range(count):
		var envelope := pow(1.0 - float(i) / count, 2.0)
		var wave := sin(TAU * frequency * float(i) / stream.mix_rate)
		samples.encode_s16(i * 2, int(wave * envelope * 9000))
	stream.data = samples
	sound.stream = stream
	sound.play()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_panel != null:
		set_paused(true)
