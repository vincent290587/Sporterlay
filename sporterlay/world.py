"""Power out to a virtual world (the Godot project in `world/godot`) over UDP.

Every tick (4 Hz) one JSON datagram goes to 127.0.0.1:<world_port>:
    {"v": 1, "power": 245}
`power` is the raw trainer power in W (0 when stale or not pedaling). It's one way:
nothing comes back, and Sporterlay's own riding (ERG, gears, speed) doesn't change.
The world turns power into speed with its own physics. Sending to a port nobody
listens on is harmless: Sporterlay never depends on the world running.
"""

from __future__ import annotations

import json
import logging
import socket
from typing import Optional

log = logging.getLogger(__name__)


class WorldLink:
    def __init__(self, port: int):
        self.addr = ("127.0.0.1", port)
        self._sock: Optional[socket.socket] = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setblocking(False)
        log.info("Sending power to udp://%s:%d", *self.addr)

    def send(self, power: Optional[int]) -> None:
        if self._sock is None:
            return
        msg = json.dumps({"v": 1, "power": power or 0}, separators=(",", ":")).encode()
        try:
            self._sock.sendto(msg, self.addr)
        except OSError as e:  # Windows: ICMP port unreachable from an earlier send, buffer full
            log.debug("World link send: %s", e)

    def close(self) -> None:
        if self._sock is not None:
            self._sock.close()
            self._sock = None
