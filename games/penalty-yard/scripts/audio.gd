extends RefCounted
## Synthesised feedback sounds. Generated WAV data, no external assets.

const SAMPLE_RATE := 16000
static var cache := {}

static func tone_samples(frequency: float, duration: float, gain: float, decay := 2.0, vibrato := 0.0, vibrato_rate := 36.0) -> PackedFloat32Array:
	var count := maxi(1, int(duration * SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var time := float(i) / SAMPLE_RATE
		phase += TAU * (frequency + vibrato * sin(TAU * vibrato_rate * time)) / SAMPLE_RATE
		samples[i] = sin(phase) * pow(1.0 - float(i) / count, decay) * gain
	return samples

static func sweep_samples(from_hz: float, to_hz: float, duration: float, gain: float, decay := 2.0) -> PackedFloat32Array:
	var count := maxi(1, int(duration * SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		phase += TAU * lerpf(from_hz, to_hz, float(i) / count) / SAMPLE_RATE
		samples[i] = sin(phase) * pow(1.0 - float(i) / count, decay) * gain
	return samples

static func noise_samples(duration: float, gain: float) -> PackedFloat32Array:
	var count := maxi(1, int(duration * SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		# Deterministic pseudo-random keeps replays and tests identical.
		var raw := sin(float(i) * 12.9898) * 43758.5453
		samples[i] = (raw - floor(raw)) * 2.0 - 1.0
	return samples

static func join(parts: Array) -> PackedFloat32Array:
	var joined := PackedFloat32Array()
	for part in parts:
		joined.append_array(part)
	return joined

static func _pack(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = bytes
	return stream

static func _build(name: String) -> AudioStreamWAV:
	match name:
		"kick": return _pack(sweep_samples(175.0, 62.0, 0.15, 0.85, 2.6))
		"body": return _pack(tone_samples(115.0, 0.09, 0.5, 2.4))
		"catch": return _pack(join([noise_samples(0.07, 0.55), tone_samples(540.0, 0.08, 0.4, 2.2)]))
		"goal": return _pack(join([tone_samples(523.0, 0.12, 0.55, 1.6), tone_samples(784.0, 0.24, 0.6, 1.8)]))
		"save": return _pack(sweep_samples(680.0, 1060.0, 0.17, 0.5, 1.6))
		"miss": return _pack(sweep_samples(300.0, 150.0, 0.3, 0.45, 1.4))
		"whistle": return _pack(tone_samples(2350.0, 0.45, 0.24, 0.5, 130.0, 41.0))
		"beep": return _pack(tone_samples(880.0, 0.07, 0.32, 2.5))
		"place": return _pack(join([noise_samples(0.03, 0.5), tone_samples(710.0, 0.05, 0.35, 2.5)]))
	return _pack(tone_samples(440.0, 0.1, 0.4))

static func stream(name: String) -> AudioStreamWAV:
	if not cache.has(name):
		cache[name] = _build(name)
	return cache[name]

static func outcome_sound(outcome: String) -> String:
	return "goal" if outcome == "goal" else ("save" if outcome == "save" else "miss")
