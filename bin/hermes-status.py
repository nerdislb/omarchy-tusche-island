#!/usr/bin/env python3
"""Read-only Hermes Desktop/TUI turn snapshot for Tusche Island (Linux)."""
from contextlib import closing
from pathlib import Path
from functools import cache
import argparse
import json
import math
import os
import sqlite3
import time


@cache
def boot_time():
    for line in Path('/proc/stat').read_text().splitlines():
        if line.startswith('btime '):
            return float(line.split()[1])
    raise ValueError('Boot time unavailable')


def writer_alive(entry):
    """Tri-state PID + birth-time identity; unknown never earns a working badge."""
    pid, expected = entry.get('writer_pid'), entry.get('writer_start_time')
    if (not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0
            or not isinstance(expected, (int, float)) or isinstance(expected, bool)
            or not math.isfinite(expected) or expected <= 0):
        return None
    try:
        fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        if fields[0] in ('Z', 'X'):
            return False
        start = boot_time() + int(fields[19]) / os.sysconf('SC_CLK_TCK')
        return abs(start - expected) < 0.001
    except (FileNotFoundError, ProcessLookupError):
        return False
    except (OSError, ValueError, IndexError):
        return None


class Tracker:
    def __init__(self, home, *, writer_live=writer_alive, now=time.time):
        self.home = Path(home).resolve()
        self.writer_live = writer_live
        self.now = now
        self.previous = {}

    def poll(self):
        path = self.home / 'desktop' / 'interrupted_turns.json'
        try:
            entries = json.loads(path.read_text(encoding='utf-8'))
            if not isinstance(entries, dict):
                raise ValueError('Invalid marker root')
        except FileNotFoundError:
            entries = {}
        except (OSError, ValueError, UnicodeError):
            # Loss of observability must never masquerade as a completion.
            self.previous = {}
            return {'available': False, 'agents': []}
        agents = []
        current = {}
        titles = {}
        if entries:
            try:
                with closing(sqlite3.connect((self.home / 'state.db').as_uri() + '?mode=ro', uri=True, timeout=0.2)) as db:
                    for sid in entries:
                        row = db.execute('SELECT title FROM sessions WHERE id=?', (sid,)).fetchone()
                        if row and isinstance(row[0], str) and row[0]:
                            titles[sid] = row[0][:160]
            except sqlite3.Error:
                pass  # Optional display metadata; never create/repair the session DB.
        now = self.now()
        for sid, entry in entries.items():
            if not isinstance(entry, dict):
                continue
            started = entry.get('started_at')
            if (not isinstance(started, (int, float)) or isinstance(started, bool)
                    or not math.isfinite(started) or not 0 <= now - started <= 86400
                    or self.writer_live(entry) is not True):
                continue
            previous = self.previous.get(sid)
            agent = {'pane': 'hermes:' + sid, 'agent': 'Hermes',
                     'title': titles.get(sid, previous[1]['title'] if previous else 'Hermes'),
                     'status': 'working'}
            agents.append(agent)
            current[sid] = (entry, agent)
        for sid, (entry, agent) in self.previous.items():
            if sid not in entries and self.writer_live(entry) is True:
                agents.append(dict(agent, status='idle'))
        self.previous = current
        return {'available': True, 'agents': agents}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', type=Path, default=Path(os.environ.get('HERMES_HOME') or Path.home() / '.hermes'))
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--interval', type=float, default=2.0)
    args = parser.parse_args()
    if not math.isfinite(args.interval) or args.interval < 0.05:
        parser.error('--interval must be finite and at least 0.05 seconds')
    tracker = Tracker(args.home.expanduser())
    while True:
        print(json.dumps(tracker.poll(), ensure_ascii=False), flush=True)
        if not args.watch:
            return
        time.sleep(args.interval)


if __name__ == '__main__':
    main()
