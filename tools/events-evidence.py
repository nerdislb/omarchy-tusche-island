#!/usr/bin/env python3
"""Exercise hc 0.1.18 and compare 60 idle seconds against the polling base.

All core writes use HC_SESSION=islandtest and private HOME/XDG paths. Only
owned PIDs are terminated; no desktop, service manager or owner core is used.
"""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import queue
import shutil
import socket
import subprocess as sp
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/evidence/events'
BASE = '1879de1'
HC = shutil.which('hc')


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run():
    OUT.mkdir(parents=True, exist_ok=True)
    private = Path(tempfile.mkdtemp(prefix='island-events-', dir='/tmp'))
    env = dict(HOME=str(private / 'home'), PATH='/usr/bin:/bin:' + str(Path(HC).parent),
               LANG='C.UTF-8', USER=os.environ.get('USER', 'nerdi'), HC_SESSION='islandtest',
               XDG_RUNTIME_DIR=str(private / 'run'), XDG_STATE_HOME=str(private / 'state'),
               XDG_CONFIG_HOME=str(private / 'config'), XDG_CACHE_HOME=str(private / 'cache'),
               XDG_DATA_HOME=str(private / 'data'), PYTHONDONTWRITEBYTECODE='1')
    for key, value in env.items():
        if key == 'HOME' or key.startswith('XDG_'):
            Path(value).mkdir(mode=0o700, parents=True, exist_ok=True)
    processes, streams, readers = [], [], []
    result = dict(base_commit=BASE, private_root=str(private), session='islandtest',
                  environment=env, core_version=sp.check_output([HC, '--version'], text=True).strip())
    collector_hash = hashlib.sha256((ROOT / 'bin/herdr-core-status.py').read_bytes()).hexdigest()
    result['collector_sha256'] = collector_hash

    def call(*args):
        return sp.check_output([HC, *args], env=env, text=True, stderr=sp.PIPE, timeout=10)

    def launch(args, name):
        log = (private / (name + '.stderr')).open('w')
        streams.append(log)
        proc = sp.Popen(args, env=env, stdout=sp.PIPE, stderr=log, text=True)
        processes.append(proc)
        return proc

    def consume(proc, name):
        lines = queue.Queue()
        captured = []

        def read():
            for line in proc.stdout:
                item = dict(seconds=round(time.monotonic() - started, 4), value=json.loads(line))
                captured.append(item)
                lines.put(item)
        started = time.monotonic()
        thread = threading.Thread(target=read)
        thread.start()
        readers.append(thread)
        return lines, captured

    def receive(lines, predicate, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            item = lines.get(timeout=max(0.01, deadline - time.monotonic()))
            if predicate(item['value']):
                return item
        raise AssertionError('Expected collector observation did not arrive')

    def request(method):
        with socket.socket(socket.AF_UNIX) as peer:
            peer.settimeout(5)
            peer.connect(str(private / 'run/herdr-core/islandtest.sock'))
            peer.sendall(json.dumps(dict(jsonrpc='2.0', id=1, method=method, params={})).encode() + b'\n')
            with peer.makefile('rb') as file:
                return json.loads(file.readline())

    try:
        # Foreground core gives this harness an owned, waitable PID. Private
        # runtime also prevents hc's systemd integration from using the owner bus.
        core = launch([HC, 'serve'], 'core')
        endpoint = private / 'run/herdr-core/islandtest.sock'
        for _ in range(100):
            if endpoint.exists():
                break
            if core.poll() is not None:
                raise AssertionError('Private core exited')
            time.sleep(0.05)
        else:
            raise AssertionError('Private core did not listen')
        collector = launch([sys.executable, str(ROOT / 'bin/herdr-core-status.py'), '--watch'], 'smoke')
        lines, observations = consume(collector, 'smoke')
        receive(lines, lambda value: value['available'])
        agent = private / 'agent.py'
        agent.write_text('''import sys, time
for state in ['working', 'done']:
    sys.stdout.write('\\x1b]7501;state=' + state + ':app=island-fixture\\x1b\\\\')
    sys.stdout.flush()
    time.sleep(1.2)
time.sleep(180)
''')
        address = json.loads(call('run', '--bg', '--no-parent', '--no-notify', '--name', 'island-fixture',
                                  '--label', 'where=Island fixture', sys.executable, str(agent)))['address']
        working = receive(lines, lambda value: any(a['status'] == 'working' and a['agent'] == 'island-fixture' for a in value['agents']))
        done = receive(lines, lambda value: any(a['status'] == 'idle' and a['agent'] == 'island-fixture' for a in value['agents']))
        # Observe the actual 15-second core heartbeat as well as the independent
        # 3-second island output; no facts are changed during this interval.
        with socket.socket(socket.AF_UNIX) as peer:
            peer.settimeout(18)
            peer.connect(str(endpoint))
            peer.sendall(b'{"jsonrpc":"2.0","id":1,"method":"events.subscribe","params":{}}\n')
            with peer.makefile('rb') as file:
                json.loads(file.readline())
                start = time.monotonic()
                heartbeat = json.loads(file.readline())
                result['core_heartbeat'] = dict(seconds=round(time.monotonic() - start, 4), message=heartbeat)
                assert heartbeat['method'] == 'heartbeat', heartbeat
        collector.terminate()
        collector.wait(timeout=5)
        result['smoke'] = dict(address=address, working=working, done=done, observations=observations)
        baseline = private / 'polling.py'
        baseline.write_bytes(sp.check_output(['git', 'show', BASE + ':bin/herdr-core-status.py'], cwd=ROOT))
        result['polling_sha256'] = hashlib.sha256(baseline.read_bytes()).hexdigest()
        old, new = load(baseline, 'polling_base'), load(ROOT / 'bin/herdr-core-status.py', 'events_current')
        cli = call('ls', '--json')
        api = request('events.subscribe')
        state = new.EventState()
        state.feed(api)
        old_line = json.dumps(old.snapshot(cli), sort_keys=True, separators=(',', ':'))
        assert old_line == new.encode(state.snapshot()), (old_line, state.snapshot())
        result['parity'] = dict(byte_equal=True, polling_line=old_line, event_line=new.encode(state.snapshot()),
                                cli_fixture=json.loads(cli), api_fixture=api)
        # Python's subprocess audit event counts actual Popen attempts. Log all
        # argv in this isolated fixture. rusage separates collector and child CPU;
        # startup/import cost is included for both variants.
        wrapper = private / 'measure.py'
        wrapper.write_text('''import importlib.util, json, resource, signal, sys, time
starts = []
def audit(event, args):
    if event == 'subprocess.Popen':
        starts.append({'seconds': time.monotonic() - started, 'argv': args[1]})
def stop(*_):
    raise SystemExit
signal.signal(signal.SIGTERM, stop)
started = time.monotonic()
sys.addaudithook(audit)
try:
    spec = importlib.util.spec_from_file_location('collector', sys.argv[1])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.watch()
finally:
    own = resource.getrusage(resource.RUSAGE_SELF)
    children = resource.getrusage(resource.RUSAGE_CHILDREN)
    elapsed = time.monotonic() - started
    cpu = own.ru_utime + own.ru_stime
    child_cpu = children.ru_utime + children.ru_stime
    with open(sys.argv[2], 'w') as file:
        json.dump(dict(seconds=elapsed, collector_cpu_seconds=cpu,
                       child_cpu_seconds=child_cpu, total_cpu_seconds=cpu + child_cpu,
                       total_one_cpu_percent=100 * (cpu + child_cpu) / elapsed,
                       process_starts=len(starts), starts=starts), file, indent=2)
''')
        measured = []
        for name, source in [('polling', baseline), ('events', ROOT / 'bin/herdr-core-status.py')]:
            proc = launch([sys.executable, str(wrapper), str(source), str(private / (name + '.json'))], name)
            pending, captured = consume(proc, name)
            receive(pending, lambda value: value['available'])
            measured.append((name, proc, captured))
        print('Private OSC working/done and byte parity passed; measuring both collectors for 60 seconds.', flush=True)
        # The calling tool yields while this interval runs.
        time.sleep(60)
        for name, proc, captured in measured:
            proc.terminate()
            proc.wait(timeout=6)
            result[name] = json.loads((private / (name + '.json')).read_text())
            result[name]['output_lines'] = len(captured)
            assert all(item['value']['available'] for item in captured)
        assert result['polling']['process_starts'] >= 39
        assert result['events']['process_starts'] == 0
        assert collector_hash == hashlib.sha256((ROOT / 'bin/herdr-core-status.py').read_bytes()).hexdigest()
        (OUT / 'measurement.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({name: {key: value for key, value in result[name].items() if key != 'starts'}
                          for name in ['polling', 'events']}, indent=2), flush=True)
    finally:
        for proc in processes:
            if proc.poll() is None and proc is not processes[0]:
                proc.terminate()
                proc.wait(timeout=6)
        if processes and processes[0].poll() is None:
            try:
                call('server', 'stop')
            finally:
                try:
                    processes[0].wait(timeout=6)
                except sp.TimeoutExpired:
                    processes[0].terminate()
                    processes[0].wait(timeout=6)
        for thread in readers:
            thread.join(timeout=3)
        for proc in processes:
            if proc.stdout:
                proc.stdout.close()
        for stream in streams:
            stream.close()
        # Preserve only diagnostics from our private processes before deleting.
        (OUT / 'stderr.txt').write_text(''.join(path.name + '\n' + path.read_text() for path in sorted(private.glob('*.stderr'))))
        pids = [proc.pid for proc in processes]
        shutil.rmtree(private)
        cleanup = dict(private_root=str(private), private_root_removed=not private.exists(),
                       owned_pids=pids, processes_reaped=all(proc.poll() is not None for proc in processes))
        (OUT / 'cleanup.json').write_text(json.dumps(cleanup, indent=2) + '\n')
        assert cleanup['private_root_removed'] and cleanup['processes_reaped']


if __name__ == '__main__':
    run()
