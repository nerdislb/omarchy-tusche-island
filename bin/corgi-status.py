#!/usr/bin/env python3
"""Local Corgi snapshots for Tusche Island; never starts a runtime."""
import argparse
import json
import os
import re
import subprocess
import tempfile
import time

MAX_BYTES = 8 * 1024 * 1024


def run_json(argv):
    # Bound memory even when a daemon has a large session history.
    with tempfile.TemporaryFile() as out:
        subprocess.run(argv, stdout=out, stderr=subprocess.DEVNULL, timeout=3, check=True)
        if out.tell() > MAX_BYTES:
            raise ValueError('Snapshot too large')
        out.seek(0)
        return json.load(out)


def text(value, limit=180):
    return value[:limit] if isinstance(value, str) else ''


def positive(value):
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def snapshot(reply):
    if not isinstance(reply, dict) or reply.get('ok') is not True:
        raise ValueError('Unavailable')
    result = reply.get('result')
    if not isinstance(result, dict) or not isinstance(result.get('panes'), list):
        raise ValueError('Invalid snapshot')
    agents = []
    for pane in result['panes'][:256]:
        if not isinstance(pane, dict) or pane.get('exited') or pane.get('dormant'):
            continue
        agent = pane.get('agent')
        pid = pane.get('pane')
        if not positive(pid) or not isinstance(agent, dict) or not agent.get('provider'):
            continue
        state = agent.get('state')
        attention = agent.get('attention')
        # Unknown/lost states cannot earn a completion transition.
        status = ('blocked' if state == 'blocked' or attention in ('needs_input', 'needs_approval')
                  else 'working' if state == 'working'
                  else 'idle' if state in ('done', 'idle') else 'unknown')
        agents.append({'pane': 'corgi:' + str(pid), 'source': 'corgi',
                       'agent': text(agent.get('provider'), 40).capitalize(),
                       'title': text(agent.get('name')) or text(agent.get('activity')) or 'Corgi agent',
                       'activity': text(agent.get('activity')), 'status': status,
                       'session': text(agent.get('session'), 160),
                       'conversation': agent.get('conversation'),
                       'workspace': pane.get('workspace'), 'tab': pane.get('tab')})
    return {'available': True, 'agents': agents}


def poll():
    try:
        return snapshot(run_json(['corgi', 'list', '--json']))
    except (OSError, ValueError, subprocess.SubprocessError, TypeError):
        return {'available': False, 'agents': []}


def focus(pane_id):
    if not re.fullmatch(r'[1-9][0-9]{0,12}', pane_id):
        return 1
    reply = run_json(['corgi', 'list', '--json'])
    if not isinstance(reply, dict) or reply.get('ok') is not True:
        return 1
    panes = [p for p in reply['result']['panes'] if isinstance(p, dict)
             and p.get('pane') == int(pane_id) and not p.get('exited') and not p.get('dormant')
             and positive(p.get('workspace'))]
    if len(panes) != 1:
        return 1
    viewers = [v for v in reply.get('viewers', []) if isinstance(v, dict)
               and positive(v.get('id')) and positive(v.get('workspace'))]
    candidates = [v for v in viewers if v.get('workspace') == panes[0].get('workspace')]
    # Never guess between two viewers. A single attached viewer can switch workspaces.
    if len(candidates) != 1:
        candidates = viewers if len(viewers) == 1 else []
    if len(candidates) != 1 or not positive(candidates[0].get('id')):
        return 1
    subprocess.run(['corgi', 'focus', pane_id, '--viewer', str(candidates[0]['id'])],
                   check=True, timeout=3, stdout=subprocess.DEVNULL)
    # This desktop hosts Corgi inside a terminal. Raise only an unambiguous window.
    if os.environ.get('UMBRIEL_SOCKET'):
        clients = run_json(['umbriel', 'windows', '--json'])
        windows = [c for c in clients if isinstance(c, dict) and text(c.get('title')).casefold() == 'corgi']
        if len(windows) == 1 and re.fullmatch(r'[0-9a-fA-F]+', text(windows[0].get('id'))):
            subprocess.run(['umbriel', 'msg', 'window-focus:' + windows[0]['id']],
                           check=True, timeout=3, stdout=subprocess.DEVNULL)
        return 0
    clients = run_json(['hyprctl', '-j', 'clients'])
    windows = [c for c in clients if isinstance(c, dict) and text(c.get('title')).casefold() == 'corgi']
    if len(windows) == 1 and re.fullmatch(r'0x[0-9a-fA-F]+', windows[0].get('address', '')):
        subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.focus({ window = "address:' + windows[0]['address'] + '" })'],
                       check=True, timeout=3, stdout=subprocess.DEVNULL)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--focus')
    args = parser.parse_args()
    if args.focus:
        try:
            return focus(args.focus)
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
            return 1
    while True:
        print(json.dumps(poll(), ensure_ascii=True), flush=True)
        if not args.watch:
            return 0
        time.sleep(2)


if __name__ == '__main__':
    raise SystemExit(main())
