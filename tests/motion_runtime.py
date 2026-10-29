#!/usr/bin/env python3
"""Real Qt runs of the island's spring motion (python3 tests/motion_runtime.py).

ShapeMorph: the island's shape grows to a new view on the Dynamic Island's
spring with a visible settle that stays within 6 px (and 4 % of the size), so
the 8 px lip and the pill never visibly dip; it never goes below 0, lands
exactly, keeps position and velocity on a retarget and stops its clock;
Reduced Motion and an unmapped strip put it in place at once.
ViewSlot: a view fades in while growing from 96 % to exactly 100 % without
overshoot, fades out faster where it stands (no zoom); unseen or Reduced Motion
at once. IslandSwitch: the knob is thrown with at most a hair of give, the
track colour follows the knob's position, the knob widens a fifth while pressed
toward where it would go. OutputsView: one plate glides between the rows with
the leading edge first, lands without a bounce, retargets without a jump,
follows a rebuilt row at once, and the row under it gives up its own plate.
Only the palette and spacing environment (qs.Commons) and IconButton (qs.Ui)
are stubbed, as in the Tusche Bar's tab_lens_runtime.py.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMMONS = Path(os.environ.get("OMARCHY_PATH", str(Path.home() / "omarchy"))) / "shell/Commons"

HELPERS = '''
 function fail(m) { console.log("FAIL " + m); Qt.exit(1) }
 // internal objects (springs, lenses) by a property only they have
 function find(o, key) {
  if (!o) return null
  if (o[key] !== undefined) return o
  var kids = o.data || []
  for (var i = 0; i < kids.length; i++) { var f = find(kids[i], key); if (f) return f }
  return null
 }
 function near(a, b, e) { return Math.abs(a - b) <= (e === undefined ? 0.01 : e) }
'''

SHAPE = '''import QtQuick
import Quickshell
import qs.Commons
import "views"
FloatingWindow {
 id: root
 visible: true; implicitWidth: 200; implicitHeight: 100
 property real tw: 126
 property real th: 32
 property bool live: true
 property real chipTarget: 0
 ShapeMorph { id: shape; targetWidth: root.tw; targetHeight: root.th; maxOvershoot: 6; live: root.live }
 // the bar's live segment: never past its width, never below 0
 SpringValue { id: chip; target: root.chipTarget; response: 0.32; damping: 0.92; cap: 0 }
''' + HELPERS + '''
 function at(w, h) { return shape.width === w && shape.height === h }
 property int step: 0
 property int ticks: 0
 property real maxW: 0
 property real maxH: 0
 property real minW: 1e9
 property real minH: 1e9
 property real growW: 0
 property real growH: 0
 property real lipDip: 0
 property real maxChip: 0
 property real minChip: 0
 function reset() { maxW = 0; maxH = 0; minW = 1e9; minH = 1e9; ticks = 0 }
 FrameAnimation {
  running: true
  onTriggered: {
   root.ticks++
   root.maxW = Math.max(root.maxW, shape.width); root.minW = Math.min(root.minW, shape.width)
   root.maxH = Math.max(root.maxH, shape.height); root.minH = Math.min(root.minH, shape.height)
   root.maxChip = Math.max(root.maxChip, chip.value); root.minChip = Math.min(root.minChip, chip.value)
   if (root.step === 0) {
    if (!at(126, 32) || shape.moving) return fail("first placement: not at the pill at rest")
    root.reset(); root.step = 1; root.tw = 424; root.th = 172; root.chipTarget = 80
   } else if (root.step === 1) {
    if (root.ticks === 1 && !shape.moving) return fail("a new view did not spring")
    if (shape.moving || chip.moving) { if (root.ticks > 120) fail("the grow did not settle within 2 s"); return }
    if (!at(424, 172)) return fail("did not land on 424x172: " + shape.width + "x" + shape.height)
    root.growW = root.maxW - 424; root.growH = root.maxH - 172
    if (root.growW < 2 || root.growW > 6 + 0.01) return fail("width settle out of range: " + root.growW)
    if (root.growH < 1 || root.growH > 6 + 0.01) return fail("height settle out of range: " + root.growH)
    if (shape.widthSpring.clock.running || shape.heightSpring.clock.running) return fail("a clock still runs at rest")
    if (root.maxChip > 80 || chip.value !== 80) return fail("the segment went past its width: " + root.maxChip)
    root.reset(); root.step = 2; root.tw = 64; root.th = 8; root.chipTarget = 0
   } else if (root.step === 2) {
    if (shape.moving || chip.moving) { if (root.ticks > 120) fail("the shrink did not settle"); return }
    if (!at(64, 8)) return fail("did not land on the lip")
    if (root.minH < 8 - 0.04 * 8 - 0.01) return fail("the lip dipped below its height: " + root.minH)
    if (root.minW < 64 - 0.04 * 64 - 0.01) return fail("the lip dipped below its width: " + root.minW)
    if (root.minChip < 0 || chip.value !== 0) return fail("the segment went below 0: " + root.minChip)
    root.lipDip = 8 - root.minH
    root.reset(); root.step = 3; root.tw = 424; root.th = 172
   } else if (root.step === 3) {
    if (root.ticks === 6) {   // retarget mid-flight: same place, same velocity
     var w = shape.widthSpring, x0 = w.position, v0 = w.velocity, shown = shape.width
     if (!shape.moving || v0 <= 0) return fail("not growing mid-flight")
     root.tw = 300; root.th = 32
     if (w.position !== x0 || w.velocity !== v0 || shape.width !== shown || !shape.moving) return fail("retarget jumped or lost its velocity")
    }
    if (root.ticks <= 6 || shape.moving) { if (root.ticks > 120) fail("retarget did not settle"); return }
    if (!at(300, 32)) return fail("retarget did not land on 300x32")
    root.reset(); root.step = 4; root.tw = 0
   } else if (root.step === 4) {
    if (shape.moving) { if (root.ticks > 120) fail("hiding did not settle"); return }
    if (root.minW < 0 || shape.width !== 0) return fail("the hidden shape went below 0: " + root.minW)
    root.tw = 126
    Style.reduceMotion = true; root.tw = 404; root.th = 186
    if (!at(404, 186) || shape.moving) return fail("Reduced Motion: the shape sprang")
    Style.reduceMotion = false
    root.live = false; root.tw = 126; root.th = 32
    if (!at(126, 32) || shape.moving) return fail("unmapped: the shape sprang")
    root.live = true
    root.reset(); root.step = 5; root.tw = 424; root.th = 172
   } else if (root.step === 5) {
    if (root.ticks === 4) {
     Style.reduceMotion = true
     if (!at(424, 172) || shape.moving) return fail("Reduced Motion mid-flight: not in place at once")
     Style.reduceMotion = false
     console.log("PASS shape: settle " + root.growW.toFixed(1) + " x " + root.growH.toFixed(1) + " px past the new size, the lip dips "
       + root.lipDip.toFixed(2) + " px, lands exactly, retargets with its velocity, no clock at rest, Reduced Motion and unmapped at once")
     Qt.exit(0)
    }
   }
  }
 }
}
'''

SLOT = '''import QtQuick
import Quickshell
import qs.Commons
import "views"
FloatingWindow {
 id: root
 visible: true; implicitWidth: 400; implicitHeight: 200
 property bool on: false
 property bool live: true
 Item {
  id: content
  width: 400; height: 200
  readonly property real dpr: 1
  readonly property bool live: root.live
  ViewSlot { id: slot; active: root.on; width: 300; height: 100; Rectangle { anchors.fill: parent; color: "red" } }
 }
''' + HELPERS + '''
 property var grow: null
 property int step: 0
 property int ticks: 0
 property real lastScale: 0
 property real maxScale: 0
 property real firstScale: 0
 property int enterTicks: 0
 FrameAnimation {
  running: true
  onTriggered: {
   root.ticks++
   if (root.step === 0) {
    root.grow = root.find(slot, "restartFrom")
    if (!root.grow) return fail("no spring in the slot")
    if (slot.opacity !== 0 || slot.visible || slot.x !== 50 || slot.y !== 50) return fail("an inactive slot shows")
    root.ticks = 0; root.step = 1; root.on = true
    root.firstScale = slot.scale; root.lastScale = slot.scale; root.maxScale = slot.scale
   } else if (root.step === 1) {
    if (slot.scale < root.lastScale - 1e-9) return fail("the entrance shrank on its way in")
    root.lastScale = slot.scale; root.maxScale = Math.max(root.maxScale, slot.scale)
    if (root.ticks === 1 && !(slot.opacity < 1 && slot.scale < 0.99)) return fail("the view did not grow in: " + slot.opacity + " " + slot.scale)
    if (root.grow.moving || slot.opacity < 1) { if (root.ticks > 90) fail("the entrance did not settle"); return }
    if (!near(root.firstScale, 0.96, 0.001)) return fail("did not start at 96 %: " + root.firstScale)
    if (root.maxScale > 1 || slot.scale !== 1 || slot.opacity !== 1) return fail("did not land at 100 % without overshoot: " + root.maxScale)
    root.enterTicks = root.ticks
    root.ticks = 0; root.step = 2; root.on = false
   } else if (root.step === 2) {
    if (slot.scale !== 1) return fail("the exit zoomed: " + slot.scale)
    if (slot.visible) { if (root.ticks > 15) fail("the exit took longer than its entrance"); return }
    if (root.grow.moving) return fail("a clock still runs after the exit")
    root.ticks = 0; root.step = 3; root.on = true
   } else if (root.step === 3) {
    if (root.ticks === 1 && slot.scale > 0.975) return fail("a fresh entrance did not start small: " + slot.scale)
    if (root.ticks === 3) { root.on = false; root.lastScale = slot.scale }
    if (root.ticks > 3 && slot.scale > root.lastScale + 1e-9) return fail("an interrupted entrance grew on its way out")
    if (root.ticks <= 3 || slot.visible) { if (root.ticks > 30) fail("the interrupted entrance did not leave"); return }
    root.live = false; root.on = true
    if (slot.opacity !== 1 || slot.scale !== 1) return fail("unseen: the view did not show at once")
    root.on = false
    if (slot.opacity !== 0) return fail("unseen: the view did not go at once")
    root.live = true
    Style.reduceMotion = true; root.on = true
    if (slot.opacity !== 1 || slot.scale !== 1 || root.grow.moving) return fail("Reduced Motion: the view grew in")
    Style.reduceMotion = false
    console.log("PASS slot: grows in from 96 % to exactly 100 % (" + root.enterTicks + " frames), fades out faster without a zoom, unseen and Reduced Motion at once")
    Qt.exit(0)
   }
  }
 }
}
'''

SWITCH = '''import QtQuick
import Quickshell
import qs.Commons
import "views"
FloatingWindow {
 id: root
 visible: true; implicitWidth: 100; implicitHeight: 60
 property bool on: false
 QtObject {
  id: isl
  property color surface: "#202830"
  property color accentColor: "#3388ff"
  property color fgDim: "#a0a0a0"
  function s(px) { return px }
 }
 IslandSwitch { id: sw; x: 20; y: 20; island: isl; width: implicitWidth; height: implicitHeight; checked: root.on }
''' + HELPERS + '''
 property int step: 0
 property int ticks: 0
 property real maxX: 0
 property real worst: 0
 property real free: 38 - 4 - 14
 function knobAt() { return (sw.knob.x - 2) / (38 - 4 - sw.knob.width) }
 function colourAt() { return (sw.track.color.r - sw.offTrack.r) / (sw.onTrack.r - sw.offTrack.r) }
 FrameAnimation {
  running: true
  onTriggered: {
   root.ticks++
   var moving = sw.data.some(function(o) { return o && o.restartFrom !== undefined && o.moving })
   if (root.step === 0) {
    if (sw.knob.x !== 2 || sw.knob.width !== 14 || !Qt.colorEqual(sw.track.color, sw.offTrack)) return fail("off at rest: knob or track wrong")
    root.ticks = 0; root.step = 1; root.on = true
   } else if (root.step === 1) {
    if (root.ticks === 1 && !moving) return fail("the knob was not thrown")
    root.maxX = Math.max(root.maxX, sw.knob.x)
    var k = Math.max(0, Math.min(1, root.knobAt()))
    root.worst = Math.max(root.worst, Math.abs(root.colourAt() - k))
    if (moving) { if (root.ticks > 60) fail("the throw did not settle within 1 s"); return }
    if (sw.knob.x !== 22 || !Qt.colorEqual(sw.track.color, sw.onTrack)) return fail("on: did not land: " + sw.knob.x)
    if (root.maxX > 22 + 1) return fail("the knob bounced too far: " + root.maxX)
    if (root.worst > 0.02) return fail("the track colour does not follow the knob: off by " + root.worst)
    root.ticks = 0; root.step = 2; sw.pressed = true
   } else if (root.step === 2) {
    if (moving) { if (root.ticks > 60) fail("the press did not settle"); return }
    if (!near(sw.knob.width, 14 * 1.2) || !near(sw.knob.x + sw.knob.width, 36)) return fail("pressed: the knob did not widen toward the free side: " + sw.knob.x + " " + sw.knob.width)
    root.ticks = 0; root.step = 3; sw.pressed = false
   } else if (root.step === 3) {
    if (moving) { if (root.ticks > 60) fail("the release did not settle"); return }
    if (sw.knob.width !== 14 || sw.knob.x !== 22) return fail("released: the knob did not come back: " + sw.knob.width)
    Style.reduceMotion = true; root.on = false
    if (sw.knob.x !== 2 || !Qt.colorEqual(sw.track.color, sw.offTrack)) return fail("Reduced Motion: the knob was thrown")
    Style.reduceMotion = false
    console.log("PASS switch: thrown with " + (root.maxX - 22).toFixed(2) + " px of give, the track colour follows the knob (within "
      + root.worst.toFixed(3) + "), widens a fifth while pressed toward its free side, Reduced Motion at once")
    Qt.exit(0)
   }
  }
 }
}
'''

OUTPUTS = '''import QtQuick
import Quickshell
import qs.Commons
import "views"
FloatingWindow {
 id: root
 visible: true; implicitWidth: 400; implicitHeight: 300
 readonly property var outs: [{ id: 1, name: "a" }, { id: 2, name: "b" }, { id: 3, name: "c" }, { id: 4, name: "d" }]
 QtObject {
  id: isl
  property var audioOutputs: root.outs
  property var sink: root.outs[0]
  property color fg: "#e0e0e0"
  property color accentColor: "#3388ff"
  property string fontFamily: "monospace"
  property string textFamily: "sans"
  function s(px) { return px }
  function f(px) { return px }
  function outputGlyph(n) { return "o" }
  function outputLabel(n) { return n.name }
  function selectOutput(n) { sink = n }
  function closeOutputs() {}
 }
 OutputsView { id: view; width: 392; height: 260; island: isl }
''' + HELPERS + '''
 property var lens: null
 property int step: 0
 property int ticks: 0
 property real maxStretch: 0
 property real minWidth: 1e9
 property real maxBottom: 0
 property bool bottomLed: false
 property real passedLit: 0
 property real glideStretch: 0
 function at(y, h) { return lens && lens.y === y && lens.height === h && near(lens.width, 360) }
 function rowAt(i) { var col = root.find(view, "spacing"); return col.children.filter(function(c) { return c.lit !== undefined })[i] }
 FrameAnimation {
  running: true
  onTriggered: {
   root.ticks++
   if (root.lens && root.lens.moving) {
    root.maxStretch = Math.max(root.maxStretch, root.lens.stretch)
    root.minWidth = Math.min(root.minWidth, root.lens.width)
    root.maxBottom = Math.max(root.maxBottom, root.lens.y + root.lens.height)
    if ((root.lens.y + root.lens.height - 40) / 132 > root.lens.y / 132 + 0.1) root.bottomLed = true
    root.passedLit = Math.max(root.passedLit, root.rowAt(1).lit)
   }
   if (root.step === 0) {
    root.lens = root.find(view, "edgeTop")
    if (!root.lens) return fail("no lens in the output list")
    if (!at(0, 40) || root.lens.moving) return fail("first placement: not on the first row at rest")
    if (!Qt.colorEqual(root.lens.color, Util.alpha(isl.accentColor, 0.18))) return fail("the lens is not the row highlight")
    if (root.rowAt(0).color.a !== 0 || !near(root.rowAt(1).color.a, 0.04, 0.005)) return fail("rows: the current one keeps its plate, or the others lost theirs")
    root.ticks = 0; root.step = 1; isl.selectOutput(root.outs[3])
   } else if (root.step === 1) {
    if (root.ticks === 1 && !root.lens.moving) return fail("a click did not glide")
    if (root.lens.moving) { if (root.ticks > 90) fail("the glide did not settle within 1.5 s"); return }
    if (!at(132, 40)) return fail("did not land on the fourth row: " + root.lens.y + " " + root.lens.height)
    if (!root.bottomLed) return fail("the leading edge did not lead")
    if (root.maxStretch < 8 || root.maxStretch > 80) return fail("stretch out of range: " + root.maxStretch)
    if (root.minWidth >= 360 || root.minWidth < 360 - 2 * 2 - 0.01) return fail("squeeze out of range: " + root.minWidth)
    if (root.maxBottom > 172 + 1) return fail("bounced past the row: " + root.maxBottom)
    if (root.passedLit < 0.5) return fail("the rows it passed did not glance up: " + root.passedLit)
    if (root.rowAt(3).color.a !== 0 || !near(root.rowAt(0).color.a, 0.04, 0.005)) return fail("rows did not hand their plates over")
    root.glideStretch = root.maxStretch
    root.ticks = 0; root.step = 2; isl.selectOutput(root.outs[0])
   } else if (root.step === 2) {
    if (root.ticks === 6) {   // retarget mid-flight: same place, same velocity
     var y0 = root.lens.y, h0 = root.lens.height, v0 = root.lens.topVelocity
     if (!root.lens.moving || v0 >= 0) return fail("not heading up mid-flight")
     isl.selectOutput(root.outs[1])
     if (root.lens.y !== y0 || root.lens.height !== h0 || root.lens.topVelocity !== v0 || !root.lens.moving) return fail("retarget jumped or lost its velocity")
    }
    if (root.ticks <= 6 || root.lens.moving) { if (root.ticks > 90) fail("retarget did not settle"); return }
    if (!at(44, 40)) return fail("retarget did not land on the second row")
    root.ticks = 0; root.step = 3
    isl.audioOutputs = root.outs.slice()   // a model reload: fresh delegates
   } else if (root.step === 3) {
    if (root.lens.moving) return fail("rebuilt rows: the lens glided instead of going along")
    if (!at(44, 40)) return fail("rebuilt rows: the lens is not on the second row: " + root.lens.y)
    Style.reduceMotion = true; isl.selectOutput(root.outs[2])
    if (!at(88, 40) || root.lens.moving) return fail("Reduced Motion: the lens glided")
    Style.reduceMotion = false
    view.visible = false; isl.selectOutput(root.outs[0])
    if (!at(0, 40) || root.lens.moving) return fail("unseen: the lens glided")
    console.log("PASS outputs: one plate glides with the leading edge first (stretch " + root.glideStretch.toFixed(1)
      + " px), lands without a bounce, retargets without a jump, follows rebuilt rows at once, rows give up their plate under it, Reduced Motion and unseen at once")
    Qt.exit(0)
   }
  }
 }
}
'''

ICON_BUTTON = '''import QtQuick
Item { property string glyph; property int glyphSize; property color color; property string fontFamily; signal clicked() }
'''

SCENES = {"shape": SHAPE, "slot": SLOT, "switch": SWITCH, "outputs": OUTPUTS}


def run():
    with tempfile.TemporaryDirectory(prefix="island-motion-", dir=os.environ.get("TMPDIR")) as tmp:
        tmp = Path(tmp)
        commons = tmp / "Commons"
        commons.mkdir(parents=True)
        shutil.copy2(COMMONS / "Util.qml", commons / "Util.qml")
        (commons / "qmldir").write_text("module qs.Commons\nsingleton Util 1.0 Util.qml\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\n")
        (commons / "Color.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property color foreground: "#eeeeee"; property color accent: "#3388ff" }
''')
        (commons / "Style.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property bool reduceMotion: false; property int cornerRadius: 6; function space(n) { return n } function duration(n) { return reduceMotion ? 0 : n } }
''')
        views = tmp / "views"
        shutil.copytree(ROOT / "views", views)
        (views / "IconButton.qml").write_text(ICON_BUTTON)
        failures = []
        for name, qml in SCENES.items():
            scene = tmp / f"{name}.qml"
            scene.write_text(qml)
            result = subprocess.run(["quickshell", "-p", str(scene)],
                                    env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software", "QT_FORCE_STDERR_LOGGING": "1", "QT_LOGGING_RULES": "qml=true;qml.*=true"},
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
            out = result.stdout
            print("\n".join(line for line in out.splitlines() if "PASS" in line or "FAIL" in line or "Error" in line or "rror:" in line) or out)
            bad = [e for e in ("ReferenceError:", "TypeError:", "Unable to assign", "Binding loop", "is not a type") if e in out]
            if result.returncode != 0 or f"PASS {name}:" not in out or bad:
                failures.append(f"{name} (exit {result.returncode}{', ' + ', '.join(bad) if bad else ''})")
                if f"PASS {name}:" not in out:
                    print(out)
        assert not failures, "motion runtime failed: " + "; ".join(failures)


if __name__ == "__main__":
    run()
