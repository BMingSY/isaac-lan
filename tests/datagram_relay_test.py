"""Exercise whole UDP payloads, impairment, route ownership and live recovery."""

import socket
import threading
import time
import unittest

from datagram_relay import DatagramRelay


class DatagramRelayTest(unittest.TestCase):
    def test_bandwidth_queue_does_not_starve_full_size_datagrams(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        server.bind(("127.0.0.1", 0))
        server.settimeout(1)
        relay = DatagramRelay(0, server.getsockname()[1], 0)
        relay.configure({"downstream_bytes_per_second": 6000}, 0)
        client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        client.setblocking(False)
        try:
            client.sendto(b"route", relay.listener.getsockname())
            _, route = server.recvfrom(65536)
            # Exhaust the initial burst, then keep small traffic above the
            # bandwidth limit while a full-size fragment waits its turn.
            for _ in range(3):
                server.sendto(b"warm" * 5500, route)
            time.sleep(0.1)
            server.sendto(b"L" * 1200, route)
            began, arrived = time.monotonic(), False
            while time.monotonic() - began < 2:
                server.sendto(b"s" * 100, route)
                while True:
                    try:
                        data, _ = client.recvfrom(65536)
                        arrived |= data == b"L" * 1200
                    except BlockingIOError:
                        break
                time.sleep(0.01)
            self.assertTrue(arrived, "Small packets starved a full-size UDP fragment")
            self.assertIsNone(relay.error)
        finally:
            relay.close()
            client.close()
            server.close()

    def test_loss_reordering_duplication_and_recovery(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        server.bind(("127.0.0.1", 0))
        server.settimeout(0.05)
        stop = threading.Event()

        def echo():
            while not stop.is_set():
                try:
                    data, address = server.recvfrom(65536)
                    server.sendto(data, address)
                except TimeoutError:
                    continue

        worker = threading.Thread(target=echo)
        worker.start()
        relay = DatagramRelay(0, server.getsockname()[1], 5)
        client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        client.settimeout(0.1)
        destination = relay.listener.getsockname()
        try:
            relay.configure({"loss_percent": 100}, 5)
            client.sendto(b"discard", destination)
            with self.assertRaises(TimeoutError):
                client.recvfrom(65536)
            relay.configure({"loss_percent": 20, "duplicate_percent": 50, "jitter_ms": 20}, 5)
            for number in range(100):
                client.sendto(number.to_bytes(2, "big") + b"payload" * 100, destination)
            received = []
            deadline = time.monotonic() + 0.6
            while time.monotonic() < deadline:
                try:
                    data, _ = client.recvfrom(65536)
                    self.assertEqual(data[2:], b"payload" * 100)
                    received.append(int.from_bytes(data[:2], "big"))
                except TimeoutError:
                    continue
            self.assertGreater(len(received), 20)
            self.assertLess(len(set(received)), len(received))
            self.assertNotEqual(received, sorted(received))
            self.assertGreater(relay.dropped, 10)
            self.assertGreater(relay.duplicates, 10)
            relay.configure({}, 0)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as other:
                other.settimeout(1)
                other.sendto(b"second route", destination)
                self.assertEqual(other.recvfrom(65536)[0], b"second route")
            self.assertEqual(relay.connections, 2)
            self.assertIsNone(relay.error)
        finally:
            client.close()
            relay.close()
            stop.set()
            worker.join(timeout=2)
            server.close()

    def test_invalid_profile_does_not_partially_apply(self):
        relay = DatagramRelay(0, 1, 10)
        try:
            before = relay.settings()
            for profile in (
                {"loss_percent": 101},
                {"jitter_ms": float("nan")},
                {"upstream_bytes_per_second": -1},
                {"stall_ms": 100},
            ):
                with self.assertRaises(ValueError):
                    relay.configure(profile, 20)
                self.assertEqual(relay.settings(), before)
        finally:
            relay.close()
