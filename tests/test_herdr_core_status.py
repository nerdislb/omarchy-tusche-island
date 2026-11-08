import importlib.util
import json
import os
import queue
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("hcs", Path(__file__).resolve().parent.parent / "bin/herdr-core-status.py")
hcs = importlib.util.module_from_spec(spec); spec.loader.exec_module(hcs)

LS = {"terminals": [
    {"address": "t4", "agent": "pi", "cwd": "/home/x", "state": "live", "status": "done", "where": "~ / Codex"},
    {"address": "t13", "agent": "claude", "cwd": "/p", "state": "live", "status": "working", "where": "p / 2"},
    {"address": "t14", "agent": "pi", "state": "live", "status": "blocked"},
    {"address": "t15", "state": "live", "status": "working"},            # no agent: a plain shell
    {"address": "t16", "agent": "pi", "state": "finished", "status": "idle"},
    {"address": "t17; rm -rf ~", "agent": "pi", "state": "live", "status": "idle"},
    {"address": "vps/t7", "agent": "pi", "state": "live", "status": "weird"},
]}


def terminal(address="t4", state="working", **fields):
    return dict(address=address, argv=["/usr/bin/pi"], cwd="/home/x", state="live",
                status={"state": state, "app": "pi"}, labels={"where": "~ / Codex"}, **fields)


def initial(records, seq=10):
    return {"jsonrpc": "2.0", "id": 1, "result": {"seq": seq, "terminals": records}}


def event(seq, kind, data, address="t4"):
    return {"jsonrpc": "2.0", "method": "event", "params": {
        "seq": seq, "type": kind, "terminal": address, "data": data}}


class FakeCore:
    """A controllable plain-mode peer; each accepted connection is isolated."""
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.bind(str(path))
        self.socket.listen()
        self.socket.settimeout(0.1)
        self.connections = queue.Queue()
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.accept)
        self.thread.start()

    def accept(self):
        while not self.stop.is_set():
            try:
                peer, _ = self.socket.accept()
            except socket.timeout:
                continue
            self.connections.put(peer)

    def connect(self, method="events.subscribe", request_id=1):
        peer = self.connections.get(timeout=5)
        peer.settimeout(3)
        request = b""
        while not request.endswith(b"\n"):
            request += peer.recv(4096)
        if json.loads(request) != {"jsonrpc": "2.0", "id": request_id, "method": method, "params": {}}:
            raise AssertionError(request)
        return peer

    def close(self):
        self.stop.set()
        self.thread.join(timeout=2)
        self.socket.close()
        while not self.connections.empty():
            self.connections.get_nowait().close()


def send(peer, *messages):
    peer.sendall(b"".join(json.dumps(message).encode() + b"\n" for message in messages))


class HerdrCoreStatus(unittest.TestCase):
    def test_snapshot(self):
        snap = hcs.snapshot(json.dumps(LS))
        self.assertTrue(snap["available"])
        got = {a["pane"]: a["status"] for a in snap["agents"]}
        self.assertEqual(got, {"hc:t4": "idle", "hc:t13": "working", "hc:t14": "blocked", "hc:vps/t7": "unknown"})
        self.assertTrue(all(a["source"] == "herdr-core" for a in snap["agents"]))

    def test_bad_input(self):
        for raw in ("", "nope", "[]", '{"terminals": 3}'):
            self.assertEqual(hcs.snapshot(raw), {"available": False, "agents": []})

    def test_focus_rejects_odd_address(self):
        for bad in ("", "t1; id", "../x", "t", "--help"):
            self.assertEqual(hcs.focus(bad), 2)

    def test_cli_parity(self):
        # Handwritten CLI fixture includes argv fallback, explicit empty app,
        # Unicode, null status, remote address and fields CLI short ignores.
        records = [terminal(), terminal("t13", "error", name="fallback"),
                   terminal("t14", "done"), terminal("t15"), terminal("t16"),
                   terminal("vps/t7", "weird")]
        records[1]["labels"] = {}
        records[1]["status"]["app"] = "claude"
        records[2]["labels"] = {"where": "墨" * 150}
        records[2]["cwd"] = "/" + "x" * 450
        records[2]["status"]["app"] = "a" * 45
        records[3]["status"] = None
        records[3]["argv"] = ["/bin/sh"]
        records[3]["foreground"] = {"cwd": "/ignored"}
        records[3]["title"] = "ignored OSC title"
        records[4]["status"]["app"] = ""
        cli = {"terminals": [
            {"address": "t4", "agent": "pi", "cwd": "/home/x", "state": "live", "status": "working", "where": "~ / Codex"},
            {"address": "t13", "agent": "claude", "cwd": "/home/x", "state": "live", "status": "error", "name": "fallback"},
            {"address": "t14", "agent": "a" * 45, "cwd": "/" + "x" * 450, "state": "live", "status": "done", "where": "墨" * 150},
            {"address": "t15", "agent": "sh", "cwd": "/home/x", "state": "live", "where": "~ / Codex"},
            {"address": "t16", "agent": "", "cwd": "/home/x", "state": "live", "where": "~ / Codex"},
            {"address": "vps/t7", "agent": "pi", "cwd": "/home/x", "state": "live", "status": "weird", "where": "~ / Codex"},
        ]}
        state = hcs.EventState()
        state.feed(initial(records))
        self.assertEqual(hcs.encode(state.snapshot()), hcs.encode(hcs.snapshot(json.dumps(cli))))
        state.feed(event(11, "status", {"status": {"state": "blocked", "app": "codex"}}))
        state.feed(event(12, "labels", {"labels": {"where": "Project / 2"}}))
        cli['terminals'][0].update(status='blocked', agent='codex', where='Project / 2')
        self.assertEqual(hcs.encode(state.snapshot()), hcs.encode(hcs.snapshot(json.dumps(cli))))

    def test_deltas_and_sequence_fence(self):
        state = hcs.EventState()
        state.feed(initial([terminal(foreground={"pid": 12}, pid=12)]))
        state.feed(event(11, "status", {"status": {"state": "done", "app": "claude"}, "records": {}, "reported": True}))
        self.assertEqual(state.snapshot()["agents"][0]["status"], "idle")
        self.assertEqual(state.snapshot()["agents"][0]["agent"], "claude")
        state.feed(event(11, "removed", {}))  # duplicate is ignored
        state.feed(event(12, "title", {"title": "new title"}))
        state.feed(event(13, "labels", {"labels": {"where": "tab 2"}}))
        self.assertEqual(state.snapshot()["agents"][0]["title"], "tab 2")
        state.feed(event(14, "lost", {"reason": "holder_lost", "finished_ms": None}))
        self.assertEqual(state.terminals["t4"]["state"], "live")
        self.assertIsNone(state.terminals["t4"]["pid"])
        self.assertNotIn("foreground", state.terminals["t4"])
        state.feed(event(15, "restarted", terminal(state="idle")))
        self.assertEqual(state.snapshot()["agents"][0]["agent"], "pi")
        state.feed(event(16, "created", terminal("t20"), "t20"))
        state.feed(event(17, "finished", {"finished_ms": 123, "reason": "exited", "exit_code": 0}))
        self.assertEqual([a["pane"] for a in state.snapshot()["agents"]], ["hc:t20"])
        state.feed(event(18, "removed", {}, "t20"))
        self.assertEqual(state.snapshot()["agents"], [])

    def test_labels_record_and_missed(self):
        state = hcs.EventState()
        state.feed(initial([]))
        state.feed(event(11, "labels", {"labels": {}, "record": terminal()}))
        self.assertEqual(len(state.snapshot()["agents"]), 1)
        state.feed({"method": "missed", "params": {"seq": 20, "terminals": [terminal("t3", "blocked")]}})
        state.feed(event(19, "removed", {}, "t3"))
        state.feed({"method": "missed", "params": {"seq": 12, "terminals": []}})
        state.feed({"method": "heartbeat", "params": {"seq": 20}})
        self.assertEqual(state.snapshot()["agents"][0]["pane"], "hc:t3")
        self.assertEqual(state.seq, 20)
        # A core restart resets seq only on a new connection.
        state = hcs.EventState()
        state.feed(initial([], seq=0))
        self.assertEqual(state.snapshot(), {"available": True, "agents": []})

    def test_unrelated_events_and_gaps(self):
        state = hcs.EventState()
        state.feed(initial([terminal()]))
        before = state.snapshot()
        for seq, kind, data in [(11, "foreground", {"cwd": "/ignored"}),
                                (12, "turn", {"turn": 2}), (13, "size", {"cols": 80, "rows": 24}),
                                (14, "keep", {"keep": True}), (15, "doc", {"name": "test"})]:
            state.feed(event(seq, kind, data))
        self.assertEqual(before, state.snapshot())
        with self.assertRaises(ValueError):
            state.feed(event(17, "removed", {}))
        with self.assertRaises(ValueError):
            state.feed({"method": "heartbeat", "params": {"seq": 18}})

    def test_limit_and_creation_order(self):
        state = hcs.EventState()
        state.feed(initial([terminal(f"t{i}") for i in range(1, 66)] + [terminal("vps/t7")]))
        self.assertEqual(len(state.snapshot()["agents"]), hcs.LIMIT)
        state.feed(event(11, "removed", {}, "t1"))
        self.assertEqual(state.snapshot()["agents"][-1]["pane"], "hc:t65")
        state.feed(event(12, "created", terminal("t1"), "t1"))
        self.assertEqual(state.snapshot()["agents"][0]["pane"], "hc:t1")
        state.feed(event(13, "created", terminal("t1;bad"), "t1;bad"))
        self.assertNotIn("t1;bad", state.terminals)

    def test_remote_groups_follow_cli_machine_order(self):
        state = hcs.EventState()
        state.feed(initial([terminal("b/t12"), terminal("a/t2"), terminal("b/t2"), terminal()]))
        state.feed(event(11, "created", terminal("b/t3"), "b/t3"))
        self.assertEqual([a['pane'] for a in state.snapshot(['b', 'a'])['agents']],
                         ['hc:t4', 'hc:b/t2', 'hc:b/t3', 'hc:b/t12', 'hc:a/t2'])

    def test_endpoint_resolution(self):
        with tempfile.TemporaryDirectory(prefix="island-events-") as folder:
            env = {"HOME": folder, "XDG_CONFIG_HOME": folder, "XDG_RUNTIME_DIR": folder, "HC_SESSION": " islandtest "}
            with patch.dict(os.environ, env, clear=True):
                self.assertEqual(hcs.socket_path(), folder + "/herdr-core/islandtest.sock")
                config = Path(folder, "herdr-core/config.toml")
                config.parent.mkdir()
                config.write_text('socket = "/tmp/custom.sock"\n')
                self.assertEqual(hcs.socket_path(), "/tmp/custom.sock")
                os.environ["HC_SOCKET"] = "/tmp/override.sock"
                self.assertEqual(hcs.socket_path(), "/tmp/override.sock")
                del os.environ["HC_SOCKET"]
                config.unlink()
                os.environ["HC_SESSION"] = "../bad"
                with self.assertRaises(ValueError):
                    hcs.socket_path()

    def test_retry_backoff_caps_at_thirty_seconds(self):
        clock, attempts, lines = [0.0], [], []

        def connect(_):
            attempts.append(clock[0])
            if len(attempts) == 9:
                raise KeyboardInterrupt
            raise FileNotFoundError

        peer = unittest.mock.MagicMock()
        peer.__enter__.return_value = peer
        peer.connect.side_effect = connect
        with patch.object(hcs.socket, "socket", return_value=peer), \
             patch.object(hcs, "socket_path", return_value="/tmp/absent.sock"), \
             patch.object(hcs.time, "monotonic", side_effect=lambda: clock[0]), \
             patch.object(hcs.time, "sleep", side_effect=lambda seconds: clock.__setitem__(0, clock[0] + seconds)), \
             patch("builtins.print", side_effect=lambda *args, **kw: lines.append(clock[0])), \
             patch.object(hcs, "run_ls", side_effect=AssertionError("watch must never poll")):
            with self.assertRaises(KeyboardInterrupt):
                hcs.watch()
        self.assertEqual(attempts, [0, 1, 3, 7, 15, 31, 61, 91, 121])
        self.assertTrue(all(b - a <= 3 for a, b in zip(lines, lines[1:])))

    def test_silent_core_deadlines(self):
        for subscribed in [False, True]:
            with self.subTest(subscribed=subscribed):
                clock, output, first = [0.0], [], [subscribed]
                peer = unittest.mock.MagicMock()
                peer.__enter__.return_value = peer
                peer.connect.side_effect = [None, KeyboardInterrupt]
                peer.recv.return_value = json.dumps(initial([])).encode() + b'\n'

                def select_read(readers, _writes, _errors, timeout):
                    if first[0]:
                        first[0] = False
                        return readers, [], []
                    clock[0] += timeout
                    return [], [], []

                with patch.object(hcs.socket, 'socket', return_value=peer), \
                     patch.object(hcs, 'socket_path', return_value='/tmp/test.sock'), \
                     patch.object(hcs.select, 'select', side_effect=select_read), \
                     patch.object(hcs.time, 'monotonic', side_effect=lambda: clock[0]), \
                     patch.object(hcs.time, 'sleep', side_effect=lambda seconds: clock.__setitem__(0, clock[0] + seconds)), \
                     patch('builtins.print', side_effect=lambda line, **kw: output.append((clock[0], json.loads(line)))):
                    with self.assertRaises(KeyboardInterrupt):
                        hcs.watch()
                self.assertEqual(output[-1], (hcs.CORE_TIMEOUT if subscribed else 5,
                                              {'available': False, 'agents': []}))
                if subscribed:
                    self.assertTrue(all(b[0] - a[0] <= 3 for a, b in zip(output, output[1:])))


class SocketWatch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="island-events-")
        self.path = Path(self.tmp.name, "core.sock")
        self.core = FakeCore(self.path)
        # Make any accidental watch-mode CLI fallback fail visibly.
        trap = Path(self.tmp.name, "hc")
        trap.write_text("#!/bin/sh\ntouch '" + self.tmp.name + "/hc-was-called'\nexit 1\n")
        trap.chmod(0o700)
        env = {"PATH": self.tmp.name, "HOME": self.tmp.name, "HC_SOCKET": str(self.path)}
        self.proc = subprocess.Popen([sys.executable, str(Path(hcs.__file__)), "--watch"],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True)
        self.lines = queue.Queue()
        self.reader = threading.Thread(target=lambda: [self.lines.put((time.monotonic(), line)) for line in self.proc.stdout])
        self.reader.start()

    def tearDown(self):
        self.proc.terminate()
        self.proc.wait(timeout=5)
        self.reader.join(timeout=2)
        self.assertEqual(self.proc.stderr.read(), "")
        self.proc.stdout.close()
        self.proc.stderr.close()
        self.core.close()
        self.assertFalse(Path(self.tmp.name, "hc-was-called").exists())
        self.tmp.cleanup()

    def read(self, timeout=5):
        stamp, line = self.lines.get(timeout=timeout)
        return stamp, json.loads(line)

    def test_stream_heartbeat_missed_and_reconnect(self):
        with self.core.connect() as peer:
            send(peer, initial([terminal()]))
            start, snap = self.read()
            self.assertEqual(snap["agents"][0]["status"], "working")
            send(peer, event(11, "title", {"title": "ignored"}), {"method": "heartbeat", "params": {"seq": 11}})
            with self.assertRaises(queue.Empty):
                self.lines.get(timeout=0.2)
            heartbeat, same = self.read()
            self.assertEqual(same, snap)
            self.assertGreaterEqual(heartbeat - start, 2.8)
            self.assertLess(heartbeat - start, 3.8)
            # Multiple messages in a single read must each be applied/emitted.
            send(peer, event(12, "status", {"status": {"state": "done", "app": "pi"}}),
                 {"method": "missed", "params": {"seq": 30, "terminals": [terminal("t2", "blocked")]}})
            self.assertEqual(self.read()[1]["agents"][0]["status"], "idle")
            self.assertEqual(self.read()[1]["agents"][0]["pane"], "hc:t2")
            send(peer, event(29, "removed", {}, "t2"))
        self.assertFalse(self.read()[1]["available"])
        with self.core.connect() as peer:
            payload = json.dumps(initial([terminal("t3", "idle")], seq=0)).encode() + b"\n"
            peer.sendall(payload[:7])
            time.sleep(0.05)
            peer.sendall(payload[7:])
            self.assertEqual(self.read()[1]["agents"][0]["pane"], "hc:t3")

    def test_missing_socket_keeps_heartbeat_without_cli(self):
        self.core.close()
        self.path.unlink()
        start, snap = self.read()
        self.assertEqual(snap, {"available": False, "agents": []})
        end, same = self.read()
        self.assertEqual(snap, same)
        self.assertLess(end - start, 3.8)

    def test_remote_machine_metadata_is_read_only_on_topology_change(self):
        with self.core.connect() as peer:
            send(peer, initial([terminal("a/t10"), terminal("b/t2"), terminal("a/t2")]))
            with self.core.connect("machine.list", 2) as metadata:
                send(metadata, {"jsonrpc": "2.0", "id": 2, "result": {"machines": [{"name": "b"}, {"name": "a"}]}})
            self.assertEqual([a['pane'] for a in self.read()[1]['agents']], ['hc:b/t2', 'hc:a/t2', 'hc:a/t10'])
            send(peer, event(11, "status", {"status": {"state": "done", "app": "pi"}}, "a/t2"))
            self.assertEqual(self.read()[1]['agents'][1]['status'], 'idle')
            self.assertTrue(self.core.connections.empty())

    def test_bad_response_and_sequence_gap_reconnect(self):
        with self.core.connect() as peer:
            send(peer, {"jsonrpc": "2.0", "id": 1, "error": {"message": "not supported"}})
            self.assertFalse(self.read()[1]['available'])
        with self.core.connect() as peer:
            send(peer, initial([terminal()]))
            self.assertTrue(self.read()[1]['available'])
            send(peer, event(12, "removed", {}))  # seq 11 was never received
            self.assertFalse(self.read()[1]['available'])
        with self.core.connect() as peer:
            send(peer, initial([], seq=0))
            self.assertEqual(self.read()[1], {'available': True, 'agents': []})


if __name__ == "__main__":
    unittest.main()
