extends "res://scripts/game.gd"
## Stable hand/aim inputs for headless network tests; no production test switches.
const DelayedSession = preload("res://tests/delayed_session.gd")
var delay_network := false
var test_hands := Vector3(0, 1.2, 0.6)

func _ready() -> void:
	super._ready()
	if delay_network:
		var previous := network
		previous.room_panel.queue_free()
		remove_child(previous)
		previous.free()
		network = Node.new()
		network.name = "Session"
		network.set_script(DelayedSession)
		add_child(network, true)

func update_pointer() -> void:
	if aim_marker != null:
		aim_marker.position = aim
		hand_target = Vector3(keeper_x, 0, 0) + test_hands
		gloves.position = hand_target
