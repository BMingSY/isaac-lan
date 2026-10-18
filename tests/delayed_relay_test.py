"""Exercise the real TCP relay's byte order, asymmetric rate and live recovery."""

from pathlib import Path
import socket
import sys
import threading
import time
import unittest
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from delayed_relay import DelayedRelay


class DelayedRelayTest(unittest.TestCase):
    def test_jitter_stalls_and_upstream_limit_preserve_bytes_and_fin(self):
        payload = bytes(range(251)) * 200
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen()
        server.settimeout(8)
        received, errors, gaps = [], [], []

        def serve():
            try:
                with server.accept()[0] as connection:
                    connection.settimeout(8)
                    chunks, previous = [], time.monotonic()
                    while data := connection.recv(1024):
                        now = time.monotonic()
                        gaps.append(now - previous)
                        previous = now
                        chunks.append(data)
                    received.append(b"".join(chunks))
                    connection.sendall(b"complete")
            except Exception as error:
                errors.append(error)

        relay = DelayedRelay(0, server.getsockname()[1], 40)
        relay.configure(
            {
                "jitter_ms": 20,
                "upstream_bytes_per_second": 32768,
                "stall_every_ms": 300,
                "stall_ms": 150,
            },
            40,
        )
        thread = threading.Thread(target=serve)
        thread.start()
        try:
            with socket.create_connection(relay.listener.getsockname(), timeout=8) as client:
                client.settimeout(8)
                client.sendall(payload)
                client.shutdown(socket.SHUT_WR)
                result = bytearray()
                while data := client.recv(1024):
                    result.extend(data)
                self.assertEqual(result, b"complete")
            thread.join(timeout=8)
            self.assertFalse(thread.is_alive())
            self.assertEqual(received, [payload])
            self.assertFalse(errors)
            self.assertGreater(max(gaps), 0.1, "Configured delivery stall never happened")
            self.assertEqual(relay.upstream_bytes, len(payload))
            self.assertIsNone(relay.error)
        finally:
            relay.close()
            server.close()
            thread.join(timeout=3)

    def test_invalid_profile_is_rejected_without_partial_application(self):
        relay = DelayedRelay(0, 1, 40)
        try:
            before = relay.settings()
            for settings in (
                {"upstream_bytes_per_second": -1},
                {"jitter_ms": float("nan")},
                {"stall_every_ms": 100, "stall_ms": 100},
                {"stall_ms": 10},
            ):
                with self.assertRaises(ValueError):
                    relay.configure(settings, 40)
                self.assertEqual(relay.settings(), before)
        finally:
            relay.close()

    def test_three_clients_share_one_egress_budget(self):
        payload = bytes(range(256)) * 256
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen()
        server.settimeout(8)
        errors, received = [], []

        def serve():
            try:
                for _ in range(3):
                    with server.accept()[0] as connection:
                        connection.sendall(payload)
            except Exception as error:
                errors.append(error)

        def receive(client):
            try:
                data = bytearray()
                while len(data) < len(payload):
                    chunk = client.recv(8192)
                    if not chunk:
                        raise EOFError("Incomplete shared-budget stream")
                    data.extend(chunk)
                received.append(bytes(data))
            except Exception as error:
                errors.append(error)

        with TemporaryDirectory() as folder:
            relay = DelayedRelay(0, server.getsockname()[1], 10, Path(folder))
            relay.downstream_bytes_per_second = 131072
            producer = threading.Thread(target=serve)
            producer.start()
            clients, readers = [], []
            began = time.monotonic()
            try:
                for _ in range(3):
                    client = socket.create_connection(relay.listener.getsockname(), timeout=8)
                    client.settimeout(8)
                    clients.append(client)
                    reader = threading.Thread(target=receive, args=(client,))
                    reader.start()
                    readers.append(reader)
                for reader in readers:
                    reader.join(timeout=8)
                    self.assertFalse(reader.is_alive())
                self.assertGreater(time.monotonic() - began, 1.25)
                self.assertEqual(received, [payload] * 3)
                self.assertFalse(errors)
                self.assertEqual(relay.downstream_bytes, len(payload) * 3)
            finally:
                for client in clients:
                    client.close()
                relay.close()
                server.close()
                producer.join(timeout=3)
                for reader in readers:
                    reader.join(timeout=3)
            self.assertEqual(
                [p.read_bytes() for p in sorted(Path(folder).glob("host-*.bin"))], [payload] * 3
            )

    def test_downstream_limit_preserves_input_and_can_be_removed(self):
        payload = bytes(range(251)) * 3000
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen()
        server.settimeout(5)
        acknowledgments, errors = [], []

        def serve():
            try:
                with server.accept()[0] as connection:
                    connection.settimeout(5)
                    connection.sendall(payload)
                    received = b""
                    while len(received) < 5:
                        data = connection.recv(5 - len(received))
                        if not data:
                            raise EOFError("Input stream closed before the complete message")
                        received += data
                    acknowledgments.append((received, time.monotonic()))
            except Exception as error:
                errors.append(error)

        relay = DelayedRelay(0, server.getsockname()[1], 20)
        relay.downstream_bytes_per_second = 131072
        thread = threading.Thread(target=serve)
        thread.start()
        try:
            with socket.create_connection(relay.listener.getsockname(), timeout=5) as client:
                client.settimeout(5)
                began = time.monotonic()
                client.sendall(b"input")
                received = bytearray()
                while len(received) < 131072:
                    received.extend(client.recv(8192))
                limited = time.monotonic() - began
                self.assertGreater(limited, 0.85)
                self.assertLess(limited, 3)
                relay.downstream_bytes_per_second = 0
                while len(received) < len(payload):
                    data = client.recv(65536)
                    self.assertTrue(data, "Relay closed before forwarding all bytes")
                    received.extend(data)
                self.assertEqual(received, payload)
                self.assertLess(time.monotonic() - began - limited, 2)
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
            self.assertEqual(errors, [])
            self.assertEqual(acknowledgments[0][0], b"input")
            self.assertLess(acknowledgments[0][1] - began, 0.5)
            self.assertIsNone(relay.error)
        finally:
            relay.close()
            server.close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
