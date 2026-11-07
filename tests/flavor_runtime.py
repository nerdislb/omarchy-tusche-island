#!/usr/bin/env python3
"""Real Qt lifecycle checks: flavor switching, cancellation, reduced motion, rest."""
import dynamic_runtime as runtime

stubs = runtime.STUBS.replace('  property color islandInk:', '''  property string flavor: ""
  property int workingAgents: 2
  property int doneSerial: 0
  property color accentColor: "#ffb27a"
  property color islandInk:''')
SCENE = '''import QtQuick
import Quickshell
import qs.Commons
import "views"
import "IslandModel.js" as Model
FloatingWindow {
 id: root
 visible: true; implicitWidth: 960; implicitHeight: 560
''' + stubs + '''
 DynamicStage { id: stage; anchors.fill: parent; island: isl; rows: noteRows; anchorX: 480 }
 function fail(m) { console.log("FAIL " + m); Qt.exit(1) }
 function seal() { return stage.children.filter(function(c) { return c && c.eventKey !== undefined })[0] }
 function alert() { isl.hudAlert = { source: "hud", kind: "agent", key: -1, title: "Agent finished", subtitle: "Island build", actions: [] } }
 property int step: 0
 property double since: Date.now()
 function next(n) { step = n; since = Date.now() }
 Timer { interval: 20; running: true; repeat: true; onTriggered: root.tick() }
 function tick() {
  var age = Date.now() - since
  if (step === 0 && age > 400) {
   if (stage.ticking || stage.corona !== 0) return fail("default is not at rest")
   isl.flavor = "umbra"; next(1)
  } else if (step === 1 && age > 500) {
   if (Math.abs(stage.corona - 0.7) > 0.001 || stage.ticking) return fail("static corona does not settle")
   isl.doneSerial++; alert(); next(2)
  } else if (step === 2 && age > 140) {
   if (stage.flareAlpha < 0.8) return fail("completion did not flash")
   next(3)
  } else if (step === 3 && age > 1100) {
   if (stage.flareAlpha !== 0 || stage.corona !== 0 || stage.ticking) return fail("completion left a running effect")
   isl.flavor = "tusche"; next(4)
  } else if (step === 4 && age > 500) {
   var s = seal()
   if (!s || s.stampAlpha !== 1 || s.stampScale !== 1 || s.stampAngle !== -3 || s.inkAlpha !== 0 || s.animating)
    return fail("stamp or ink did not settle")
   isl.hudAlert = null; next(5)
  } else if (step === 5 && age > 1600) {
   if (seal().active || seal().animating || stage.ticking || stage.swelling) return fail("dismissed stamp remains")
   alert(); next(6)
  } else if (step === 6 && age > 60) {
   isl.flavor = "register"; next(7)
  } else if (step === 7 && age > 300) {
   var s = seal()
   if (s.stampAlpha !== 0 || s.inkAlpha !== 0 || s.marksAlpha !== 1 || s.marksInset !== 0 || s.animating)
    return fail("switch mid-stamp did not cancel or register did not settle")
   Style.reduceMotion = true; isl.flavor = "tusche"; next(8)
  } else if (step === 8 && age > 60) {
   var s = seal()
   if (s.stampScale !== 1 || s.stampAngle !== -3 || s.inkAlpha !== 0) return fail("reduced motion moved stamp")
   next(9)
  } else if (step === 9 && age > 300) {
   if (seal().animating || seal().stampAlpha !== 1) return fail("reduced stamp did not settle")
   isl.flavor = "umbra"; isl.doneSerial++; next(10)
  } else if (step === 10 && age > 60) {
   stage.live = false; next(11)
  } else if (step === 11 && age > 100) {
   if (stage.flareAlpha !== 0 || seal().active || seal().animating) return fail("hidden stage kept effect")
   stage.live = true; isl.flavor = ""; isl.hudAlert = null; next(12)
  } else if (step === 12 && age > 1600) {
   if (stage.ticking || stage.corona !== 0 || stage.flareAlpha !== 0 || seal().active || stage.swelling)
    return fail("default restore left transient state")
   console.log("PASS flavor: corona static; diamond expires; stamp settles; dismissal clears; switch cancels; register settles; reduced fades only; hidden stage cancels; default restored at rest")
   Qt.exit(0)
  }
 }
}
'''
if __name__ == '__main__':
    runtime.run(scenes={'flavor': SCENE})
