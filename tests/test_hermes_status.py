"""Read-only Hermes Desktop/TUI status contract; no Hermes runtime imports."""
import importlib.util
import json
from pathlib import Path
from contextlib import closing
import os
import subprocess
import sys
import time
import sqlite3
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "bin" / "hermes-status.py"
spec = importlib.util.spec_from_file_location("hermes_status", MODULE)
assert spec is not None and spec.loader is not None
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)


class HermesStatusTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.marker = self.home / "desktop" / "interrupted_turns.json"
        self.marker.parent.mkdir()
        with closing(sqlite3.connect(self.home / "state.db")) as db:
            db.execute("CREATE TABLE sessions (id TEXT PRIMARY KEY, title TEXT, source TEXT)")
            db.execute("INSERT INTO sessions VALUES ('session-a', 'Bar integration', 'desktop')")
            db.commit()
        self.entry = {"writer_pid": 123, "writer_start_time": 50.0, "started_at": 90.0,
                      "prompt": "PRIVATE PROMPT MUST NOT LEAVE HERMES"}
        self.tracker = status.Tracker(self.home, writer_live=lambda entry: True, now=lambda: 100.0)

    def write(self, entries):
        self.marker.write_text(json.dumps(entries))

    def test_working_turn_uses_only_title_and_never_writes_hermes_state(self):
        self.write({"session-a": self.entry})
        before = {p: p.read_bytes() for p in (self.marker, self.home / 'state.db')}
        result = self.tracker.poll()
        self.assertTrue(result['available'])
        self.assertEqual(result['agents'], [{"pane": "hermes:session-a", "agent": "Hermes",
                                            "title": "Bar integration", "status": "working"}])
        self.assertNotIn('PRIVATE', json.dumps(result))
        self.assertEqual(before, {p: p.read_bytes() for p in before})

    def test_concluded_turn_emits_one_idle_snapshot_then_disappears(self):
        self.write({'session-a': self.entry})
        self.tracker.poll()
        self.marker.unlink()  # Hermes removes the file when its last turn concludes.
        result = self.tracker.poll()
        self.assertEqual([a['status'] for a in result['agents']], ['idle'])
        self.assertEqual(result['agents'][0]['title'], 'Bar integration')
        self.assertEqual(self.tracker.poll()['agents'], [])
        self.assertEqual(status.Tracker(self.home, writer_live=lambda e: True, now=lambda: 100).poll()['agents'], [])

    def test_dead_unknown_and_stale_writers_never_work_or_complete(self):
        for live in (False, None):
            with self.subTest(live=live):
                tracker = status.Tracker(self.home, writer_live=lambda e: live, now=lambda: 100)
                self.write({'session-a': self.entry})
                self.assertEqual(tracker.poll()['agents'], [])
        self.write({'session-a': dict(self.entry, started_at=-90000)})
        self.assertEqual(self.tracker.poll()['agents'], [])
        self.write({'session-a': self.entry})
        self.tracker.poll()
        self.tracker.writer_live = lambda e: False
        self.marker.unlink()
        self.assertEqual(self.tracker.poll()['agents'], [], 'death is not a completed turn')

    def test_unreadable_marker_drops_state_without_a_completion(self):
        for text in ('broken JSON', '[]', 'null'):
            with self.subTest(text=text):
                self.write({'session-a': self.entry})
                self.tracker.poll()
                self.marker.write_text(text)
                self.assertEqual(self.tracker.poll(), {'available': False, 'agents': []})
                self.write({})
                self.assertEqual(self.tracker.poll()['agents'], [])

    def test_missing_title_database_is_optional_and_never_created(self):
        (self.home / 'state.db').unlink()
        self.write({'session-a': self.entry})
        self.assertEqual(self.tracker.poll()['agents'][0]['title'], 'Hermes')
        self.assertFalse((self.home / 'state.db').exists())

    def test_linux_writer_identity_rejects_reused_pid_and_unknown_start(self):
        stat = Path(f'/proc/{os.getpid()}/stat').read_text().rsplit(')', 1)[1].split()
        boot = next(float(line.split()[1]) for line in Path('/proc/stat').read_text().splitlines() if line.startswith('btime '))
        start = boot + int(stat[19]) / os.sysconf('SC_CLK_TCK')
        entry = dict(self.entry, writer_pid=os.getpid(), writer_start_time=start)
        self.assertTrue(status.writer_alive(entry))
        self.assertFalse(status.writer_alive(dict(entry, writer_start_time=start - 10)))
        self.assertIsNone(status.writer_alive(dict(entry, writer_start_time=None)))
        self.assertIsNone(status.writer_alive(dict(entry, writer_pid=True)))
        self.assertFalse(status.writer_alive(dict(entry, writer_pid=99999999)))

    def test_watch_cli_reads_real_marker_and_observes_its_removal(self):
        stat = Path(f'/proc/{os.getpid()}/stat').read_text().rsplit(')', 1)[1].split()
        boot = next(float(line.split()[1]) for line in Path('/proc/stat').read_text().splitlines() if line.startswith('btime '))
        entry = dict(self.entry, writer_pid=os.getpid(), started_at=time.time(),
                     writer_start_time=boot + int(stat[19]) / os.sysconf('SC_CLK_TCK'))
        self.write({'session-a': entry})
        proc = subprocess.Popen([sys.executable, str(MODULE), '--home', str(self.home), '--watch', '--interval', '0.05'],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(json.loads(proc.stdout.readline())['agents'][0]['status'], 'working')
            self.marker.unlink()
            self.assertEqual(json.loads(proc.stdout.readline())['agents'][0]['status'], 'idle')
            self.assertEqual(json.loads(proc.stdout.readline())['agents'], [])
        finally:
            proc.terminate()
            proc.communicate(timeout=3)


if __name__ == '__main__':
    unittest.main()
