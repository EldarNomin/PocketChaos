extends SceneTree
## Developer tool: renders striker, keeper and build views to .shots/ PNGs.
## Run without --headless: godot --path . --script tests/render_snapshot.gd

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = load("res://main.tscn").instantiate()
	root.add_child(game)
	if game.tutorial.visible:
		game.tutorial.close()
	var directory := ProjectSettings.globalize_path("res://.shots")
	DirAccess.make_dir_recursive_absolute(directory)
	for i in range(20):
		await process_frame
	await _shot(directory + "/view_striker.png")
	game.set_mode(game.Mode.KEEPER)
	for i in range(10):
		await process_frame
	await _shot(directory + "/view_keeper.png")
	game.set_mode(game.Mode.SHOOTER)
	game.field.toggle_practice()
	for i in range(10):
		await process_frame
	await _shot(directory + "/view_build.png")
	print("Shots written to %s" % directory)
	game.queue_free()
	await process_frame
	quit(0)

func _shot(path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("shot: ", path)
