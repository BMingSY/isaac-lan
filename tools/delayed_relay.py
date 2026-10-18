"""Owned TCP delivery fixture: delay, jitter, rate limits and ordered stalls.

Stalls model the delivery gap visible to an application, not IP packet loss.
Every accepted byte is forwarded in order, including across graceful close.
"""

from collections import deque
import select
import random
import socket
import threading
import time


class DelayedRelay:
    def __init__(self, listen_port, target_port, delay_ms, record_path=None):
        self.delay = delay_ms / 1000
        # One shared host-to-client budget models a server's total egress.
        # Zero means unlimited in either direction.
        self.downstream_bytes_per_second = 0
        self.upstream_bytes_per_second = 0
        self.jitter = 0
        self.stall = (0, 0)
        self.downstream_bytes = 0
        self.upstream_bytes = 0
        self.connections = 0
        self.record_path = record_path
        if record_path:
            record_path.mkdir(parents=True, exist_ok=True)
        self.target = target_port
        self.listener = socket.socket()
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", listen_port))
        self.listener.listen()
        self.listener.setblocking(False)
        self.stop = threading.Event()
        self.error = None
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def configure(self, settings, default_delay_ms):
        """Validate a complete live profile before changing the owned relay."""
        rates = [settings.get(name + "_bytes_per_second", 0) for name in ("downstream", "upstream")]
        delay = settings.get("delay_ms", default_delay_ms)
        jitter = settings.get("jitter_ms", 0)
        interval, duration = settings.get("stall_every_ms", 0), settings.get("stall_ms", 0)
        if any(type(rate) is not int or rate < 0 for rate in rates):
            raise ValueError("Invalid owned relay bandwidth")
        if any(
            type(value) not in (int, float) or not 0 <= value <= 5000 for value in (delay, jitter)
        ):
            raise ValueError("Invalid owned relay latency or jitter")
        if (
            any(type(value) is not int or value < 0 for value in (interval, duration))
            or bool(interval) != bool(duration)
            or duration >= interval
            and duration != 0
            or duration > 5000
        ):
            raise ValueError("Invalid owned relay stall interval")
        self.downstream_bytes_per_second, self.upstream_bytes_per_second = rates
        self.delay, self.jitter = delay / 1000, jitter / 1000
        self.stall = (interval / 1000, duration / 1000)

    def settings(self):
        return {
            "downstream_bytes_per_second": self.downstream_bytes_per_second,
            "upstream_bytes_per_second": self.upstream_bytes_per_second,
            "delay_ms": self.delay * 1000,
            "jitter_ms": self.jitter * 1000,
            "stall_every_ms": self.stall[0] * 1000,
            "stall_ms": self.stall[1] * 1000,
        }

    def connect(self):
        # Consecutive native endings reuse the game processes, but close the
        # old host listener before creating the next lobby. Keep an accepted
        # guest connection alive while that loopback listener returns.
        deadline = time.monotonic() + 30
        while not self.stop.is_set():
            try:
                return socket.create_connection(("127.0.0.1", self.target), timeout=2)
            except ConnectionRefusedError:
                if time.monotonic() >= deadline:
                    raise
                self.stop.wait(0.05)
        return None

    def run(self):
        routes, pending = {}, {}
        downstream = set()
        recordings, sequence = {}, 0
        credit, credited_at, rotation = [0, 0], time.monotonic(), 0
        started_at = None
        jitter = random.Random(0)
        eof, shutdown = set(), set()
        try:
            while not self.stop.is_set():
                readable, _, _ = select.select(
                    [
                        self.listener,
                        *(
                            s
                            for s in routes
                            if s not in eof
                            and sum(len(data) for _, data in pending[routes[s]]) < 524288
                        ),
                    ],
                    [],
                    [],
                    0.002,
                )
                for source in readable:
                    if source is self.listener:
                        client, _ = self.listener.accept()
                        try:
                            host = self.connect()
                        except Exception:
                            client.close()
                            raise
                        if host is None:
                            client.close()
                            break
                        for sock in (client, host):
                            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                            sock.setblocking(False)
                            pending[sock] = deque()
                        routes[client], routes[host] = host, client
                        if self.record_path:
                            sequence += 1
                            recordings[host] = (self.record_path / f"host-{sequence}.bin").open(
                                "wb"
                            )
                        downstream.add(client)
                        if started_at is None:
                            started_at = time.monotonic()
                        self.connections += 1
                        continue
                    try:
                        data = source.recv(65536)
                    except ConnectionResetError:
                        data = b""
                    if not data:
                        eof.add(source)
                        continue
                    if source in recordings:
                        recordings[source].write(data)
                    delay = max(0, self.delay + jitter.uniform(-self.jitter, self.jitter))
                    pending[routes[source]].append((time.monotonic() + delay, data))
                now = time.monotonic()
                rates = [self.upstream_bytes_per_second, self.downstream_bytes_per_second]
                for direction, rate in enumerate(rates):
                    credit[direction] = (
                        min(max(1, rate * 0.02), credit[direction] + rate * (now - credited_at))
                        if rate
                        else 0
                    )
                credited_at = now
                interval, duration = self.stall
                elapsed = now - started_at if started_at is not None else 0
                stalled = interval and elapsed >= interval and elapsed % interval < duration
                targets = list(pending)
                if targets:
                    rotation = (rotation + 1) % len(targets)
                    targets = targets[rotation:] + targets[:rotation]
                for target in targets:
                    queue = pending[target]
                    direction = int(target in downstream)
                    rate = rates[direction]
                    while not stalled and queue and queue[0][0] <= time.monotonic():
                        ready, data = queue[0]
                        allowance = min(len(data), int(credit[direction])) if rate else len(data)
                        if allowance == 0:
                            break
                        try:
                            sent = target.send(data[:allowance])
                        except BlockingIOError:
                            break
                        except (BrokenPipeError, ConnectionResetError):
                            # A deliberate guest departure is a connection
                            # event, not a failure of the latency fixture.
                            queue.clear()
                            eof.add(target)
                            break
                        if rate:
                            credit[direction] -= sent
                        if target in downstream:
                            self.downstream_bytes += sent
                        else:
                            self.upstream_bytes += sent
                        if sent == len(data):
                            queue.popleft()
                        else:
                            queue[0] = ready, data[sent:]
                            break
                    if not queue and routes[target] in eof and target not in shutdown:
                        # Forward queued FIN/finish bytes before closing the
                        # opposite direction; do not turn a clean game exit
                        # into an artificial transport failure.
                        try:
                            target.shutdown(socket.SHUT_WR)
                        except OSError:
                            eof.add(target)
                        shutdown.add(target)
                for sock in list(routes):
                    if sock not in routes:
                        continue
                    other = routes[sock]
                    if sock in eof and other in eof and not pending[sock] and not pending[other]:
                        for end in (sock, other):
                            routes.pop(end)
                            pending.pop(end)
                            eof.discard(end)
                            shutdown.discard(end)
                            if end in downstream:
                                self.connections -= 1
                            downstream.discard(end)
                            if end in recordings:
                                recordings.pop(end).close()
                            end.close()
        except Exception as error:
            if not self.stop.is_set():
                self.error = str(error)
        finally:
            for stream in recordings.values():
                stream.close()
            for sock in routes:
                sock.close()
            self.listener.close()

    def close(self):
        self.stop.set()
        self.thread.join(timeout=3)
