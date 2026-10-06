extends CharacterBody3D
## Fixed-step swept collisions. One host will run this in stage 3.

const Rules = preload("res://scripts/rules.gd")
const Tuning = preload("res://scripts/tuning.gd")
var live := false
var curve := 0.0
var elapsed := 0.0
var travelled := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = Rules.RADIUS
	shape.shape = sphere
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = Rules.RADIUS
	sphere_mesh.height = Rules.RADIUS * 2.0
	mesh.mesh = sphere_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f4e8d0")
	material.roughness = 0.7
	mesh.material_override = material
	add_child(mesh)
	# Simple coloured seams make the ball visible without imported assets.
	for axis in [Vector3.RIGHT, Vector3.FORWARD]:
		var seam := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = Rules.RADIUS - 0.009
		torus.outer_radius = Rules.RADIUS + 0.003
		seam.mesh = torus
		seam.rotation = axis * PI / 2.0
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color("354747")
		seam.material_override = dark
		mesh.add_child(seam)

func reset_ball() -> void:
	position = Rules.SHOT_ORIGIN
	velocity = Vector3.ZERO
	curve = 0.0
	elapsed = 0.0
	travelled = 0.0
	live = false

func launch(target: Vector3, power: float, spin: float) -> void:
	velocity = Rules.launch_velocity(target, power)
	curve = spin
	elapsed = 0.0
	live = true

func step(delta: float, external_acceleration := Vector3.ZERO) -> Vector3:
	var previous := position
	if not live:
		return previous
	elapsed += delta
	velocity.y -= Tuning.GRAVITY * delta
	velocity.x += curve * Tuning.CURVE_ACCELERATION * delta
	velocity += external_acceleration * delta
	var motion := velocity * delta
	# Consume remaining travel after a bounce, including at high speed.
	for iteration in range(4):
		var collision := move_and_collide(motion)
		if collision == null:
			break
		var normal := collision.get_normal()
		var restitution := Tuning.GROUND_RESTITUTION if normal.y > 0.7 else Tuning.FRAME_RESTITUTION
		if collision.get_collider().has_meta("shield"):
			restitution = Tuning.SHIELD_RESTITUTION
		velocity = velocity.bounce(normal) * restitution
		motion = collision.get_remainder().bounce(normal) * restitution
		if normal.y > 0.7:
			velocity.x *= 0.94
			velocity.z *= 0.94
			if absf(velocity.y) < 0.3:
				velocity.y = 0.0
		if motion.length_squared() < 0.000001:
			break
	travelled += previous.distance_to(position)
	return previous
