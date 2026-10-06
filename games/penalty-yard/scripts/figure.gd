extends Node3D
## Stylised box humanoid shared by the striker avatar and the goalkeeper.
## Feet stand on y = 0; the figure faces local -Z.

const Style = preload("res://scripts/style.gd")

var jersey: Color = Style.STRIKER_JERSEY
var shorts_color: Color = Style.SHORTS
var skin: Color = Style.SKIN
var hair_color: Color = Color("3a2e26")
var shirt_number := ""
var arm_pivots: Array[Node3D] = []
var idle_clock := 0.0
var base_y := 0.0

func _part(size: Vector3, at: Vector3, color: Color, parent: Node = self) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _ready() -> void:
	base_y = position.y
	# Legs: skin, sock in team colour, dark boot.
	for side: float in [-1.0, 1.0]:
		var x := side * 0.11
		_part(Vector3(0.16, 0.42, 0.18), Vector3(x, 0.60, -0.02), skin)
		_part(Vector3(0.17, 0.26, 0.19), Vector3(x, 0.25, -0.02), shorts_color)
		_part(Vector3(0.19, 0.11, 0.30), Vector3(x, 0.055, 0.02), Color("232a2e"))
	_part(Vector3(0.38, 0.26, 0.25), Vector3(0, 0.86, 0), shorts_color)
	_part(Vector3(0.44, 0.56, 0.25), Vector3(0, 1.26, 0), jersey)
	# Arms hang from shoulder pivots so they can be aimed at the gloves.
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.28, 1.47, 0)
		add_child(pivot)
		_part(Vector3(0.14, 0.16, 0.16), Vector3(0, 0, -0.08), jersey, pivot)
		_part(Vector3(0.11, 0.12, 0.30), Vector3(0, 0, -0.30), skin, pivot)
		pivot.rotation_degrees = Vector3(-72, 0, side * -14)
		arm_pivots.append(pivot)
	_part(Vector3(0.27, 0.28, 0.27), Vector3(0, 1.70, 0), skin)
	_part(Vector3(0.29, 0.10, 0.29), Vector3(0, 1.875, 0), hair_color)
	_part(Vector3(0.29, 0.22, 0.08), Vector3(0, 1.75, 0.115), hair_color)
	# Face on the -Z side the figure looks toward.
	for side in [-1.0, 1.0]:
		_part(Vector3(0.04, 0.05, 0.02), Vector3(side * 0.06, 1.72, -0.14), Color("232a2e"))
	if shirt_number != "":
		var number := Label3D.new()
		number.text = shirt_number
		number.font_size = 160
		number.pixel_size = 0.0016
		number.modulate = Color("f4efe2")
		number.position = Vector3(0, 1.30, 0.135)
		number.rotation_degrees.y = 180
		add_child(number)

func _process(delta: float) -> void:
	idle_clock += delta
	position.y = base_y + 0.01 * sin(idle_clock * 2.2)

func aim_arms(left_target: Vector3, right_target: Vector3) -> void:
	if not is_inside_tree():
		return
	for i in range(2):
		var target := left_target if i == 0 else right_target
		var pivot := arm_pivots[i]
		if pivot.global_position.distance_to(target) < 0.01:
			continue
		pivot.look_at(target, Vector3.UP)
		var reach := pivot.global_position.distance_to(target) / 0.52
		pivot.scale = Vector3(1, 1, clampf(reach, 0.55, 1.7))
