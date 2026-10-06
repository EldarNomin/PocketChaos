extends Node3D

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	return result

func box(size: Vector3, at: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = size
	mesh.mesh = geometry
	mesh.material_override = material(color)
	mesh.position = at
	add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		mesh.add_child(body)
	return mesh

func _ready() -> void:
	box(Vector3(17, 0.2, 22), Vector3(0, -0.1, 5), Color("315653"), true)
	box(Vector3(0.14, 2.64, 0.14), Vector3(-3.07, 1.25, 0), Color("efe8d7"), true)
	box(Vector3(0.14, 2.64, 0.14), Vector3(3.07, 1.25, 0), Color("efe8d7"), true)
	box(Vector3(6.28, 0.14, 0.14), Vector3(0, 2.57, 0), Color("efe8d7"), true)
	var chalk := Color("b1d0b4")
	for x in [-5.0, 5.0]:
		box(Vector3(0.045, 0.01, 15), Vector3(x, 0.008, 6), chalk)
	box(Vector3(10, 0.01, 0.045), Vector3(0, 0.009, 0), chalk)
	box(Vector3(10, 0.01, 0.045), Vector3(0, 0.009, 12), chalk)
	box(Vector3(0.6, 0.01, 0.045), Vector3(0, 0.012, 10), chalk)
	# Goal net: visual only, so result is decided by crossing the mouth.
	for i in range(13):
		box(Vector3(0.016, 2.5, 0.016), Vector3(-3.0 + i * 0.5, 1.25, -1.35), Color("698782"))
	for i in range(6):
		box(Vector3(6, 0.016, 0.016), Vector3(0, i * 0.5, -1.35), Color("698782"))
	for x in [-3.0, 3.0]:
		for i in range(6):
			box(Vector3(0.016, 0.016, 1.35), Vector3(x, i * 0.5, -0.675), Color("698782"))
	# Fences and buildings remain decorative in this training build.
	for x in [-7.0, 7.0]:
		for z in range(-3, 15, 2):
			box(Vector3(0.07, 2.2, 0.07), Vector3(x, 1.1, z), Color("526965"))
		for height in [0.4, 1.2, 2.0]:
			box(Vector3(0.04, 0.04, 18), Vector3(x, height, 5), Color("526965"))
	for i in range(7):
		var x := -15.0 + i * 5.0
		var height := 4.0 + (i % 3) * 2.0
		box(Vector3(4.4, height, 3), Vector3(x, height / 2.0, -7), Color("34484d"))
		for floor_index in range(int(height / 1.3)):
			for window_index in range(3):
				box(Vector3(0.45, 0.6, 0.02), Vector3(x - 1.3 + window_index * 1.3, 0.8 + floor_index * 1.3, -5.48), Color("cfab71"))
	box(Vector3(2.2, 0.15, 0.65), Vector3(-6, 0.65, 6), Color("b48056"))
	for z in [5.75, 6.25]:
		box(Vector3(1.8, 0.6, 0.07), Vector3(-6, 0.3, z), Color("526965"))
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("14212e")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("bed7d8")
	settings.ambient_light_energy = 0.75
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_color = Color("ffd6a2")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

