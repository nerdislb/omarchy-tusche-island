import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('corgi_status', Path(__file__).parents[1] / 'bin/corgi-status.py')
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


def reply(state='working', attention='none'):
    return {'ok': True, 'result': {'panes': [
        {'pane': 7, 'workspace': 1, 'agent': {'provider': 'codex', 'state': state,
         'attention': attention, 'name': '<img src="https://invalid"> $(echo x)', 'session': 's'}}],
        'conversations': [{'agent': {'state': 'working'}}]},
        'viewers': [{'id': 9, 'workspace': 1}]}


class StatusTests(unittest.TestCase):
    def test_states_and_current_panes_only(self):
        for state, attention, expected in [('working', 'none', 'working'), ('blocked', 'needs_input', 'blocked'),
                ('idle', 'needs_approval', 'blocked'), ('done', 'none', 'idle'), ('idle', 'none', 'idle'),
                ('lost', 'none', 'unknown')]:
            agents = c.snapshot(reply(state, attention))['agents']
            self.assertEqual(len(agents), 1)
            self.assertEqual(agents[0]['status'], expected)
            self.assertEqual(agents[0]['pane'], 'corgi:7')
            self.assertTrue(agents[0]['title'].startswith('<img'))  # rendered as PlainText in QML

    def test_invalid_and_closed(self):
        for data in ({'ok': False}, {}, {'ok': True, 'result': {}}):
            with self.assertRaises(ValueError): c.snapshot(data)
        data = reply(); data['result']['panes'][0]['exited'] = True
        self.assertEqual(c.snapshot(data)['agents'], [])
        data = reply(); data['result']['panes'][0]['pane'] = True
        self.assertEqual(c.snapshot(data)['agents'], [])

    def test_failures_are_unavailable(self):
        for error in (FileNotFoundError(), ValueError(), subprocess.TimeoutExpired('corgi', 3)):
            with patch.object(c, 'run_json', side_effect=error):
                self.assertEqual(c.poll(), {'available': False, 'agents': []})

    def test_focus_literal_and_unique(self):
        with patch.object(c, 'run_json', side_effect=[reply(), []]), patch.object(c.subprocess, 'run') as run:
            self.assertEqual(c.focus('7'), 0)
            self.assertEqual(run.call_args.args[0], ['corgi', 'focus', '7', '--viewer', '9'])
        data = reply(); data['viewers'].append({'id': 10, 'workspace': 1})
        with patch.object(c, 'run_json', return_value=data), patch.object(c.subprocess, 'run') as run:
            self.assertEqual(c.focus('7'), 1); run.assert_not_called()
        with patch.object(c, 'run_json') as read:
            self.assertEqual(c.focus('7; touch /tmp/no'), 1); read.assert_not_called()

    def test_focus_rejects_closed_or_malformed(self):
        for key in ('exited', 'dormant'):
            data = reply(); data['result']['panes'][0][key] = True
            with patch.object(c, 'run_json', return_value=data), patch.object(c.subprocess, 'run') as run:
                self.assertEqual(c.focus('7'), 1); run.assert_not_called()
        data = reply(); data['result']['panes'][0]['workspace'] = None
        with patch.object(c, 'run_json', return_value=data): self.assertEqual(c.focus('7'), 1)

    def test_bounds(self):
        data = reply(); data['result']['panes'][0]['agent']['name'] = 'x' * 10000
        self.assertEqual(len(c.snapshot(data)['agents'][0]['title']), 180)


if __name__ == '__main__': unittest.main()
