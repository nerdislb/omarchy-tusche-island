import base64
import http.server
import importlib.util
import json
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('opencode_status', Path(__file__).parents[1] / 'bin/opencode-status.py')
o = importlib.util.module_from_spec(spec)
spec.loader.exec_module(o)

INFO = {
    'ses_root': {'id': 'ses_root', 'title': 'Bar fix', 'location': {'directory': '/home/me/src'}},
    'ses_child': {'id': 'ses_child', 'parentID': 'ses_root', 'title': 'explore'},
    'ses_other': {'id': 'ses_other', 'title': '<b>$(touch /tmp/x)</b>', 'outcome': 'succeeded'},
}


def ev(kind, **data):
    return {'type': kind, 'data': data}


class Clock:
    def __init__(self): self.t = 1000.0
    def __call__(self): return self.t


def tracker(active=None):
    clock = Clock()
    t = o.Tracker(service={'url': 'http://127.0.0.1:1', 'auth': ''}, clock=clock)
    t.fetch = lambda sid: dict(INFO.get(sid, {}))
    with patch.object(o, 'get_json', return_value=active or {}):
        t.handle(ev('server.connected'))
    return t, clock


def states(t):
    return {a['pane']: a['status'] for a in t.snapshot()['agents']}


class RegistrationTests(unittest.TestCase):
    def write(self, data):
        f = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False)
        json.dump(data, f); f.close()
        return Path(f.name)

    def test_local_service_with_basic_auth(self):
        reg = o.registration(self.write({'url': 'http://127.0.0.1:49374', 'password': 'pw'}))
        self.assertEqual(reg['url'], 'http://127.0.0.1:49374')
        self.assertEqual(base64.b64decode(reg['auth'].split()[1]).decode(), 'opencode:pw')

    def test_never_sends_the_password_elsewhere(self):
        for url in ('http://example.com:80', 'https://127.0.0.1:1', 'http://127.0.0.1:1/x', 'file:///etc/passwd'):
            self.assertIsNone(o.registration(self.write({'url': url, 'password': 'pw'})), url)

    def test_missing_broken_or_dead(self):
        self.assertIsNone(o.registration(Path('/nonexistent/service.json')))
        self.assertIsNone(o.registration(self.write(['x'])))
        dead = subprocess.Popen(['true']); dead.wait()
        self.assertIsNone(o.registration(self.write({'url': 'http://127.0.0.1:1', 'password': 'pw', 'pid': dead.pid})))


class EventTests(unittest.TestCase):
    def test_server_sent_events(self):
        lines = [b': heartbeat\n', b'\n', b'data: {"type":"a",\n', b'data: "data":{}}\n', b'\n', b'data: nope\n', b'\n',
                 b'data: {"type":"b"}\r\n', b'\r\n']
        self.assertEqual([e['type'] for e in o.events(lines)], ['a', 'b'])


class TrackerTests(unittest.TestCase):
    def test_unavailable_until_connected(self):
        t = o.Tracker(service={'url': 'http://127.0.0.1:1'})
        self.assertEqual(t.snapshot(), {'available': False, 'agents': []})

    def test_a_run_and_its_end(self):
        t, _ = tracker()
        self.assertEqual(t.snapshot(), {'available': True, 'agents': []})
        t.handle(ev('session.execution.started', sessionID='ses_root'))
        agent = t.snapshot()['agents'][0]
        self.assertEqual(agent, {'pane': 'opencode:ses_root', 'source': 'opencode', 'agent': 'OpenCode', 'title': 'Bar fix',
                                 'status': 'working', 'directory': '/home/me/src'})
        t.handle(ev('session.renamed', sessionID='ses_root', title='Bar fixed'))
        t.handle(ev('session.execution.succeeded', sessionID='ses_root'))
        self.assertEqual(t.snapshot()['agents'][0]['status'], 'idle')
        self.assertEqual(t.snapshot()['agents'][0]['title'], 'Bar fixed')
        for end in ('failed', 'interrupted'):
            t.handle(ev('session.execution.started', sessionID='ses_root'))
            t.handle(ev('session.execution.' + end, sessionID='ses_root'))
            self.assertEqual(states(t), {'opencode:ses_root': 'unknown'}, end)  # never announced as finished

    def test_waiting_for_the_user_counts_for_the_top_session(self):
        t, _ = tracker()
        t.handle(ev('session.execution.started', sessionID='ses_root'))
        t.handle(ev('session.execution.started', sessionID='ses_child'))   # a subagent is not its own agent
        t.handle(ev('permission.asked', id='per_1', sessionID='ses_child'))
        self.assertEqual(states(t), {'opencode:ses_root': 'blocked'})
        t.handle(ev('form.created', form={'id': 'frm_1', 'sessionID': 'ses_root'}))
        t.handle(ev('permission.replied', requestID='per_1', sessionID='ses_child'))
        self.assertEqual(states(t), {'opencode:ses_root': 'blocked'})
        t.handle(ev('form.cancelled', id='frm_1', sessionID='ses_root'))
        self.assertEqual(states(t), {'opencode:ses_root': 'working'})
        t.handle(ev('session.execution.succeeded', sessionID='ses_child'))
        self.assertEqual(states(t), {'opencode:ses_root': 'working'})

    def test_unknown_sessions_appear_only_by_starting_or_asking(self):
        t, _ = tracker()
        for e in (ev('session.renamed', sessionID='ses_root', title='x'), ev('session.execution.succeeded', sessionID='ses_root'),
                  ev('permission.replied', sessionID='ses_root', requestID='p'), ev('session.execution.started', sessionID='bad id'),
                  ev('session.execution.started', sessionID=['ses_root']), {'type': 'session.execution.started', 'data': 'x'}):
            t.handle(e)
        self.assertEqual(t.snapshot()['agents'], [])

    def test_finished_sessions_leave_and_come_back(self):
        t, clock = tracker()
        t.handle(ev('session.execution.started', sessionID='ses_root'))
        t.handle(ev('session.execution.succeeded', sessionID='ses_root'))
        clock.t += o.KEEP + 1
        self.assertEqual(t.snapshot()['agents'], [])
        t.handle(ev('session.execution.started', sessionID='ses_root'))
        self.assertEqual(states(t), {'opencode:ses_root': 'working'})
        t.handle(ev('session.deleted', sessionID='ses_root'))
        self.assertEqual(t.snapshot()['agents'], [])

    def test_reconnect_takes_what_runs_now(self):
        t, _ = tracker(active={'ses_root': {'type': 'running'}, 'ses_child': {'type': 'running'}})
        self.assertEqual(states(t), {'opencode:ses_root': 'working'})
        t.handle(ev('session.execution.started', sessionID='ses_other'))
        with patch.object(o, 'get_json', return_value={}):
            t.handle(ev('server.connected'))
        # finished while away: only a recorded success counts as idle
        self.assertEqual(states(t), {'opencode:ses_root': 'unknown', 'opencode:ses_other': 'idle'})
        self.assertTrue(t.snapshot()['agents'][1]['title'].startswith('<b>'))  # shown as PlainText in QML


class ServiceTests(unittest.TestCase):
    """The real HTTP path: auth, the filtered stream, events in order."""

    def test_stream_from_a_local_service(self):
        seen = {}

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args): pass

            def reply(self, data):
                body = json.dumps(data).encode()
                self.send_response(200); self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)

            def do_GET(self):
                if self.headers.get('Authorization') != 'Basic ' + base64.b64encode(b'opencode:pw').decode():
                    self.send_response(401); self.end_headers(); return
                if self.path.startswith('/api/event?'):
                    seen['query'] = self.path
                    self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
                    for e in (ev('server.connected'), ev('session.execution.started', sessionID='ses_root'),
                              ev('session.execution.succeeded', sessionID='ses_root')):
                        self.wfile.write(b': heartbeat\n\ndata: ' + json.dumps(e).encode() + b'\n\n'); self.wfile.flush()
                        time.sleep(0.3)
                    time.sleep(1)
                elif self.path == '/api/session/active':
                    self.reply({'location': {'directory': '/'}, 'data': {}})
                elif self.path.startswith('/api/session/'):
                    self.reply({'data': INFO.get(self.path.rsplit('/', 1)[1], {})} if 'root' in self.path else {})
                else:
                    self.send_response(404); self.end_headers()

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        service = {'url': 'http://127.0.0.1:%d' % server.server_address[1],
                   'auth': 'Basic ' + base64.b64encode(b'opencode:pw').decode()}
        t = o.Tracker()
        threading.Thread(target=t.run, kwargs={'registry': lambda: service, 'sleep': lambda s: time.sleep(5)}, daemon=True).start()
        statuses = []
        for _ in range(60):
            snap = t.snapshot()
            if snap['agents'] and (not statuses or statuses[-1] != snap['agents'][0]['status']):
                statuses.append(snap['agents'][0]['status'])
            if statuses[-1:] == ['idle']:
                break
            time.sleep(0.05)
        server.shutdown()
        self.assertEqual(statuses, ['working', 'idle'])
        self.assertEqual(t.snapshot()['agents'][0]['title'], 'Bar fix')
        self.assertIn('types=session.execution.started', seen['query'])
        self.assertNotIn('delta', seen['query'])


class FocusTests(unittest.TestCase):
    windows = [{'id': 'a1', 'title': 'OC | Bar fix'}, {'id': 'b2', 'title': 'OC | Other'}, {'id': 'c3', 'title': 'Zen'}]

    def focus(self, windows, title='Bar fix'):
        with patch.dict(o.os.environ, {'UMBRIEL_SOCKET': '/run/test.sock'}), \
                patch.object(o, 'registration', return_value={'url': 'http://127.0.0.1:1', 'auth': ''}), \
                patch.object(o, 'get_json', return_value={'title': title}), \
                patch.object(o, 'run_json', return_value=windows), patch.object(o.subprocess, 'run') as run:
            return o.focus('ses_root'), run

    def test_its_own_window_else_the_only_one(self):
        code, run = self.focus(self.windows)
        self.assertEqual((code, run.call_args.args[0]), (0, ['umbriel', 'msg', 'window-focus:a1']))
        code, run = self.focus([self.windows[1], self.windows[2]])
        self.assertEqual((code, run.call_args.args[0]), (0, ['umbriel', 'msg', 'window-focus:b2']))

    def test_never_guesses_or_runs_untrusted_ids(self):
        code, run = self.focus([self.windows[1], {'id': 'd4', 'title': 'OC | Third'}])
        self.assertEqual(code, 1); run.assert_not_called()
        code, run = self.focus([{'id': 'a1; rm -rf ~', 'title': 'OC | Bar fix'}])
        self.assertEqual(code, 1); run.assert_not_called()
        with patch.object(o, 'run_json') as read:
            self.assertEqual(o.focus('ses_x; touch /tmp/no'), 1); read.assert_not_called()


if __name__ == '__main__': unittest.main()
