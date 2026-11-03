#!/usr/bin/env python3
"""OpenCode sessions for Tusche Island, from the local service's event stream.

Reads the running service's registration (its loopback URL and password) and
subscribes to its event stream for just the events that change a session's
state: a run starting and ending, permission requests and questions, renames.
Never starts the service and never reads prompts or messages; only session
ids, titles and directories leave OpenCode. Prints one snapshot per line:

  {"available": true, "agents": [{"pane": "opencode:<id>", "source": "opencode",
   "agent": "OpenCode", "title": "...", "status": "working", "directory": "..."}]}

status: working (a run in progress), blocked (waiting for a permission or an
answer), idle (the last run succeeded), unknown (it failed or was stopped;
never announced as finished). Subagent sessions report to their top session.
"""
import argparse
import base64
import http.client
import json
import os
import re
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

SESSION = re.compile(r'ses_[A-Za-z0-9]{1,64}')
EVENTS = ('session.execution.started', 'session.execution.succeeded', 'session.execution.failed',
          'session.execution.interrupted', 'session.renamed', 'session.deleted', 'session.archived',
          'permission.asked', 'permission.replied', 'form.created', 'form.replied', 'form.cancelled')
KEEP = 600            # seconds a finished session stays listed
LIMIT = 64            # sessions listed at most
STREAM_TIMEOUT = 45   # seconds without a byte (three missed 15 s heartbeats): reconnect
MAX_BYTES = 4 * 1024 * 1024
LOOPBACK = {'127.0.0.1', 'localhost', '::1'}
WINDOW_PREFIX = 'OC | '   # the OpenCode TUI's terminal title: "OC | <session title>"
NETWORK_ERRORS = (OSError, ValueError, http.client.HTTPException)


def text(value, limit=180):
    return value[:limit] if isinstance(value, str) else ''


def registration_path():
    base = os.environ.get('XDG_STATE_HOME') or str(Path.home() / '.local/state')
    return Path(base) / 'opencode/service.json'


def registration(path=None):
    """The running service: {'url', 'auth'}, or None (not running, not local)."""
    try:
        data = json.loads((path or registration_path()).read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or not isinstance(data.get('url'), str):
        return None
    parts = urllib.parse.urlsplit(data['url'])
    # The password only ever goes to a service on this machine.
    if parts.scheme != 'http' or parts.hostname not in LOOPBACK or parts.path not in ('', '/'):
        return None
    pid = data.get('pid')
    if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return None
        except PermissionError:
            pass
    password = data.get('password')
    auth = 'Basic ' + base64.b64encode(('opencode:' + password).encode()).decode() if isinstance(password, str) else ''
    return {'url': data['url'].rstrip('/'), 'auth': auth}


def request(service, path, accept='application/json', timeout=3):
    req = urllib.request.Request(service['url'] + path, headers={'Accept': accept})
    if service.get('auth'):
        req.add_header('Authorization', service['auth'])
    return urllib.request.urlopen(req, timeout=timeout)


def get_json(service, path):
    with request(service, path) as reply:
        body = reply.read(MAX_BYTES + 1)
    if len(body) > MAX_BYTES:
        raise ValueError('Reply too large')
    data = json.loads(body)
    return data['data'] if isinstance(data, dict) and 'data' in data and 'id' not in data else data


def events(lines):
    """Server-sent events (JSON in `data:` lines) from a byte-line iterator."""
    data, size = [], 0
    for raw in lines:
        line = raw.decode('utf-8', 'replace').rstrip('\r\n')
        if line == '':
            if data:
                try:
                    event = json.loads('\n'.join(data))
                except ValueError:
                    event = None
                if isinstance(event, dict):
                    yield event
            data, size = [], 0
        elif line.startswith('data:'):
            size += len(line)
            if size > MAX_BYTES:
                raise ValueError('Event too large')
            data.append(line[5:].lstrip(' '))


class Tracker:
    """Session states from the event stream; one writer thread, read by snapshot()."""

    def __init__(self, service=None, clock=time.monotonic):
        self.service = service
        self.clock = clock
        self.lock = threading.Lock()
        self.available = False
        self.sessions = {}   # top session id -> state
        self.roots = {}      # session id -> its top session id

    def fetch(self, sid):
        try:
            info = get_json(self.service, '/api/session/' + sid)
        except NETWORK_ERRORS:
            return {}
        return info if isinstance(info, dict) else {}

    def root_of(self, sid, depth=0):
        """The top session a session belongs to (a subagent's parent), or None."""
        if not isinstance(sid, str) or not SESSION.fullmatch(sid):
            return None
        with self.lock:
            root = self.roots.get(sid)
            if root is not None and root in self.sessions:
                return root
        info = self.fetch(sid)
        parent = info.get('parentID')
        if isinstance(parent, str) and SESSION.fullmatch(parent) and parent != sid and depth < 8:
            root = self.root_of(parent, depth + 1)
        else:
            root = sid
            location = info.get('location') if isinstance(info.get('location'), dict) else {}
            with self.lock:
                self.sessions.setdefault(sid, {'title': text(info.get('title')), 'directory': text(location.get('directory'), 400),
                                               'running': False, 'final': None, 'changed': self.clock(), 'waits': set(),
                                               'listed': False})
        if root:
            with self.lock:
                self.roots[sid] = root
        return root

    def known(self, sid):
        with self.lock:
            return sid in self.roots

    def touch(self, sid, **values):
        with self.lock:
            s = self.sessions.get(sid)
            if s is not None:
                s.update(values)
                s['changed'] = self.clock()

    def wait(self, sid, key, on):
        with self.lock:
            s = self.sessions.get(sid)
            if s is not None:
                (s['waits'].add if on else s['waits'].discard)(key)
                s['listed'] = True
                s['changed'] = self.clock()

    def handle(self, event):
        kind = event.get('type')
        data = event.get('data') if isinstance(event.get('data'), dict) else {}
        if kind == 'server.connected':
            self.resync()
            return
        if kind in ('session.deleted', 'session.archived'):
            with self.lock:
                self.sessions.pop(data.get('sessionID'), None)
            return
        form = data.get('form') if kind == 'form.created' and isinstance(data.get('form'), dict) else {}
        sid = form.get('sessionID') if form else data.get('sessionID')
        # Only what starts work or waits for the user makes a session appear.
        if kind not in ('session.execution.started', 'permission.asked', 'form.created') and not self.known(sid):
            return
        root = self.root_of(sid)
        if not root:
            return
        own = root == sid
        if kind == 'session.execution.started' and own:
            self.touch(root, running=True, final=None, listed=True)
        elif kind in ('session.execution.succeeded', 'session.execution.failed', 'session.execution.interrupted') and own:
            self.touch(root, running=False, waits=set(), final='idle' if kind.endswith('succeeded') else 'unknown')
        elif kind == 'session.renamed' and own:
            title = text(data.get('title'))
            if title:
                self.touch(root, title=title)
        elif kind in ('permission.asked', 'permission.replied'):
            self.wait(root, 'permission:' + text(data.get('id') if kind == 'permission.asked' else data.get('requestID'), 80),
                      kind == 'permission.asked')
        elif kind in ('form.created', 'form.replied', 'form.cancelled'):
            self.wait(root, 'form:' + text(form.get('id') if form else data.get('id'), 80), kind == 'form.created')

    def resync(self):
        """On (re)connect: what runs now. Events during a gap are missed by contract."""
        active = get_json(self.service, '/api/session/active')
        running = set()
        for sid in (active if isinstance(active, dict) else {}):
            root = self.root_of(sid)
            if root:
                running.add(root)
        for root in running:
            self.touch(root, running=True, final=None, listed=True)
        with self.lock:
            stopped = [sid for sid, s in self.sessions.items() if s['running'] and sid not in running]
        for sid in stopped:
            # finished while we were away: only a recorded success counts
            outcome = self.fetch(sid).get('outcome')
            self.touch(sid, running=False, final='idle' if outcome == 'succeeded' else 'unknown')
        with self.lock:
            self.available = True

    def snapshot(self):
        with self.lock:
            if not self.available:
                return {'available': False, 'agents': []}
            now = self.clock()
            for sid in [sid for sid, s in self.sessions.items()
                        if not s['running'] and not s['waits'] and now - s['changed'] > KEEP]:
                del self.sessions[sid]
                for child in [c for c, r in self.roots.items() if r == sid]:
                    del self.roots[child]
            agents = []
            for sid, s in self.sessions.items():
                if not s['listed']:
                    continue
                status = 'blocked' if s['waits'] else 'working' if s['running'] else (s['final'] or 'unknown')
                agents.append({'pane': 'opencode:' + sid, 'source': 'opencode', 'agent': 'OpenCode',
                               'title': s['title'] or 'OpenCode session', 'status': status, 'directory': s['directory']})
            return {'available': True, 'agents': agents[-LIMIT:]}

    def set_unavailable(self):
        with self.lock:
            self.available = False

    def run(self, sleep=time.sleep, registry=registration):
        delay = 2
        while True:
            self.service = registry()
            if not self.service:
                self.set_unavailable()
                sleep(2)
                continue
            query = urllib.parse.urlencode([('types', t) for t in EVENTS])
            try:
                stream = request(self.service, '/api/event?' + query, accept='text/event-stream', timeout=STREAM_TIMEOUT)
            except NETWORK_ERRORS:
                self.set_unavailable()
                sleep(delay)
                delay = min(30, delay * 2)
                continue
            delay = 2
            try:
                with stream:
                    for event in events(stream):
                        try:
                            self.handle(event)
                        except (KeyError, TypeError, AttributeError):
                            pass  # an event of an unexpected shape changes nothing
            except TimeoutError:
                pass          # a quiet stream: reconnect and resync, still available
            except NETWORK_ERRORS:
                self.set_unavailable()
                sleep(delay)


def run_json(argv):
    with tempfile.TemporaryFile() as out:
        subprocess.run(argv, stdout=out, stderr=subprocess.DEVNULL, timeout=3, check=True)
        if out.tell() > MAX_BYTES:
            raise ValueError('Reply too large')
        out.seek(0)
        return json.load(out)


def pick_window(windows, title):
    """The OpenCode window for a session: its own title, else the only one."""
    titled = [w for w in windows if isinstance(w, dict) and isinstance(w.get('title'), str)]
    if title:
        exact = [w for w in titled if w['title'] == WINDOW_PREFIX + title]
        if len(exact) == 1:
            return exact[0]
    tuis = [w for w in titled if w['title'].startswith(WINDOW_PREFIX) or w['title'] in ('OC', 'OpenCode')]
    return tuis[0] if len(tuis) == 1 else None


def focus(sid):
    if not isinstance(sid, str) or not SESSION.fullmatch(sid):
        return 1
    title = ''
    service = registration()
    if service:
        try:
            info = get_json(service, '/api/session/' + sid)
            title = text(info.get('title')) if isinstance(info, dict) else ''
        except NETWORK_ERRORS:
            pass
    if os.environ.get('UMBRIEL_SOCKET'):
        window = pick_window(run_json(['umbriel', 'windows', '--json']), title)
        if not window or not re.fullmatch(r'[0-9a-fA-F]+', text(window.get('id'))):
            return 1
        subprocess.run(['umbriel', 'msg', 'window-focus:' + window['id']], check=True, timeout=3, stdout=subprocess.DEVNULL)
        return 0
    window = pick_window(run_json(['hyprctl', '-j', 'clients']), title)
    if not window or not re.fullmatch(r'0x[0-9a-fA-F]+', text(window.get('address'))):
        return 1
    subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.focus({ window = "address:' + window['address'] + '" })'],
                   check=True, timeout=3, stdout=subprocess.DEVNULL)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--watch', action='store_true', help='print a snapshot every two seconds')
    parser.add_argument('--focus', metavar='SESSION', help='raise the terminal showing this session')
    args = parser.parse_args()
    if args.focus:
        try:
            return focus(args.focus)
        except (OSError, ValueError, TypeError, subprocess.SubprocessError):
            return 1
    tracker = Tracker()
    threading.Thread(target=tracker.run, daemon=True).start()
    # A first snapshot as soon as the stream connected (or did not).
    for _ in range(20):
        if tracker.available:
            break
        time.sleep(0.1)
    while True:
        print(json.dumps(tracker.snapshot(), ensure_ascii=True), flush=True)
        if not args.watch:
            return 0
        time.sleep(2)


if __name__ == '__main__':
    raise SystemExit(main())
