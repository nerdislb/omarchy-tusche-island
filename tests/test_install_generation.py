import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('install_generation', Path(__file__).parents[1] / 'bin/install-generation.py')
ig = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ig)


class InstallTests(unittest.TestCase):
    def test_the_island_moves_only_its_own_module_urls(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            source = tmp / 'src'
            (source / 'modules').mkdir(parents=True)
            (source / 'manifest.json').write_text(json.dumps({'id': 'nerdibeard.tusche-island', 'entryPoints': {'barWidget': 'BarWidget.qml'}}))
            (source / 'BarWidget.qml').write_text('import QtQuick\nItem {}\n')
            (source / 'modules/Bell.qml').write_text('import QtQuick\nItem {}\n')
            target = tmp / 'plugins' / 'nerdibeard.tusche-island'
            bar = tmp / 'plugins' / 'nerdibeard.tusche-bar'
            config = tmp / 'shell.json'
            layout = {'center': [{'id': 'nerdibeard.tusche-island', 'look': 'dynamic'}],
                      'centerEnd': [{'id': 'island.bell', 'source': str(target / 'modules/Bell.qml')},
                                    {'id': 'tusche.centre', 'source': str(bar / 'generations/abc/modules/Centre.qml')}]}
            config.write_text(json.dumps({'bar': {'layout': layout}}))
            first = ig.install(source, target, config)
            after = json.loads(config.read_text())['bar']['layout']
            self.assertEqual(after['centerEnd'][0]['source'], str(target / 'generations' / first / 'modules/Bell.qml'))
            # the bar's module and the island's own entry are left alone
            self.assertEqual(after['centerEnd'][1], layout['centerEnd'][1])
            self.assertEqual(after['center'], layout['center'])
            # a later generation moves it on from the old one
            (source / 'modules/Bell.qml').write_text('import QtQuick\nItem { }\n')
            second = ig.install(source, target, config)
            self.assertNotEqual(first, second)
            after = json.loads(config.read_text())['bar']['layout']
            self.assertEqual(after['centerEnd'][0]['source'], str(target / 'generations' / second / 'modules/Bell.qml'))
            # staging happens outside the plugin folder
            self.assertEqual(sorted(p.name for p in target.iterdir()), ['generations', 'installed-generation.json', 'manifest.json'])

    def test_a_path_out_of_the_folder_is_left_alone(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            source = tmp / 'src'
            (source / 'modules').mkdir(parents=True)
            (source / 'manifest.json').write_text(json.dumps({'id': 'nerdibeard.tusche-island', 'entryPoints': {'barWidget': 'BarWidget.qml'}}))
            (source / 'BarWidget.qml').write_text('import QtQuick\nItem {}\n')
            (source / 'modules/Bell.qml').write_text('import QtQuick\nItem {}\n')
            target = tmp / 'plugins' / 'nerdibeard.tusche-island'
            config = tmp / 'shell.json'
            config.write_text(json.dumps({'bar': {'layout': {}}}))
            first = ig.install(source, target, config)
            # a source that climbs out of the new generation into an older one
            sneaky = {'id': 'island.bell', 'source': str(target / 'modules/../..' / first / 'modules/Bell.qml')}
            config.write_text(json.dumps({'bar': {'layout': {'centerEnd': [sneaky]}}}))
            (source / 'modules/Bell.qml').write_text('import QtQuick\nItem { }\n')
            ig.install(source, target, config)
            self.assertEqual(json.loads(config.read_text())['bar']['layout']['centerEnd'][0], sneaky)


if __name__ == '__main__': unittest.main()
