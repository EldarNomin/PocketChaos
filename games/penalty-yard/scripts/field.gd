extends Node3D
## Shared immutable field during shots; preview geometry never collides.
const FieldRules = preload("res://scripts/field_rules.gd")
const Style = preload("res://scripts/style.gd")
var game: Node3D
var layout := FieldRules.empty_layout()
var revision := -1
var objects: Node3D
var markers: Node3D
var preview: Node3D
var panel: Control
var practice_button: Button
var clear_button: Button
var headline: Label
var hint: Label
var orientation: Label
var slot_buttons: Array[Button] = []
var option_buttons: Array[Button] = []
var rotation_buttons: Array[Button] = []
var skip_button: Button
var practice := false
var kind := "shield"
var rotation_index := 2
var selected_slot := 0
var hovered_cell := -1
var preview_key := ""
var last_error := ""

func _ready() -> void:
	game = get_parent()
	objects = Node3D.new()
	add_child(objects)
	markers = Node3D.new()
	add_child(markers)
	for cell in range(15):
		var at := FieldRules.cell_position(cell)
		box(markers, Vector3(0.75,0.012,0.75), at + Vector3(0,0.016,0), Style.MARKER)
		var number := Label3D.new()
		number.text = str(cell + 1)
		number.font_size = 44
		number.pixel_size = 0.009
		number.position = at + Vector3(0,0.04,0)
		number.rotation_degrees.x = -90
		markers.add_child(number)
	markers.hide()
	build_ui()

func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if color.a < 1:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.set_meta("shield", true)
		var collision := CollisionShape3D.new()
		var collision_shape := BoxShape3D.new()
		collision_shape.size = size
		collision.shape = collision_shape
		body.add_child(collision)
		mesh.add_child(body)
	return mesh

func make_item(parent: Node3D, item: Dictionary, ghost := false) -> void:
	var item_root := Node3D.new()
	item_root.position = FieldRules.cell_position(int(item.cell))
	parent.add_child(item_root)
	var color := Style.HOST_ITEM if int(item.owner) == 0 else Style.GUEST_ITEM
	if ghost:
		color.a = 0.42
	if item.kind == "shield":
		item_root.rotation_degrees.y = FieldRules.ANGLES[int(item.rotation)]
		var shield := box(item_root, Vector3(1.25,1.4,0.16), Vector3(0,0.8,0), color, not ghost)
		shield.rotation_degrees.x = -12
		# Marks on both sides keep ownership visible from either role.
		for side in [-1,1]:
			box(shield, Vector3(0.12,1.2,0.012), Vector3(-0.4,0,side * 0.09), Color("f1e5c6"))
	else:
		var direction := -1.0 if item.kind == "fan_left" else 1.0
		box(item_root, Vector3(0.35,0.1,0.65), Vector3(-direction * 0.65,0.07,0), color)
		box(item_root, Vector3(0.12,0.7,0.12), Vector3(-direction * 0.65,0.4,0), color)
		box(item_root, Vector3(0.15,0.75,0.75), Vector3(-direction * 0.65,0.85,0), color)
		for blade in [-1,1]:
			box(item_root, Vector3(0.17,0.06,0.62), Vector3(-direction * 0.65,0.85,0), Color("e5ecdc")).rotation_degrees.x = blade * 45
		# Exact wind footprint and height are visible; the fan is not a blocker.
		box(item_root, Vector3(2,0.015,2), Vector3(0,0.025,0), Color(color.r,color.g,color.b,0.16))
		for x in [-1,1]:
			box(item_root, Vector3(0.025,2.5,0.025), Vector3(x,1.25,-1), Color(color.r,color.g,color.b,0.35))
		for z in [-0.6,0,0.6]:
			box(item_root, Vector3(1.2,0.02,0.04), Vector3(0,0.05,z), color)
			for side in [-1,1]:
				var tip := box(item_root, Vector3(0.3,0.02,0.04), Vector3(direction * 0.48,0.05,z + side * 0.09), color)
				tip.rotation_degrees.y = direction * side * 40

func apply_layout(data: Array, new_revision: int) -> void:
	if revision == new_revision:
		return
	layout = data.duplicate(true)
	revision = new_revision
	for child in objects.get_children():
		child.free()
	for item in layout:
		if not item.is_empty():
			make_item(objects, item)
	preview_key = ""

func clear() -> void:
	apply_layout(FieldRules.empty_layout(), revision + 1)
	practice = false
	hide_builder()

func wind_acceleration(point: Vector3) -> Vector3:
	return FieldRules.wind_acceleration(layout, point)

func build_ui() -> void:
	practice_button = game.button("Поле · B", toggle_practice)
	practice_button.position = Vector2(22,140)
	game.ui_root.add_child(practice_button)
	clear_button = game.button("Пустое поле",func(): clear(); game.reset_attempt())
	clear_button.position = Vector2(170,140)
	game.ui_root.add_child(clear_button)
	var background := PanelContainer.new()
	background.position = Vector2(22,145)
	background.custom_minimum_size = Vector2(300,0)
	background.add_theme_stylebox_override("panel", game.panel_style())
	game.ui_root.add_child(background)
	panel = background
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	background.add_child(stack)
	headline = game.label("Измени площадку",22)
	stack.add_child(headline)
	for option in FieldRules.KINDS:
		var option_kind: String = option
		var option_button: Button = game.button({"shield":"Щит для отскока","fan_left":"Ветер ←","fan_right":"Ветер →"}[option],func(): kind = option_kind; last_error = ""; preview_key = "")
		stack.add_child(option_button)
		option_buttons.append(option_button)
	var row := HBoxContainer.new()
	rotation_buttons.append(game.button("↶ · Q",func(): rotate_selection(-1)))
	rotation_buttons.append(game.button("↷ · E",func(): rotate_selection(1)))
	for rotation_button in rotation_buttons:
		row.add_child(rotation_button)
	stack.add_child(row)
	orientation = game.label("",16)
	stack.add_child(orientation)
	var slots := HBoxContainer.new()
	for i in range(2):
		var slot := i
		var slot_button: Button = game.button("Место %d" % (i+1),func(): selected_slot = slot; last_error = ""; preview_key = "")
		slots.add_child(slot_button)
		slot_buttons.append(slot_button)
	stack.add_child(slots)
	skip_button = game.button("Пропустить · R", skip_turn)
	stack.add_child(skip_button)
	hint = game.label("",15)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(260,48)
	stack.add_child(hint)
	panel.hide()

func editable() -> bool:
	return practice or (game.network != null and game.network.online and game.network.connected and game.network.state == game.network.State.BUILD and game.network.build_slot == game.network.local_slot())

func skip_turn() -> void:
	if not editable():
		return
	if practice:
		close_practice()
	else:
		game.network.send_command("skip", {})

func show_builder() -> void:
	game.charging = false
	game.camera.position = Vector3(0,13.5,10)
	game.camera.look_at(Vector3(0,0,5))
	game.gloves.hide()
	game.training_striker.hide()
	game.opponent_keeper.hide()
	game.opponent_hands.hide()
	game.aim_marker.hide()
	markers.show()
	panel.show()
	selected_slot = 0
	var owner: int = 0 if practice else game.network.local_slot()
	if not layout[owner*2].is_empty() and layout[owner*2+1].is_empty():
		selected_slot = 1
	last_error = ""
	preview_key = ""

func hide_builder() -> void:
	markers.hide()
	panel.hide()
	if preview != null:
		preview.free()
		preview = null
	preview_key = ""

func toggle_practice() -> void:
	if game.network != null and game.network.online:
		return
	if practice:
		close_practice()
	else:
		game.reset_attempt()
		practice = true
		show_builder()

func close_practice() -> void:
	practice = false
	hide_builder()
	game.reset_attempt()

func rotate_selection(change: int) -> void:
	rotation_index = posmod(rotation_index + change, FieldRules.ANGLES.size())
	last_error = ""
	preview_key = ""

func place_selected() -> void:
	if not editable() or hovered_cell < 0:
		return
	var owner: int = 0 if practice else game.network.local_slot()
	last_error = FieldRules.placement_error(layout,owner,selected_slot,kind,hovered_cell,rotation_index)
	if last_error != "":
		return
	if practice:
		var updated := layout.duplicate(true)
		updated[selected_slot] = {"owner":0,"kind":kind,"cell":hovered_cell,"rotation":rotation_index}
		apply_layout(updated,revision+1)
		close_practice()
	else:
		game.network.send_command("place",{"slot":selected_slot,"kind":kind,"cell":hovered_cell,"rotation":rotation_index})

func handle_input(event: InputEvent) -> void:
	if not editable():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: rotate_selection(-1)
			KEY_E: rotate_selection(1)
			KEY_1: selected_slot = 0; preview_key = ""
			KEY_2: selected_slot = 1; preview_key = ""
			KEY_R:
				if practice: close_practice()
				else: game.network.send_command("skip",{})
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		update_hover()
		place_selected()

func update_hover() -> void:
	hovered_cell = -1
	var mouse := game.get_viewport().get_mouse_position()
	var origin: Vector3 = game.camera.project_ray_origin(mouse)
	var ray: Vector3 = game.camera.project_ray_normal(mouse)
	if ray.y < -0.001:
		var hit := origin - ray * origin.y / ray.y
		var closest := 0.85
		for cell in range(15):
			var distance := hit.distance_to(FieldRules.cell_position(cell))
			if distance < closest:
				closest = distance
				hovered_cell = cell

func tick() -> void:
	practice_button.visible = not practice and (game.network == null or not game.network.online) and not game.paused and (game.network == null or not game.network.room_panel.visible) and not game.overlay_open()
	clear_button.visible = practice_button.visible and layout != FieldRules.empty_layout()
	if practice:
		game.shooter_button.disabled = true
		game.keeper_button.disabled = true
		game.repeat_button.disabled = true
		game.header.text = "Поле для тренировки"
		game.status.text = "Выбери предмет и место"
		game.detail.text = "Установи предмет, затем попробуй удар или ловлю."
		game.controls.text = "ЛКМ — поставить   ·   Q / E — угол   ·   1 / 2 — своё место   ·   B / R — вернуться"
		game.power_bar.hide()
	if not panel.visible:
		return
	var can_edit: bool = editable() and not game.paused and not game.network.room_panel.visible
	headline.text = "Твой ход" if can_edit else "Друг меняет поле"
	orientation.text = "Угол щита: %s°" % str(FieldRules.ANGLES[rotation_index]) if kind == "shield" else "Видимая зона ветра: 2 × 2 м"
	for i in range(option_buttons.size()):
		option_buttons[i].disabled = not can_edit or FieldRules.KINDS[i] == kind
	for rotation_button in rotation_buttons:
		rotation_button.disabled = not can_edit or kind != "shield"
	skip_button.disabled = not can_edit
	var owner: int = 0 if practice else game.network.local_slot()
	for i in range(2):
		slot_buttons[i].disabled = not can_edit or i == selected_slot
		slot_buttons[i].text = ("Заменить %d" if not layout[owner*2+i].is_empty() else "Место %d") % (i+1)
	hint.text = last_error if last_error != "" else ("Кликни по площадке. Предмет останется для обоих ударов." if can_edit else "Следующий ход будет твоим. Условия ударов одинаковые.")
	if not can_edit:
		if preview != null: preview.hide()
		return
	var previous_hover := hovered_cell
	update_hover()
	if hovered_cell != previous_hover:
		last_error = ""
	var error := FieldRules.placement_error(layout,owner,selected_slot,kind,hovered_cell,rotation_index) if hovered_cell >= 0 else ""
	if error != "": hint.text = error
	var key := "%s:%d:%d:%d" % [kind,rotation_index,hovered_cell,selected_slot]
	if key == preview_key:
		return
	preview_key = key
	if preview != null: preview.free()
	preview = Node3D.new()
	add_child(preview)
	if hovered_cell >= 0:
		make_item(preview,{"owner":owner,"kind":kind,"cell":hovered_cell,"rotation":rotation_index},true)
		box(preview,Vector3(1.0,0.018,1.0),FieldRules.cell_position(hovered_cell)+Vector3(0,0.035,0),Color(0.3,0.85,0.6,0.65) if error == "" else Color(0.9,0.25,0.2,0.65))
		if error != "": hint.text = error
