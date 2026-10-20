"""Owned UDP relay with actual loss, duplication, reordering and bounded queues."""

import heapq
import math
import random
import select
import socket
import struct
import threading
import time


class DatagramRelay:
    def __init__(self, listen_port, target_port, delay_ms, record_path=None):
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.listener.bind(("127.0.0.1", listen_port))
        self.listener.setblocking(False)
        self.target = ("127.0.0.1", target_port)
        self.delay, self.jitter = delay_ms / 1000, 0
        self.loss, self.duplicate = 0, 0
        self.downstream_bytes_per_second = self.upstream_bytes_per_second = 0
        self.stall = (0, 0)
        self.downstream_bytes = self.upstream_bytes = self.connections = 0
        self.dropped = self.duplicates = self.max_packet_bytes = 0
        self.error = None
        self.stop = threading.Event()
        self.record = None
        if record_path:
            record_path.mkdir(parents=True, exist_ok=True)
            self.record = (record_path / "datagrams.bin").open("wb")
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def configure(self, settings, default_delay_ms):
        delay = settings.get("delay_ms", default_delay_ms)
        jitter = settings.get("jitter_ms", 0)
        loss = settings.get("loss_percent", 0)
        duplicate = settings.get("duplicate_percent", 0)
        rates = [settings.get(name + "_bytes_per_second", 0) for name in ("downstream", "upstream")]
        interval, duration = settings.get("stall_every_ms", 0), settings.get("stall_ms", 0)
        numbers = (delay, jitter, loss, duplicate, interval, duration)
        if any(type(x) not in (int, float) or not math.isfinite(x) or x < 0 for x in numbers):
            raise ValueError("Invalid UDP impairment profile")
        if max(delay, jitter, duration) > 5000 or max(loss, duplicate) > 100:
            raise ValueError("UDP impairment out of range")
        if any(type(rate) is not int or rate < 0 for rate in rates):
            raise ValueError("Invalid UDP bandwidth")
        if bool(interval) != bool(duration) or duration and duration >= interval:
            raise ValueError("Invalid UDP burst-loss interval")
        self.delay, self.jitter = delay / 1000, jitter / 1000
        self.loss, self.duplicate = loss / 100, duplicate / 100
        self.downstream_bytes_per_second, self.upstream_bytes_per_second = rates
        self.stall = (interval / 1000, duration / 1000)

    def settings(self):
        return {
            "transport": "udp",
            "delay_ms": self.delay * 1000,
            "jitter_ms": self.jitter * 1000,
            "loss_percent": self.loss * 100,
            "duplicate_percent": self.duplicate * 100,
            "downstream_bytes_per_second": self.downstream_bytes_per_second,
            "upstream_bytes_per_second": self.upstream_bytes_per_second,
            "stall_every_ms": self.stall[0] * 1000,
            "stall_ms": self.stall[1] * 1000,
            "dropped_datagrams": self.dropped,
            "duplicated_datagrams": self.duplicates,
            "max_datagram_bytes": self.max_packet_bytes,
        }

    def run(self):
        clients, upstream, pending = {}, {}, []
        rng = random.Random(103)
        sequence, queued = 0, 0
        began = credited = time.monotonic()
        credit = [65536.0, 65536.0]
        try:
            while not self.stop.is_set():
                readable, _, _ = select.select([self.listener, *upstream], [], [], 0.002)
                for source in readable:
                    for _ in range(256):
                        try:
                            data, address = source.recvfrom(65536)
                        except BlockingIOError:
                            break
                        if source is self.listener:
                            if address not in clients:
                                if len(clients) >= 16:
                                    self.dropped += 1
                                    continue
                                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                                sock.bind(("127.0.0.1", 0))
                                sock.setblocking(False)
                                clients[address], upstream[sock] = sock, address
                                self.connections += 1
                            target, destination, direction = clients[address], self.target, 0
                        else:
                            if address != self.target:
                                continue
                            target, destination, direction = self.listener, upstream[source], 1
                        now = time.monotonic()
                        self.max_packet_bytes = max(self.max_packet_bytes, len(data))
                        if self.record:
                            # Timestamp, direction, payload length, complete UDP payload.
                            self.record.write(struct.pack("!dBH", now, direction, len(data)) + data)
                        interval, duration = self.stall
                        burst = (
                            interval
                            and now - began >= interval
                            and (now - began) % interval < duration
                        )
                        if burst or rng.random() < self.loss or queued + len(data) > 524288:
                            self.dropped += 1
                            continue
                        copies = 2 if rng.random() < self.duplicate else 1
                        self.duplicates += copies - 1
                        for _ in range(copies):
                            due = now + max(0, self.delay + rng.uniform(-self.jitter, self.jitter))
                            sequence += 1
                            heapq.heappush(
                                pending, (due, sequence, target, destination, direction, data)
                            )
                            queued += len(data)
                now = time.monotonic()
                rates = [self.upstream_bytes_per_second, self.downstream_bytes_per_second]
                for direction, rate in enumerate(rates):
                    credit[direction] = min(65536, credit[direction] + rate * (now - credited))
                credited = now
                deferred = []
                blocked = set()
                while pending and pending[0][0] <= now:
                    packet = heapq.heappop(pending)
                    due, sequence_number, target, destination, direction, data = packet
                    if now - due > 0.5:
                        self.dropped += 1
                        queued -= len(data)
                        continue
                    # Preserve due-order within each bandwidth queue. Letting
                    # later small packets spend its credit can permanently
                    # starve MTU-sized fragments under sustained load.
                    if direction in blocked or (rates[direction] and credit[direction] < len(data)):
                        blocked.add(direction)
                        deferred.append(packet)
                        continue
                    try:
                        target.sendto(data, destination)
                    except BlockingIOError:
                        blocked.add(direction)
                        deferred.append(packet)
                        continue
                    queued -= len(data)
                    if rates[direction]:
                        credit[direction] -= len(data)
                    if direction:
                        self.downstream_bytes += len(data)
                    else:
                        self.upstream_bytes += len(data)
                for packet in deferred:
                    heapq.heappush(pending, packet)
        except Exception as error:
            self.error = str(error)
        finally:
            for sock in upstream:
                sock.close()
            self.listener.close()
            if self.record:
                self.record.close()

    def close(self):
        self.stop.set()
        self.thread.join(timeout=3)
        if self.thread.is_alive():
            raise RuntimeError("UDP relay did not stop")
