#!/usr/bin/env python3
"""Capture flavor states in a private GLES Umbriel running the real shell.

No inherited Wayland, compositor or D-Bus connection is used. Only two
worktree plugins are installed, exclusively into the disposable HOME.
"""
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess as sp
import tempfile
import time
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OWNER = Path('/home/nerdi')
SHELL = Path(os.environ.get('SHELL_SRC', str(OWNER / 'Data/Development/projects/omarchy-umbriel-pixel-20261104')))
BAR = Path(os.environ.get('BAR_SRC', str(OWNER / 'Data/Development/projects/tusche-bar-pixel-20261104')))
ISLAND = Path(os.environ.get('ISLAND_SRC', str(ROOT)))
OUT = ROOT / 'docs/evidence/flavor'
OUT.mkdir(parents=True, exist_ok=True)
private = Path(tempfile.mkdtemp(prefix='island-flavor-', dir='/tmp'))
home, runtime = private / 'home', private / 'run'
processes, handles, captures = [], [], []
for p in [home / '.config/omarchy/plugins', home / '.local/state/omarchy', home / '.local/share', home / '.cache', runtime]:
    p.mkdir(parents=True, exist_ok=True)
runtime.chmod(0o700)
env = dict(HOME=str(home), USER='nerdi', LANG='C.UTF-8',
           PATH=f'{OWNER}/Data/Work/pixel-stil-2026-11-04/tools/stubbin:{SHELL}/bin:/usr/local/bin:/usr/bin:/bin',
           XDG_CONFIG_HOME=str(home / '.config'), XDG_STATE_HOME=str(home / '.local/state'),
           XDG_DATA_HOME=str(home / '.local/share'), XDG_CACHE_HOME=str(home / '.cache'),
           XDG_RUNTIME_DIR=str(runtime), OMARCHY_PATH=str(SHELL), XDG_CURRENT_DESKTOP='umbriel',
           DBUS_SYSTEM_BUS_ADDRESS=f'unix:path={private}/no-system-bus')


def command(args, extra=None):
    values = env | (extra or {})
    assert values['XDG_RUNTIME_DIR'].startswith('/tmp/island-flavor-')
    for k in ['XDG_RUNTIME_DIR', 'WAYLAND_DISPLAY', 'UMBRIEL_SOCKET', 'DBUS_SESSION_BUS_ADDRESS']:
        assert '/run/user/' not in values.get(k, '')
    return ['/usr/bin/env', '-i', *[f'{k}={v}' for k, v in values.items()], *map(str, args)]


def call(args, timeout=20):
    return sp.check_output(command(args), stderr=sp.STDOUT, timeout=timeout).decode()


def launch(args, name, extra=None):
    log = (private / name).open('wb')
    handles.append(log)
    p = sp.Popen(command(args, extra), stdout=log, stderr=sp.STDOUT, start_new_session=True)
    processes.append(p)
    return p


def ipc(*args):
    return call(['quickshell', 'ipc', '-p', SHELL / 'shell', 'call', 'tusche-island', *args]).strip()


def shot(name):
    start = time.monotonic()
    raw = sp.check_output(command(['grim', '-t', 'ppm', '-g', '630,0 660x310', '-']), timeout=20)
    Image.open(io.BytesIO(raw)).save(OUT / f'{name}.png')
    captures.append(dict(name=name, requested_at=start, completed_at=time.monotonic()))


def series(name, action, times):
    start = time.monotonic()
    action()
    for ms in times:
        delay = start + ms / 1000 - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        shot(f'{name}-{ms:04d}')
    for c in captures:
        if c['name'].startswith(name + '-'):
            c['elapsed_ms'] = round((c['requested_at'] - start) * 1000, 1)


try:
    # A copied palette and fonts; no account state, credentials or other plugins.
    current = home / '.local/state/omarchy/current'
    shutil.copytree(OWNER / '.local/state/omarchy/current', current, symlinks=False)
    (home / '.local/share/fonts').symlink_to(OWNER / '.local/share/fonts')
    if (OWNER / '.config/fontconfig').exists():
        shutil.copytree(OWNER / '.config/fontconfig', home / '.config/fontconfig')
    live = json.loads((OWNER / '.config/omarchy/shell.json').read_text())
    opts = next(x for x in live['bar']['layout']['center'] if x['id'] == 'nerdibeard.tusche-island')
    opts.update(look='dynamic', flavor='', monitor='primary', notifications=True, barMode=True,
                calendar=False, bluetooth=False, camera=False, charging=False, trackChange=False,
                recording=False, mic=False, omamail=False, flux=False, corgi=False, hermes=False,
                opencode=False, herdrCore=False, aiLimits=False, phone=False, timerSound=False)
    cfg = dict(version=live.get('version', 1), idle={}, plugins=[{'id': 'nerdibeard.tusche-bar', 'options': {'edge': 'none', 'motion': 'apple'}}],
               bar={'position': 'top', 'background': 'none', 'layout': {'left': [], 'center': [opts], 'right': [], 'tray': []}})
    config = home / '.config/omarchy/shell.json'
    config.write_text(json.dumps(cfg, indent=2))
    for src, name in [(BAR, 'nerdibeard.tusche-bar'), (ISLAND, 'nerdibeard.tusche-island')]:
        call(['python3', '-I', src / 'bin/install-generation.py', src, home / '.config/omarchy/plugins' / name, '--config', config])
    umcfg = private / 'umbriel.toml'
    umcfg.write_text('''[general]
autostart = []
show_cheatsheet = false
[output.HEADLESS-1]
mode = "1920x1080@60"
scale = 1.0
[colors]
background = "#17131d"
[appearance]
corner_radius = 0
[appearance.shadow]
enabled = false
[animation]
enabled = true
duration_ms = 1
''')
    for card in ['renderD129', 'renderD128']:
        um = launch(['umbriel', '-c', umcfg], f'umbriel-{card}.log',
                    dict(WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_LIBINPUT_NO_DEVICES='1',
                         WLR_RENDERER='gles2', WLR_RENDER_DRM_DEVICE=f'/dev/dri/{card}'))
        for _ in range(300):
            sockets = list(runtime.glob('umbriel-*.sock'))
            if sockets or um.poll() is not None:
                break
            time.sleep(0.05)
        if sockets:
            break
        um.wait(timeout=10)
    else:
        raise RuntimeError('Neither allowed GLES render node started')
    displays = [p.name for p in runtime.glob('wayland-*') if p.is_socket()]
    assert len(displays) == 1
    env.update(WAYLAND_DISPLAY=displays[0], UMBRIEL_SOCKET=str(sockets[0]))
    bus = sp.Popen(command(['dbus-daemon', '--session', '--nofork', '--print-address']), stdout=sp.PIPE, stderr=sp.DEVNULL, start_new_session=True)
    processes.append(bus)
    env['DBUS_SESSION_BUS_ADDRESS'] = bus.stdout.readline().decode().strip()
    shell = launch(['quickshell', '-n', '-p', SHELL / 'shell'], 'shell.log',
                   dict(QS_DISABLE_FILE_WATCHER='1', QS_NO_RELOAD_POPUP='1', QT_QPA_PLATFORM='wayland', QSG_RHI_BACKEND='opengl'))
    for _ in range(80):
        if shell.poll() is not None:
            raise RuntimeError('Shell exited')
        try:
            state = json.loads(ipc('state'))
            if state['dynamic'] is not None:
                break
        except (sp.SubprocessError, json.JSONDecodeError):
            pass
        time.sleep(0.5)
    else:
        raise RuntimeError('Dynamic island never became ready')
    time.sleep(3)
    states = {}
    for flavor in ['', 'funk', 'register', 'umbra', 'tusche']:
        label = flavor or 'default'
        print('Capturing', label, flush=True)
        ipc('demo', 'off')
        ipc('note', 'dismiss')
        ipc('set', 'flavor', flavor)
        time.sleep(1.5)
        shot(label + '-idle')
        ipc('demo', 'agents')
        time.sleep(1.2)
        shot(label + '-working')
        states[label] = json.loads(ipc('state'))
        series(label + '-done', lambda: ipc('demo', 'agentdone'), [90, 180, 260, 400, 650, 1000, 1500])
        ipc('alert', 'dismiss')
        time.sleep(1.5)
        shot(label + '-cleared')
        series(label + '-banner', lambda: ipc('demo', 'agentdone-banner'), [180, 400, 650, 1000, 1500])
        ipc('note', 'dismiss')
        ipc('demo', 'off')
        time.sleep(1.5)
    # A real working agent plus a second live capsule, then a merging banner.
    ipc('set', 'flavor', 'umbra')
    ipc('demo', 'agents')
    ipc('demo', 'timer')
    time.sleep(1.5)
    shot('umbra-minimal')
    series('umbra-merge', lambda: ipc('demo', 'notification'), [180, 300, 500, 1000])
    ipc('note', 'dismiss')
    ipc('demo', 'off')
    ipc('set', 'flavor', '')
    time.sleep(2)
    shot('default-restored')
    (OUT / 'states.json').write_text(json.dumps(states, indent=2))
    (OUT / 'captures.json').write_text(json.dumps(captures, indent=2))
    (OUT / 'isolation.json').write_text(json.dumps(dict(render_node=card, compositor_pid=um.pid, shell_pid=shell.pid,
        runtime=str(runtime), home=str(home), socket=env['UMBRIEL_SOCKET'], dbus=env['DBUS_SESSION_BUS_ADDRESS'],
        shell_source=str(SHELL), island_source=str(ISLAND), bar_source=str(BAR)), indent=2))
finally:
    for p in reversed(processes):
        if p.poll() is None:
            os.killpg(p.pid, signal.SIGTERM)
            try:
                p.wait(timeout=5)
            except sp.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL)
                p.wait(timeout=5)
    for h in handles:
        h.close()
    for f in private.glob('*.log'):
        shutil.copy2(f, OUT / f.name)
    shutil.rmtree(private)
    (OUT / 'cleanup.json').write_text(json.dumps(dict(root=str(private), removed=not private.exists(),
        owned_pids=[p.pid for p in processes], all_reaped=all(p.poll() is not None for p in processes)), indent=2))
