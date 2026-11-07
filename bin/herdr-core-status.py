#!/usr/bin/env python3
"""Herdr desktop app agents for Tusche Island, from herdr-core (`hc`).

The Herdr app runs its terminals and agents in herdr-core, not in the older
Herdr TUI server that Flux reads. This collector asks `hc ls --json` for the
live terminals that report an agent and prints one snapshot per line:

  {"available": true, "agents": [{"pane": "hc:t4", "source": "herdr-core",
   "agent": "pi", "title": "~ / Codex", "status": "working", "directory": "/home/x"}]}

status: working, blocked (needs you), idle (idle or done), unknown.
Only addresses, agent names, tab labels and folders leave herdr-core; it never
reads a terminal's screen. A snapshot is repeated every few seconds so the
island's watchdog can tell a quiet core from a stuck collector.

  herdr-core-status.py --watch          follow changes (the island runs this)
  herdr-core-status.py --once           print one snapshot
  herdr-core-status.py --focus t4       show that terminal in the Herdr app
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ADDRESS = re.compile(r'^(?:[A-Za-z0-9._-]{1,40}/)?t[0-9]{1,12}$')
STATUS = {'working': 'working', 'blocked': 'blocked', 'error': 'blocked', 'idle': 'idle', 'done': 'idle'}
POLL = 1.5        # seconds between `hc ls`
HEARTBEAT = 3.0   # repeat an unchanged snapshot at least this often
LIMIT = 64


def text(value, limit=180):
    return value[:limit] if isinstance(value, str) else ''


def hc_path():
    for candidate in (shutil.which('hc'), str(Path.home() / '.local/bin/hc')):
        if candidate and os.access(candidate, os.X_OK):
            return candidate
    return None


def snapshot(raw):
    """The island's agent list from `hc ls --json` output."""
    try:
        data = json.loads(raw)
    except (TypeError, ValueError):
        return {'available': False, 'agents': []}
    items = data.get('terminals') if isinstance(data, dict) else None
    if not isinstance(items, list):
        return {'available': False, 'agents': []}
    agents = []
    for t in items:
        if not isinstance(t, dict) or t.get('state') != 'live' or not t.get('agent'):
            continue
        address = t.get('address')
        if not isinstance(address, str) or not ADDRESS.match(address):
            continue
        agents.append({
            'pane': f'hc:{address}',
            'source': 'herdr-core',
            'agent': text(t.get('agent'), 40),
            'title': text(t.get('where') or t.get('name') or t.get('agent'), 120),
            'status': STATUS.get(t.get('status'), 'unknown'),
            'directory': text(t.get('cwd'), 400),
        })
        if len(agents) >= LIMIT:
            break
    return {'available': True, 'agents': agents}


def run_ls():
    hc = hc_path()
    if not hc:
        return None
    try:
        r = subprocess.run([hc, 'ls', '--json'], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


def watch(once=False):
    last, sent = None, 0.0
    while True:
        raw = run_ls()
        snap = snapshot(raw) if raw is not None else {'available': False, 'agents': []}
        line = json.dumps(snap, sort_keys=True, separators=(',', ':'))
        now = time.monotonic()
        if line != last or now - sent >= HEARTBEAT:
            print(line, flush=True)
            last, sent = line, now
        if once:
            return
        time.sleep(POLL)


def focus(address):
    """Show a terminal in the app: pick its pane, then raise the app's window."""
    if not ADDRESS.match(address or ''):
        return 2
    app = shutil.which('herdr-app') or str(Path.home() / '.local/bin/herdr-app')
    done = subprocess.run([app, 'do', 'agent.focus', '--terminal', address], capture_output=True, timeout=10)
    if shutil.which('umbriel') and os.environ.get('UMBRIEL_SOCKET'):
        try:
            wins = json.loads(subprocess.run(['umbriel', 'windows', '--json'], capture_output=True, text=True, timeout=5).stdout)
            wid = next((w['id'] for w in wins if w.get('app_id') == 'herdr-app'), '')
            if wid:
                subprocess.run(['umbriel', 'msg', f'window-focus:{wid}'], capture_output=True, timeout=5)
        except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError):
            pass
    return done.returncode


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument('--watch', action='store_true')
    g.add_argument('--once', action='store_true')
    g.add_argument('--focus', metavar='ADDRESS')
    a = p.parse_args()
    if a.focus:
        sys.exit(focus(a.focus))
    try:
        watch(once=a.once)
    except (KeyboardInterrupt, BrokenPipeError):
        pass


if __name__ == '__main__':
    main()
