extends RefCounted
## Persisted player settings: volume, display mode and the seen intro.

const PATH := "user://settings.cfg"
const SECTION := "game"
const KEYS := ["volume", "fullscreen", "tutorial_seen", "last_address", "last_port"]

static func defaults() -> Dictionary:
	return {"volume": 0.7, "fullscreen": false, "tutorial_seen": false, "last_address": "127.0.0.1", "last_port": 24567}

static func sanitize(data: Dictionary) -> Dictionary:
	var result := defaults()
	if data.has("volume") and (data.volume is float or data.volume is int) and is_finite(float(data.volume)):
		result.volume = clampf(float(data.volume), 0.0, 1.0)
	if data.has("fullscreen") and data.fullscreen is bool:
		result.fullscreen = data.fullscreen
	if data.has("tutorial_seen") and data.tutorial_seen is bool:
		result.tutorial_seen = data.tutorial_seen
	if data.has("last_address"):
		var address := str(data.last_address).strip_edges()
		if address.is_valid_ip_address():
			result.last_address = address
	if data.has("last_port") and (data.last_port is float or data.last_port is int) and is_finite(float(data.last_port)):
		result.last_port = clampi(int(float(data.last_port)), 1024, 65535)
	return result

static func load_config() -> Dictionary:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return defaults()
	var data := {}
	for key in KEYS:
		if file.has_section_key(SECTION, key):
			data[key] = file.get_value(SECTION, key)
	return sanitize(data)

static func save_config(data: Dictionary) -> Error:
	var file := ConfigFile.new()
	var clean := sanitize(data)
	for key in KEYS:
		file.set_value(SECTION, key, clean[key])
	return file.save(PATH)

static func apply_volume(linear: float) -> void:
	var index := AudioServer.get_bus_index("Master")
	if index < 0:
		return
	if linear <= 0.001:
		AudioServer.set_bus_mute(index, true)
		AudioServer.set_bus_volume_db(index, -60.0)
	else:
		AudioServer.set_bus_mute(index, false)
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0, 1.0)))

static func apply_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
