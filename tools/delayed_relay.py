"""Loopback-only latency fixture; preserves TCP byte order and packet throughput."""
from collections import deque
import select
import socket
import threading
import time


class DelayedRelay:
    def __init__(self, listen_port, target_port, delay_ms):
        self.delay = delay_ms / 1000
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

    def run(self):
        routes, pending = {}, {}
        eof, shutdown = set(), set()
        try:
            while not self.stop.is_set():
                readable, _, _ = select.select([self.listener, *(s for s in routes if s not in eof)], [], [], .002)
                for source in readable:
                    if source is self.listener:
                        client, _ = self.listener.accept()
                        host = socket.create_connection(("127.0.0.1", self.target), timeout=2)
                        for sock in (client, host):
                            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                            sock.setblocking(False)
                            pending[sock] = deque()
                        routes[client], routes[host] = host, client
                        continue
                    try:
                        data = source.recv(65536)
                    except ConnectionResetError:
                        data = b""
                    if not data:
                        eof.add(source)
                        continue
                    pending[routes[source]].append((time.monotonic() + self.delay, data))
                for target, queue in pending.items():
                    while queue and queue[0][0] <= time.monotonic():
                        ready, data = queue[0]
                        try:
                            sent = target.send(data)
                        except BlockingIOError:
                            break
                        except (BrokenPipeError, ConnectionResetError):
                            # A deliberate guest departure is a connection
                            # event, not a failure of the latency fixture.
                            queue.clear()
                            eof.add(target)
                            break
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
                            end.close()
        except Exception as error:
            if not self.stop.is_set():
                self.error = str(error)
        finally:
            for sock in routes:
                sock.close()
            self.listener.close()

    def close(self):
        self.stop.set()
        self.thread.join(timeout=3)
