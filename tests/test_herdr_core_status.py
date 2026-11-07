import importlib.util, json, unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
