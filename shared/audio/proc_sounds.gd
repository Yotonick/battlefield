class_name ProcSounds
## Временные звуки, сгенерированные кодом (своих звуковых ассетов пока нет).
## В v0.2 заменим на настоящие записи из assets/ — см. ASSETS.md.

const MIX_RATE: int = 22050

static var _cache: Dictionary[StringName, AudioStreamWAV] = {}


static func get_sound(sound_name: StringName) -> AudioStreamWAV:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var stream: AudioStreamWAV
	match sound_name:
		&"shot":
			stream = _make(0.45, _shot_sample)
		&"shot_far":
			stream = _make(0.5, _shot_far_sample)
		&"click":
			stream = _make(0.04, _click_sample)
		&"mag":
			stream = _make(0.09, _mag_sample)
		&"hit":
			stream = _make(0.06, _hit_sample)
		&"headshot":
			stream = _make(0.09, _headshot_sample)
		&"impact":
			stream = _make(0.08, _impact_sample)
		_:
			stream = _make(0.01, _click_sample)
	_cache[sound_name] = stream
	return stream


static func _make(duration: float, sampler: Callable) -> AudioStreamWAV:
	var count: int = int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var state: Array[float] = [0.0, 0.0]
	for i: int in count:
		var t: float = float(i) / MIX_RATE
		var value: float = float(sampler.call(t, rng, state))
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Простой фильтр низких частот (state[0] — прошлое значение).
static func _lowpass(value: float, amount: float, state: Array[float], slot: int) -> float:
	state[slot] += (value - state[slot]) * amount
	return state[slot]


static func _shot_sample(t: float, rng: RandomNumberGenerator, state: Array[float]) -> float:
	var noise: float = rng.randf_range(-1.0, 1.0)
	var crack: float = noise * exp(-t * 45.0)
	var body: float = _lowpass(noise, 0.25, state, 0) * exp(-t * 9.0) * 1.6
	var thump: float = sin(TAU * 70.0 * t) * exp(-t * 22.0) * 0.8
	return (crack * 0.6 + body + thump) * 0.8


static func _shot_far_sample(t: float, rng: RandomNumberGenerator, state: Array[float]) -> float:
	var noise: float = rng.randf_range(-1.0, 1.0)
	var body: float = _lowpass(noise, 0.08, state, 0) * exp(-t * 6.0) * 3.0
	var thump: float = sin(TAU * 55.0 * t) * exp(-t * 12.0) * 0.6
	return (body + thump) * 0.7


static func _click_sample(t: float, rng: RandomNumberGenerator, _state: Array[float]) -> float:
	return rng.randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.6 + sin(TAU * 3200.0 * t) * exp(-t * 200.0) * 0.3


static func _mag_sample(t: float, rng: RandomNumberGenerator, state: Array[float]) -> float:
	var noise: float = _lowpass(rng.randf_range(-1.0, 1.0), 0.5, state, 0)
	return noise * exp(-t * 60.0) * 0.8 + sin(TAU * 900.0 * t) * exp(-t * 80.0) * 0.25


static func _hit_sample(t: float, _rng: RandomNumberGenerator, _state: Array[float]) -> float:
	return sin(TAU * 1500.0 * t) * exp(-t * 60.0) * 0.35


static func _headshot_sample(t: float, _rng: RandomNumberGenerator, _state: Array[float]) -> float:
	return (sin(TAU * 2300.0 * t) + sin(TAU * 3100.0 * t) * 0.5) * exp(-t * 40.0) * 0.3


static func _impact_sample(t: float, rng: RandomNumberGenerator, state: Array[float]) -> float:
	return _lowpass(rng.randf_range(-1.0, 1.0), 0.35, state, 0) * exp(-t * 55.0) * 0.7
