#!/usr/bin/env python3
"""Compare the empty flavor with d3dd40d using real Qt renders at rest."""
import json
import os
from pathlib import Path
import shutil
import subprocess as sp
import tempfile
from PIL import Image, ImageChops
import dynamic_runtime as runtime

ROOT = runtime.ROOT
SCENE = '''import QtQuick
import Quickshell
import qs.Commons
import "views"
import "IslandModel.js" as Model
FloatingWindow {
 id: root
 visible: true; implicitWidth: 960; implicitHeight: 560
 color: "#17131d"
''' + runtime.STUBS + '''
 DynamicStage { id: stage; anchors.fill: parent; island: isl; rows: noteRows; anchorX: 480 }
 property int step: 0
 property bool busy: false
 Timer { interval: 2200; running: true; repeat: true; onTriggered: root.capture() }
 function capture() {
  if (busy) return
  busy = true
  stage.grabToImage(function(result) {
   result.saveToFile("OUT/" + step + ".png")
   step++
   if (step === 1) isl.dynamicMinimal = [{ kind: "timer", glyph: "", text: "4:32", tone: "#ffb27a" }]
   else if (step === 2) { isl.dynamicMinimal = []; isl.hudAlert = { source: "hud", kind: "agent", key: -1,
     glyph: "\\u{f012c}", title: "Agent finished", subtitle: "Island build", tone: "#a6dba4", actions: [] } }
   else if (step === 3) { isl.hudAlert = null; svc.add({ app: "Codex", summary: "Build", body: "Build finished", glyph: "\\u{f012c}" }) }
   else { console.log("PASS pixels"); Qt.exit(0) }
   busy = false
  })
 }
}
'''


def run():
    with tempfile.TemporaryDirectory(prefix='island-pixels-', dir='/tmp') as directory:
        tmp = Path(directory)
        for variant in ['base', 'current']:
            dest = tmp / variant
            dest.mkdir()
            if variant == 'base':
                data = sp.check_output(['git', 'archive', 'd3dd40d', 'views', 'IslandModel.js'], cwd=ROOT)
                sp.run(['tar', 'xf', '-', '-C', dest], input=data, check=True)
            else:
                shutil.copytree(ROOT / 'views', dest / 'views')
                shutil.copy2(ROOT / 'IslandModel.js', dest / 'IslandModel.js')
            shutil.copytree(ROOT / 'assets', dest / 'assets')
            commons = dest / 'Commons'
            commons.mkdir()
            shutil.copy2(runtime.COMMONS / 'Util.qml', commons / 'Util.qml')
            (commons / 'qmldir').write_text('module qs.Commons\nsingleton Util 1.0 Util.qml\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\n')
            (commons / 'Color.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var shellValues: ({}); property color accent: "#ffb27a"; property color foreground: "#efeaf6" }')
            (commons / 'Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool reduceMotion: false; function space(n) { return n } function duration(n) { return n } }')
            output = tmp / (variant + '-shots')
            output.mkdir()
            env = {**os.environ, 'QT_QPA_PLATFORM': 'xcb', 'QSG_RHI_BACKEND': 'opengl', 'LIBGL_ALWAYS_SOFTWARE': '1', 'QT_QPA_PLATFORMTHEME': 'basic'}
            code, log = runtime.run_scene(dest, 'pixels', SCENE.replace('OUT', str(output)), env, timeout=30)
            assert code == 0 and 'PASS pixels' in log, log[-4000:]
        results = {}
        for i, label in enumerate(['compact', 'minimal', 'expanded', 'banner']):
            a = Image.open(tmp / 'base-shots' / f'{i}.png').convert('RGBA')
            b = Image.open(tmp / 'current-shots' / f'{i}.png').convert('RGBA')
            delta = ImageChops.difference(a, b)
            bounds = delta.convert('RGB').getbbox() or delta.getchannel('A').getbbox()
            results[label] = {'identical': bounds is None, 'difference_bounds': bounds}
            assert bounds is None, f'{label}: empty flavor differs from baseline at {bounds}'
        print('PASS empty flavor is pixel-identical to d3dd40d: ' + json.dumps(results))

if __name__ == '__main__':
    run()
