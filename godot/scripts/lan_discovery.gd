extends Node
## LAN game discovery over UDP broadcast (scripts/net.gd owns it). A host sends a small JSON beacon every
## BEACON_EVERY seconds to the broadcast addresses of its networks (and to localhost, for a second copy of the game on
## the same machine); the join menu listens on PORT and lists the hosts heard within FORGET_AFTER seconds.

signal hosts_changed

const PORT := 7775
const MAGIC := "plateau-map"
const BEACON_EVERY := 1.0                   # s
const FORGET_AFTER := 3.5                   # s without a beacon

## Heard hosts: id (random per hosting session) -> {ip, port, name, players, max, version, seen (s)}
var hosts := {}

var _beacon: PacketPeerUDP
var _beacon_info: Callable                  # -> Dictionary sent in the beacon
var _beacon_t := 0.0
var _listen: PacketPeerUDP
var _id := ""


## Starts sending beacons; `info` returns the host's {port, name, players, max, version}.
func start_beacon(info: Callable) -> void:
	stop()
	_id = "%x%x" % [randi(), Time.get_ticks_usec()]
	_beacon_info = info
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon_t = BEACON_EVERY                # first beacon at once


## Starts listening for beacons; false when the port is taken (another copy of the game listening on this machine).
func start_listening() -> bool:
	stop()
	_listen = PacketPeerUDP.new()
	if _listen.bind(PORT) != OK:
		_listen = null
		return false
	return true


func stop() -> void:
	if _beacon:
		_beacon.close()
	if _listen:
		_listen.close()
	_beacon = null
	_listen = null
	if not hosts.is_empty():
		hosts.clear()
		hosts_changed.emit()


func _process(delta: float) -> void:
	if _beacon:
		_beacon_t += delta
		if _beacon_t >= BEACON_EVERY:
			_beacon_t = 0.0
			_send_beacon()
	if _listen:
		_receive()


func _send_beacon() -> void:
	var info: Dictionary = _beacon_info.call()
	info["game"] = MAGIC
	info["id"] = _id
	var packet := JSON.stringify(info).to_utf8_buffer()
	var targets := ["255.255.255.255", "127.0.0.1"]
	# the limited broadcast only leaves by the default route: also each network's own broadcast address (/24 assumed)
	for ip in lan_addresses():
		var parts := ip.split(".")
		targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for target: String in targets:
		_beacon.set_dest_address(target, PORT)
		_beacon.put_packet(packet)


func _receive() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	while _listen.get_available_packet_count() > 0:
		var data := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		var info: Variant = JSON.parse_string(data.get_string_from_utf8())
		if not info is Dictionary or info.get("game") != MAGIC or not info.has("id"):
			continue
		var known: Dictionary = hosts.get(info["id"], {})
		# the same beacon comes in by localhost and by the LAN: show the address others can reach too
		if known.has("ip") and ip == "127.0.0.1" and known["ip"] != "127.0.0.1":
			ip = known["ip"]
		var entry := {"ip": ip, "port": int(info.get("port", 0)), "name": str(info.get("name", "?")),
				"players": int(info.get("players", 0)), "max": int(info.get("max", 0)),
				"version": int(info.get("version", 0)), "seen": now}
		var same := not known.is_empty() and known.duplicate().merged({"seen": now}, true) == entry
		hosts[info["id"]] = entry
		changed = changed or not same
	for id: String in hosts.keys():
		if now - hosts[id]["seen"] > FORGET_AFTER:
			hosts.erase(id)
			changed = true
	if changed:
		hosts_changed.emit()


## This machine's IPv4 addresses on local networks (private ranges), skipping loopback and virtual bridges
## (Docker, libvirt); the likeliest LAN address first.
static func lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for iface: Dictionary in IP.get_local_interfaces():
		var n: String = iface["name"]
		if n == "lo" or n.begins_with("docker") or n.begins_with("br-") or n.begins_with("virbr") or n.begins_with("veth"):
			continue
		for ip: String in iface["addresses"]:
			if ip.count(".") == 3 and _private(ip) and not ip in out:
				out.append(ip)
	var rank := func(ip: String) -> int: return 0 if ip.begins_with("192.168.") else (1 if ip.begins_with("10.") else 2)
	var sorted := Array(out)
	sorted.sort_custom(func(a: String, b: String) -> bool: return rank.call(a) < rank.call(b))
	return PackedStringArray(sorted)


static func _private(ip: String) -> bool:
	var p := ip.split(".")
	var a := int(p[0])
	var b := int(p[1])
	return a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)
