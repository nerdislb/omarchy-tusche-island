#!/usr/bin/env python3
"""Herdr desktop app agents for Tusche Island, from herdr-core (`hc`).

The Herdr app runs its terminals and agents in herdr-core, not in the older
Herdr TUI server that Flux reads. This collector subscribes to core fact events and prints live terminals
in the same form as the one-shot `hc ls --json` path:

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
import select
import socket
import shutil
import subprocess
import sys
import time
from pathlib import Path

ADDRESS = re.compile(r'^(?:[A-Za-z0-9._-]{1,40}/)?t[0-9]{1,12}$')
STATUS = {'working': 'working', 'blocked': 'blocked', 'error': 'blocked', 'idle': 'idle', 'done': 'idle'}
HEARTBEAT = 3.0   # repeat an unchanged snapshot at least this often
CORE_TIMEOUT = 45.0  # three missing core heartbeats invalidate a connection
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
    return agent_snapshot(items)


def agent_snapshot(items):
    """Shared filtering for CLI rows and normalized subscription records."""
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


def socket_path():
    """Resolve the Unix endpoint without starting core or invoking its CLI."""
    if os.environ.get('HC_SOCKET'):
        return os.environ['HC_SOCKET']
    config_home = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    try:
        import tomllib
        config = tomllib.loads((config_home / 'herdr-core/config.toml').read_text())
        if isinstance(config.get('socket'), str) and config['socket']:
            return config['socket']
    except (OSError, ValueError, ImportError):
        pass
    session = os.environ.get('HC_SESSION', '').strip() or 'default'
    if session in {'.', '..'} or any(ord(c) < 32 or ord(c) == 127 or c in '/\\:*?"<>|' for c in session):
        raise ValueError('Invalid HC_SESSION')
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    if runtime:
        folder = Path(runtime) / 'herdr-core'
    elif Path(f'/run/user/{os.getuid()}').is_dir():
        folder = Path(f'/run/user/{os.getuid()}/herdr-core')
    else:
        folder = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'herdr-core' / session
    return str(folder / (session + '.sock'))


def cli_record(record):
    """Mirror hc 0.1.18's cli/output.rs::short before the existing filter."""
    status = record.get('status') or {}
    argv = record.get('argv') or []
    program = argv[0] if argv else ''
    agent = status.get('app', program.rsplit('/', 1)[-1])
    return dict(record, agent=agent, status=status.get('state'),
                where=record.get('labels', {}).get('where'))


def machine_order(path):
    """CLI lists remote groups in configured order; subscription mirrors do not."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as core:
        core.settimeout(1.0)
        core.connect(path)
        core.sendall(b'{"jsonrpc":"2.0","id":2,"method":"machine.list","params":{}}\n')
        buffer = b''
        deadline = time.monotonic() + 1.0
        while b'\n' not in buffer:
            core.settimeout(max(0.001, deadline - time.monotonic()))
            chunk = core.recv(65536)
            if not chunk or time.monotonic() > deadline or len(buffer) + len(chunk) > 1024 * 1024:
                raise ValueError('Invalid machine list response')
            buffer += chunk
    reply = json.loads(buffer.split(b'\n', 1)[0])
    return [m['name'] for m in reply['result']['machines']]


class EventState:
    """The unfiltered subscription's records and sequence fence."""
    def __init__(self):
        self.seq = None
        self.terminals = {}

    def feed(self, message):
        if not isinstance(message, dict) or 'error' in message:
            raise ValueError('Invalid core response')
        method = message.get('method')
        if self.seq is None:
            if message.get('id') != 1 or not isinstance(message.get('result'), dict):
                raise ValueError('Expected subscription snapshot')
            data = message['result']
        else:
            if method not in {'event', 'missed', 'heartbeat'}:
                raise ValueError('Unexpected core notification')
            data = message.get('params')
        if not isinstance(data, dict) or type(data.get('seq')) is not int or data['seq'] < 0:
            raise ValueError('Invalid core sequence')
        seq = data['seq']
        if self.seq is None or method == 'missed':
            if self.seq is not None and seq < self.seq:
                return
            records = data.get('terminals')
            if not isinstance(records, list):
                raise ValueError('Invalid core snapshot')
            self.terminals = {r['address']: dict(r) for r in records
                              if isinstance(r, dict) and isinstance(r.get('address'), str)
                              and ADDRESS.match(r['address'])}
            self.seq = seq
            return
        if method == 'heartbeat':
            if seq > self.seq:
                raise ValueError('Core sequence gap')
            return
        if seq <= self.seq:
            return
        if seq != self.seq + 1:
            # Unfiltered streams include every sequence. Reconnect for a fresh
            # atomic snapshot if a peer omits facts without sending missed.
            raise ValueError('Core sequence gap')
        self.seq = seq
        kind, address, delta = data.get('type'), data.get('terminal'), data.get('data')
        if kind in {'created', 'restarted'}:
            if isinstance(delta, dict) and isinstance(delta.get('address'), str) and ADDRESS.match(delta['address']):
                self.terminals[delta['address']] = dict(delta)
        elif kind == 'removed':
            self.terminals.pop(address, None)
        elif kind == 'labels' and isinstance(delta, dict) and isinstance(delta.get('record'), dict):
            record = delta['record']
            if isinstance(record.get('address'), str) and ADDRESS.match(record['address']):
                self.terminals[record['address']] = dict(record)
        elif address in self.terminals:
            record = self.terminals[address]
            if kind == 'foreground':
                record['foreground'] = delta
            elif isinstance(delta, dict):
                fields = {'status': ('status', 'records', 'reported'), 'title': ('title',),
                          'labels': ('labels',), 'keep': ('keep',), 'turn': ('turn',),
                          'size': ('cols', 'rows'),
                          'lost': ('reason', 'exit_code', 'signal', 'finished_ms'),
                          'finished': ('reason', 'exit_code', 'signal', 'finished_ms')}
                for key in fields.get(kind, ()):
                    record[key] = delta.get(key)
                if kind in {'lost', 'finished'}:
                    record.pop('foreground', None)
                if kind == 'lost':
                    record['pid'] = None
                if kind == 'finished':
                    record['state'] = 'finished'

    def snapshot(self, machines=None):
        # Local records are a u32 BTreeMap in core; creation events must insert
        # before remote records, including after LIMIT was already reached.
        local = sorted((r for a, r in self.terminals.items() if '/' not in a),
                       key=lambda r: int(r['address'][1:]))
        remote = [r for a, r in self.terminals.items() if '/' in a]
        if machines is not None:
            rank = {name: index for index, name in enumerate(machines)}
            remote.sort(key=lambda r: (rank.get(r['address'].split('/')[0], len(rank)),
                                       int(r['address'].split('/')[1][1:])))
        return agent_snapshot([cli_record(r) for r in local + remote])


def encode(snap):
    return json.dumps(snap, sort_keys=True, separators=(',', ':'))


def watch(once=False):
    if once:
        raw = run_ls()
        print(encode(snapshot(raw)), flush=True)
        return
    unavailable = {'available': False, 'agents': []}
    last, sent = None, 0.0

    def emit(snap):
        nonlocal last, sent
        line, now = encode(snap), time.monotonic()
        if line != last or now - sent >= HEARTBEAT:
            print(line, flush=True)
            last, sent = line, now

    delay = 1.0
    while True:
        state = EventState()
        remote_names, machines = set(), []
        current = unavailable
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as core:
                core.settimeout(1.0)
                path = socket_path()
                core.connect(path)
                core.sendall(b'{"jsonrpc":"2.0","id":1,"method":"events.subscribe","params":{}}\n')
                buffer = b''
                deadline = time.monotonic() + 5.0
                while True:
                    now = time.monotonic()
                    if now >= deadline:
                        raise TimeoutError('Core subscription timed out')
                    wait = min(max(0.0, sent + HEARTBEAT - now), deadline - now) if last else deadline - now
                    if select.select([core], [], [], wait)[0]:
                        chunk = core.recv(65536)
                        if not chunk:
                            raise EOFError('Core subscription closed')
                        buffer += chunk
                        if len(buffer) > 16 * 1024 * 1024:
                            raise ValueError('Core message too large')
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            message = json.loads(line)
                            state.feed(message)
                            deadline = time.monotonic() + CORE_TIMEOUT
                            delay = 1.0
                            names = {a.split('/')[0] for a in state.terminals if '/' in a}
                            if names != remote_names:
                                # One metadata read on remote topology changes,
                                # never on a timer or an ordinary status event.
                                machines = machine_order(path) if names else []
                                remote_names = names
                            if message.get('method') != 'heartbeat':
                                current = state.snapshot(machines)
                            emit(current)
                    if state.seq is not None:
                        emit(current)
                    elif last:
                        emit(unavailable)
        except (OSError, EOFError, ValueError, TypeError, KeyError):
            emit(unavailable)
        retry = time.monotonic() + delay
        delay = min(delay * 2, 30.0)
        while True:
            now = time.monotonic()
            if now >= retry:
                break
            time.sleep(min(retry - now, max(0.0, sent + HEARTBEAT - now)))
            emit(unavailable)


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
