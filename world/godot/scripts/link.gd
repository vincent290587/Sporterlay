class_name PowerLink
extends Node
## Receives power from Sporterlay: UDP datagrams on 127.0.0.1:<port>, {"v":1,"power":245},
## sent at 4 Hz. Nothing is ever sent back. Power drops to 0 W after STALE_S without a packet.

const STALE_S := 2.0

var port := 47810
var power := 0.0
var connected := false
var error := ""

var _udp := PacketPeerUDP.new()
var _last := -1e9


func _ready() -> void:
	var err := _udp.bind(port, "127.0.0.1")
	if err != OK:
		error = "UDP port %d is in use" % port
		push_warning(error)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while _udp.get_available_packet_count() > 0:
		var data: Variant = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		if data is Dictionary and int(data.get("v", 0)) == 1:
			power = maxf(0.0, float(data.get("power", 0)))
			_last = now
	connected = now - _last < STALE_S
	if not connected:
		power = 0.0


func _exit_tree() -> void:
	_udp.close()
