extends SceneTree

const Settings = preload("res://scripts/settings.gd")
const GameAudio = preload("res://scripts/audio.gd")
const Game = preload("res://scripts/game.gd")
var failures := 0
var checks := 0
var game: Node3D

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var defaults := Settings.defaults()
	check(defaults.volume == 0.7 and defaults.fullscreen == false and defaults.tutorial_seen == false, "Defaults are valid and complete")
	check(Settings.sanitize({}).volume == 0.7, "Missing keys fall back to defaults")
	check(Settings.sanitize({"volume": 2.0}).volume == 1.0, "Volume clamps from above")
	check(Settings.sanitize({"volume": -3.0}).volume == 0.0, "Volume clamps from below")
	check(Settings.sanitize({"volume": "loud"}).volume == 0.7, "Wrong volume type keeps the default")
	check(Settings.sanitize({"fullscreen": 1}).fullscreen == false, "Wrong flag type keeps the default")
	check(Settings.sanitize({"volume": 0.35, "fullscreen": true, "tutorial_seen": true}).tutorial_seen == true, "Valid values pass through")
	check(Settings.sanitize({"last_address": " 192.168.1.5 "}).last_address == "192.168.1.5", "Host address is trimmed and kept when valid")
	check(Settings.sanitize({"last_address": "not-an-ip"}).last_address == "127.0.0.1", "Invalid host address falls back to loopback")
	check(Settings.sanitize({"last_port": 70000}).last_port == 65535, "Host port clamps into the allowed range")
	check(Settings.sanitize({"last_port": "port"}).last_port == 24567, "Wrong host port type keeps the default")
	check(Settings.save_config({"volume": 0.35, "fullscreen": true, "tutorial_seen": true, "last_address": "192.168.9.9", "last_port": 24568}) == OK, "Settings file saves")
	var loaded := Settings.load_config()
	check(loaded.volume == 0.35 and loaded.fullscreen and loaded.tutorial_seen, "Settings round-trip preserves values")
	check(loaded.last_address == "192.168.9.9" and loaded.last_port == 24568, "Host address and port round-trip")
	Settings.apply_volume(0.5)
	check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01, "Volume maps to decibels on the master bus")
	Settings.apply_volume(0.0)
	check(AudioServer.is_bus_mute(0), "Zero volume mutes the bus")
	Settings.apply_volume(0.7)
	check(not AudioServer.is_bus_mute(0), "Positive volume unmutes the bus")
	Settings.apply_fullscreen(true)
	for name in ["kick", "body", "catch", "goal", "save", "miss", "whistle", "beep", "place"]:
		var stream: AudioStreamWAV = GameAudio.stream(name)
		check(stream != null and stream.data.size() > 0, "Sound '%s' generates samples" % name)
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == GameAudio.SAMPLE_RATE, "Sound '%s' uses the shared format" % name)
	check(GameAudio.stream("kick") == GameAudio.stream("kick"), "Streams are cached and reused")
	check(GameAudio.stream("goal").data.size() > GameAudio.stream("beep").data.size(), "Compound sound is longer than a single beep")
	check(GameAudio.outcome_sound("goal") == "goal" and GameAudio.outcome_sound("save") == "save" and GameAudio.outcome_sound("miss") == "miss", "Outcome mapping is complete")
	Settings.save_config({"volume": 0.7, "fullscreen": false, "tutorial_seen": false, "last_address": "192.168.9.9", "last_port": 24568})
	game = Node3D.new()
	game.set_script(Game)
	root.add_child(game)
	game.set_physics_process(false)
	await physics_frame
	await physics_frame
	check(game.network.address_field.text == "192.168.9.9" and int(game.network.port_field.value) == 24568, "Room form prefills the saved host address")
	check(game.tutorial.visible == true, "Fresh player sees the intro after launch")
	check(game.settings_panel != null and not game.settings_panel.visible, "Settings panel exists and starts hidden")
	game.tutorial.close()
	check(game.tutorial.visible == false and Settings.load_config().tutorial_seen == true, "Closing the intro persists the seen flag")
	game.tutorial.show_intro()
	check(game.tutorial.visible == true, "The intro can be replayed from settings")
	game.tutorial.close()
	game.change_volume(0.25)
	check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.25)) < 0.01, "Slider change applies volume immediately")
	check(absf(float(Settings.load_config().volume) - 0.25) < 0.001, "Slider change persists to the file")
	game.change_volume(0.7)
	print("Settings: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
