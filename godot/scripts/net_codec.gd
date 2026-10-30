extends RefCounted
## LAN games: the states net.gd sends many times a second, in bytes instead of Godot's Variant arrays: a vehicle in 27
## bytes (184 as an array), a player in 15 (60). Decoded they are the arrays car.gd net_state and game.gd
## net_player_state make, so nothing past net.gd sees the difference.
## An entry starts with its size in a byte, so a server can pass entries on without reading them all and a reader can
## skip those it can't place. Position: 3 x 24 bits at 1/256 m (+-32 km); rotation: the smallest three components of the
## quaternion at 12 bits each (about 0.02 degree). What only some vehicles send (a plane's surfaces...) stays a Variant.

const POS_SCALE := 256.0
const POS_MAX := 8388607
const ROT_RANGE := 0.70710679                   # the smallest three of a unit quaternion are within +-sqrt(1/2)
const ROT_MAX := 4095.0
const STEER_SCALE := 100.0                      # steering and pedal in a byte: +-1.27
const YAW_SCALE := 10430.0                      # radians in 16 bits
const POSE_SIZE := 14
const CAR_TRAILER := 1                          # car entry: has a rear section's pose
const CAR_EXTRAS := 2                           # car entry: has more fields after those of car.gd
const CAR_BASE := 7                             # fields of car.gd net_state
const CAR_MIN := 27                             # bytes, without the trailer and the extras
const PLAYER_BASE := 5                          # fields of game.gd net_player_state, without the gunner's
const PLAYER_MIN := 15
const TRAIN_MIN := 17


## The bytes of vehicle `net_id`'s state.
static func car(net_id: String, s: Array) -> PackedByteArray:
	var trailer: Transform3D = s[1]
	var has_trailer := trailer != Transform3D.IDENTITY
	var extras := var_to_bytes(s.slice(CAR_BASE)) if s.size() > CAR_BASE else PackedByteArray()
	var b := PackedByteArray()
	b.resize(CAR_MIN + (POSE_SIZE if has_trailer else 0) + extras.size())
	b[0] = b.size()
	b.encode_u32(1, net_id.hash())
	b[5] = (CAR_TRAILER if has_trailer else 0) | (CAR_EXTRAS if not extras.is_empty() else 0)
	_put_pose(b, 6, s[0])
	b.encode_s8(20, clampi(roundi(s[2] * STEER_SCALE), -127, 127))
	b.encode_s8(21, clampi(roundi(s[3] * STEER_SCALE), -127, 127))
	b.encode_u16(22, s[4])
	b.encode_s8(24, s[5])
	b.encode_half(25, s[6])
	var at := CAR_MIN
	if has_trailer:
		_put_pose(b, at, trailer)
		at += POSE_SIZE
	for i in extras.size():
		b[at + i] = extras[i]
	return b


## The id of the vehicle of the entry at `at` (String.hash of its net id).
static func car_id(data: PackedByteArray, at: int) -> int:
	return data.decode_u32(at + 1)


## Whether a whole entry of at least `least` bytes is there at `at` (the bytes came from the network).
static func fits(data: PackedByteArray, at: int, least: int) -> bool:
	return at < data.size() and data[at] >= least and at + data[at] <= data.size()


## The state in the vehicle entry at `at`, as car.gd net_state makes it.
static func read_car(data: PackedByteArray, at: int) -> Array:
	var head := data[at + 5]
	var s := [_get_pose(data, at + 6), Transform3D(), data.decode_s8(at + 20) / STEER_SCALE,
			data.decode_s8(at + 21) / STEER_SCALE, data.decode_u16(at + 22), data.decode_s8(at + 24),
			data.decode_half(at + 25)]
	var next := at + CAR_MIN
	if head & CAR_TRAILER:
		s[1] = _get_pose(data, next)
		next += POSE_SIZE
	if head & CAR_EXTRAS:
		var extras: Variant = bytes_to_var(data.slice(next, at + data[at]))
		if extras is Array:
			s.append_array(extras)
	return s


## The bytes of a player's state: [vehicle or train id or "", section, position, yaw, flags, gunner's fields...].
static func player(s: Array) -> PackedByteArray:
	var id: PackedByteArray = String(s[0]).to_utf8_buffer()
	var extras := var_to_bytes(s.slice(PLAYER_BASE)) if s.size() > PLAYER_BASE else PackedByteArray()
	var b := PackedByteArray()
	b.resize(PLAYER_MIN + id.size() + extras.size())
	b[1] = id.size()
	var at := 2
	for i in id.size():
		b[at + i] = id[i]
	at += id.size()
	b[at] = s[1]
	_put_position(b, at + 1, s[2])
	b.encode_s16(at + 10, roundi(wrapf(s[3], -PI, PI) * YAW_SCALE))
	b[at + 12] = s[4]
	at += 13
	for i in extras.size():
		b[at + i] = extras[i]
	b[0] = b.size()
	return b


## The state in the player entry at `at`.
static func read_player(data: PackedByteArray, at: int) -> Array:
	var size := data[at]
	var length := data[at + 1]
	if size < PLAYER_MIN + length:
		return []
	var next := at + 2 + length
	var s: Array = [data.slice(at + 2, next).get_string_from_utf8(), data[next], _get_position(data, next + 1),
			data.decode_s16(next + 10) / YAW_SCALE, data[next + 12]]
	if at + size > next + 13:
		var extras: Variant = bytes_to_var(data.slice(next + 13, at + size))
		if extras is Array:
			s.append_array(extras)
	return s


## The bytes of a train's state: its net id, its service, then train.gd net_state.
static func train(net_id: String, service: int, s: Array) -> PackedByteArray:
	var id: PackedByteArray = net_id.to_utf8_buffer()
	var b := PackedByteArray()
	b.resize(TRAIN_MIN + id.size())
	b[0] = b.size()
	b[1] = id.size()
	for i in id.size():
		b[2 + i] = id[i]
	var at := 2 + id.size()
	b.encode_u16(at, service)
	b.encode_float(at + 2, s[0])
	b.encode_float(at + 6, s[1])
	b[at + 10] = s[2]
	b[at + 11] = roundi(clampf(s[3], 0.0, 1.0) * 200.0)
	b[at + 12] = s[4]
	b.encode_s8(at + 13, clampi(roundi(s[5] * 100.0), -127, 127))
	b.encode_s8(at + 14, clampi(roundi(s[6] * 100.0), -127, 127))
	return b


## [net id, service, train.gd net_state] of the train entry at `at`, [] if it isn't whole.
static func read_train(data: PackedByteArray, at: int) -> Array:
	var length := data[at + 1]
	if data[at] != TRAIN_MIN + length:
		return []
	var next := at + 2 + length
	return [data.slice(at + 2, next).get_string_from_utf8(), data.decode_u16(next), [data.decode_float(next + 2),
			data.decode_float(next + 6), data[next + 10], data[next + 11] / 200.0, data[next + 12],
			data.decode_s8(next + 13) / 100.0, data.decode_s8(next + 14) / 100.0]]


## (Each 24 bits written as 32, the next one over its top byte.)
static func _put_position(b: PackedByteArray, at: int, p: Vector3) -> void:
	b.encode_s32(at, clampi(roundi(p.x * POS_SCALE), -POS_MAX, POS_MAX))
	b.encode_s32(at + 3, clampi(roundi(p.y * POS_SCALE), -POS_MAX, POS_MAX))
	var z := clampi(roundi(p.z * POS_SCALE), -POS_MAX, POS_MAX)
	b.encode_u16(at + 6, z & 0xffff)
	b[at + 8] = (z >> 16) & 0xff


static func _get_position(b: PackedByteArray, at: int) -> Vector3:
	return Vector3(_s24(b, at), _s24(b, at + 3), _s24(b, at + 6)) / POS_SCALE


static func _s24(b: PackedByteArray, at: int) -> int:
	var v: int = b[at] | (b[at + 1] << 8) | (b[at + 2] << 16)
	return v - 0x1000000 if v >= 0x800000 else v


static func _put_pose(b: PackedByteArray, at: int, xf: Transform3D) -> void:
	_put_position(b, at, xf.origin)
	var q: Quaternion = xf.basis.get_rotation_quaternion()
	var c := [q.x, q.y, q.z, q.w]
	var big := 0
	for i in range(1, 4):
		if absf(c[i]) > absf(c[big]):
			big = i
	var sign_of := -1.0 if c[big] < 0.0 else 1.0
	var bits := big
	var shift := 2
	for i in 4:
		if i != big:
			var v := clampf(c[i] * sign_of / ROT_RANGE * 0.5 + 0.5, 0.0, 1.0)
			bits |= roundi(v * ROT_MAX) << shift
			shift += 12
	b.encode_u32(at + 9, bits & 0xffffffff)
	b[at + 13] = (bits >> 32) & 0xff


static func _get_pose(b: PackedByteArray, at: int) -> Transform3D:
	var bits: int = b.decode_u32(at + 9) | (b[at + 13] << 32)
	var big := bits & 3
	var c := [0.0, 0.0, 0.0, 0.0]
	var shift := 2
	var left := 1.0
	for i in 4:
		if i != big:
			var v: float = ((bits >> shift) & 0xfff) / ROT_MAX
			c[i] = (v - 0.5) * 2.0 * ROT_RANGE
			left -= c[i] * c[i]
			shift += 12
	c[big] = sqrt(maxf(left, 0.0))
	return Transform3D(Basis(Quaternion(c[0], c[1], c[2], c[3]).normalized()), _get_position(b, at))
