"""Loopback-only latency fixture; preserves TCP byte order and packet throughput."""

from collections import deque
import select
import socket
import threading
import time


class DelayedRelay:
    def __init__(self, listen_port, target_port, delay_ms, record_path=None):
        self.delay = delay_ms / 1000
        # One shared host-to-client budget models a server's total egress.
        # Zero means unlimited; input traffic retains the fixed delay.
        self.downstream_bytes_per_second = 0
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
        credit, credited_at, rotation = 0, time.monotonic(), 0
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
                    pending[routes[source]].append((time.monotonic() + self.delay, data))
                now = time.monotonic()
                shared_rate = self.downstream_bytes_per_second
                credit = (
                    min(max(1, shared_rate * 0.02), credit + shared_rate * (now - credited_at))
                    if shared_rate
                    else 0
                )
                credited_at = now
                targets = list(pending)
                if targets:
                    rotation = (rotation + 1) % len(targets)
                    targets = targets[rotation:] + targets[:rotation]
                for target in targets:
                    queue = pending[target]
                    rate = shared_rate if target in downstream else 0
                    while queue and queue[0][0] <= time.monotonic():
                        ready, data = queue[0]
                        allowance = min(len(data), int(credit)) if rate else len(data)
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
                            credit -= sent
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
