#!/usr/bin/env python3
"""Verify collector replacement on immutable URL changes in private Quickshell.

Uses the real Desktop.qml with other sources disabled, a private headless GLES
Umbriel and an absent core socket. It exercises the Loader URL transition used by
shell.syncPanelEntries, without touching the owner's session or configuration.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess as sp
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/evidence/events'


def run():
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ['quickshell.log', 'renderD129.log', 'renderD128.log']:
        (OUT / ('reload-' + name)).unlink(missing_ok=True)
    private = Path(tempfile.mkdtemp(prefix='island-events-reload-', dir='/tmp'))
    processes, logs, saved_children = [], [], set()
    env = dict(HOME=str(private / 'home'), PATH='/usr/local/bin:/usr/bin:/bin', LANG='C.UTF-8',
               XDG_RUNTIME_DIR=str(private / 'run'), XDG_CONFIG_HOME=str(private / 'config'),
               XDG_STATE_HOME=str(private / 'state'), XDG_DATA_HOME=str(private / 'data'),
               XDG_CACHE_HOME=str(private / 'cache'), HC_SOCKET=str(private / 'absent.sock'),
               QS_DISABLE_FILE_WATCHER='1', QS_NO_RELOAD_POPUP='1',
               QT_QPA_PLATFORMTHEME='basic', QSG_RHI_BACKEND='opengl')
    for key in ['HOME', 'XDG_RUNTIME_DIR', 'XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME']:
        Path(env[key]).mkdir(mode=0o700, parents=True, exist_ok=True)

    def launch(args, name, extra=None):
        file = (private / name).open('w')
        logs.append(file)
        proc = sp.Popen(['/usr/bin/env', '-i', *[f'{key}={value}' for key, value in (env | (extra or {})).items()],
                         *map(str, args)], stdout=file, stderr=sp.STDOUT)
        processes.append(proc)
        return proc

    def children(pid):
        path = Path(f'/proc/{pid}/task/{pid}/children')
        return [int(value) for value in path.read_text().split()] if path.exists() else []

    def collectors(pid):
        found = []
        for child in children(pid):
            try:
                args = Path(f'/proc/{child}/cmdline').read_bytes().split(b'\0')
            except FileNotFoundError:
                continue
            if any(arg.endswith(b'/bin/herdr-core-status.py') for arg in args):
                saved_children.add(child)
                found.append(dict(pid=child, argv=[arg.decode() for arg in args if arg]))
        return found

    result = dict(collector_sha256=hashlib.sha256((ROOT / 'bin/herdr-core-status.py').read_bytes()).hexdigest(),
                  desktop_sha256=hashlib.sha256((ROOT / 'sources/Desktop.qml').read_bytes()).hexdigest())
    try:
        # Two immutable source URLs with identical code. Both carry the real
        # collector. The installed generation test separately verifies publishing.
        for name in ['generation-a', 'generation-b']:
            folder = private / name
            (folder / 'sources').mkdir(parents=True)
            (folder / 'bin').mkdir()
            shutil.copy2(ROOT / 'sources/Desktop.qml', folder / 'sources/Desktop.qml')
            shutil.copy2(ROOT / 'IslandModel.js', folder / 'IslandModel.js')
            shutil.copy2(ROOT / 'bin/herdr-core-status.py', folder / 'bin/herdr-core-status.py')
        config = private / 'umbriel.toml'
        config.write_text('[general]\nautostart = []\nshow_cheatsheet = false\n[output.HEADLESS-1]\nmode = "1280x720@60"\nscale = 1.0\n')
        runtime = Path(env['XDG_RUNTIME_DIR'])
        for card in ['renderD129', 'renderD128']:
            compositor = launch(['umbriel', '-c', config], f'{card}.log',
                                dict(WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_LIBINPUT_NO_DEVICES='1',
                                     WLR_RENDERER='gles2', WLR_RENDER_DRM_DEVICE=f'/dev/dri/{card}'))
            for _ in range(200):
                sockets = list(runtime.glob('umbriel-*.sock'))
                if sockets or compositor.poll() is not None:
                    break
                time.sleep(0.05)
            if sockets:
                result['render_node'] = card
                break
            compositor.wait(timeout=5)
        else:
            raise RuntimeError('Private headless Umbriel did not start')
        display = next(path.name for path in runtime.glob('wayland-*') if path.is_socket())
        env.update(WAYLAND_DISPLAY=display, UMBRIEL_SOCKET=str(sockets[0]), QT_QPA_PLATFORM='wayland')
        # This fixture runs no desktop services and creates no windows. The
        # compositor is still private, as required for integration probes.
        qml = private / 'shell.qml'
        qml.write_text('''import QtQuick
import Quickshell
ShellRoot {
    id: root
    property QtObject fixture: QtObject {
        function setting(key, fallback) { return key === "agents" || key === "herdrCore" }
    }
    property Item holder: Item {
        Loader { id: loader }
        Component.onCompleted: loader.setSource("generation-a/sources/Desktop.qml", {island: root.fixture})
        Timer {
            interval: 1800; running: true
            onTriggered: {
                console.log("REPLACE_GENERATION")
                loader.setSource("generation-b/sources/Desktop.qml", {island: root.fixture})
            }
        }
        Timer { interval: 4000; running: true; onTriggered: { loader.source = ""; console.log("UNLOADED") } }
    }
}
''')
        shell = launch(['quickshell', '-n', '-p', qml], 'quickshell.log')
        observations = []
        for index in range(55):
            time.sleep(0.1)
            if shell.poll() is not None:
                raise RuntimeError('Private Quickshell exited')
            observations.append(dict(seconds=round((index + 1) / 10, 1), collectors=collectors(shell.pid)))
        first = next(item for item in observations if item['collectors'])
        old_pid = first['collectors'][0]['pid']
        after = next(item for item in observations if item['seconds'] >= 3)
        final = observations[-1]
        result.update(observations=observations, first_pid=old_pid,
                      replaced=bool(after['collectors']) and all(c['pid'] != old_pid for c in after['collectors']),
                      old_process_gone=not Path(f'/proc/{old_pid}').exists(),
                      no_collectors_after_unload=not final['collectors'])
        (OUT / 'reload.json').write_text(json.dumps(result, indent=2) + '\n')
        assert result['replaced'] and result['old_process_gone'] and result['no_collectors_after_unload'], result
    finally:
        for proc in reversed(processes):
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=6)
        # Process destruction behavior is the subject of this probe. Any child
        # left alive is one observed under our own Quickshell, with a saved PID.
        for pid in saved_children:
            path = Path(f'/proc/{pid}/stat')
            if path.exists() and path.read_text().split()[2] != 'Z':
                os.kill(pid, signal.SIGTERM)
        for file in logs:
            file.close()
        for name in ['quickshell.log', 'renderD129.log', 'renderD128.log']:
            path = private / name
            if path.exists():
                shutil.copy2(path, OUT / ('reload-' + name))
        shutil.rmtree(private)
        (OUT / 'reload-cleanup.json').write_text(json.dumps(dict(private_root=str(private),
             private_root_removed=not private.exists(), owned_pids=[proc.pid for proc in processes],
             collector_pids=sorted(saved_children), processes_reaped=all(proc.poll() is not None for proc in processes)), indent=2) + '\n')


if __name__ == '__main__':
    run()
