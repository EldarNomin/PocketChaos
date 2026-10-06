extends RefCounted
## Fixed placements, ownership and conservative clear shooting corridors.
const Rules = preload("res://scripts/rules.gd")
const ANGLES := [-45.0, -22.5, 0.0, 22.5, 45.0]
const KINDS := ["shield", "fan_left", "fan_right"]
const WIND_ACCELERATION := 9.0
const MIN_SPACING := 1.8

static func empty_layout() -> Array:
	return [{}, {}, {}, {}]

static func cell_position(cell: int) -> Vector3:
	return Vector3(-3.0 + (cell % 5) * 1.5, 0, 3.0 + int(cell / 5) * 2.0)

static func corridor_blocked(target_x: float, item: Dictionary) -> bool:
	if item.is_empty() or item.kind != "shield":
		return false
	var centre := cell_position(int(item.cell))
	var angle := deg_to_rad(float(ANGLES[int(item.rotation)]))
	var from := Vector2(Rules.SHOT_ORIGIN.x - centre.x, Rules.SHOT_ORIGIN.z - centre.z).rotated(angle)
	var to := Vector2(target_x - centre.x, -centre.z).rotated(angle)
	# Tilted shield footprint plus a ball radius and small clearance.
	var half := Vector2(0.625 + Rules.RADIUS + 0.05, 0.30 + Rules.RADIUS + 0.05)
	var direction := to - from
	var start := 0.0
	var end := 1.0
	for axis in range(2):
		if absf(direction[axis]) < 0.00001:
			if absf(from[axis]) > half[axis]:
				return false
		else:
			var a := (-half[axis] - from[axis]) / direction[axis]
			var b := (half[axis] - from[axis]) / direction[axis]
			start = maxf(start, minf(a, b))
			end = minf(end, maxf(a, b))
			if start > end:
				return false
	return true

static func has_clear_corridor(layout: Array) -> bool:
	for target in [-2.4, -1.8, -1.2, -0.6, 0.0, 0.6, 1.2, 1.8, 2.4]:
		var clear := true
		for item in layout:
			if corridor_blocked(target, item):
				clear = false
				break
		if clear:
			return true
	return false

static func placement_error(layout: Array, owner: int, slot: int, kind: String, cell: int, rotation: int) -> String:
	if layout.size() != 4 or owner not in [0,1] or slot not in [0,1] or kind not in KINDS or cell < 0 or cell >= 15 or rotation < 0 or rotation >= ANGLES.size():
		return "Некорректный предмет или место."
	var index := owner * 2 + slot
	var candidate := layout.duplicate(true)
	candidate[index] = {"owner": owner, "kind": kind, "cell": cell, "rotation": rotation}
	for i in range(4):
		if i != index and not candidate[i].is_empty() and cell_position(cell).distance_to(cell_position(int(candidate[i].cell))) < MIN_SPACING:
			return "Слишком близко к другому предмету. Выбери другое место."
	if not has_clear_corridor(candidate):
		return "Щиты закрывают все прямые коридоры. Оставь путь к воротам."
	return ""

static func wind_acceleration(layout: Array, point: Vector3) -> Vector3:
	var force := 0.0
	for item in layout:
		if item.is_empty() or item.kind == "shield":
			continue
		var offset := point - cell_position(int(item.cell))
		if absf(offset.x) <= 1.0 and absf(offset.z) <= 1.0 and point.y >= 0.0 and point.y <= 2.5:
			force += WIND_ACCELERATION * (-1.0 if item.kind == "fan_left" else 1.0)
	return Vector3(clampf(force, -WIND_ACCELERATION * 2, WIND_ACCELERATION * 2), 0, 0)
