extends "res://scripts/session.gd"
## Adds 120 ms to inbound state and outbound commands, on actual ENet peers.

func _apply_state(data: Dictionary) -> void:
	await get_tree().create_timer(0.12).timeout
	if is_inside_tree():
		super._apply_state(data)

func send_command(operation: String, data: Dictionary) -> void:
	if not online or not connected:
		return
	var nonce := attempt_id
	await get_tree().create_timer(0.12).timeout
	if online and connected:
		if host:
			_accept_command(1, nonce, operation, data)
		else:
			_command.rpc_id(1, nonce, operation, data)

