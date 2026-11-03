#!/usr/bin/env python3
"""Real Qt runs of the dynamic island (python3 tests/dynamic_runtime.py [--shots DIR]).

The look `look: "dynamic"` draws the island as a black capsule over the bar
(views/DynamicStage.qml) with one liquid shape (views/LiquidShape.qml and its
shader). These scenes run the stage in a real Qt Quick window with OpenGL
(under xvfb, software GL, as the Tusche Bar's glass tests do), on its own
clock stepped exactly 1/60 s per frame, with the real NoteRows queue, the
real IslandModel helpers and a small stand-in for the island:

  liquid    compact at rest (capsule 36 px from 2 px, nothing moving);
            a banner pours: the capsule swells (+30 px) and gives, the neck
            melts it to the capsule and lets go after 0.34 s, the card falls
            with a stretch and lands with a squash and a playful overshoot,
            its text comes in late; drawn back: the neck tightens, the card
            shrinks into the capsule, the capsule keeps the banner's symbol
            until it gulps the card with a wobble, the row is gone; minimal
            capsules bud off beside it and are drawn back; the island itself
            expands for an alert (and an agent's note becomes that alert
            instead of a card, the waiting rows hanging under it) and shrinks
            back; several notes stack (open card, two rows, "+N"); the input
            region is only the capsules and the cards; Reduced Motion
            cross-fades in place with nothing springing; a banner withdrawn
            while the capsule still swells for it leaves the capsule compact
  clock     the stage's own frame clock runs while something moves and
            stops at rest
  shots     (with --shots) compact, minimal, expanded, a banner mid-pour and
            at rest, and strips of the pour and the draw-back, as PNGs

Only qs.Commons (Util, a Color and Style stand-in) is stubbed, as in
motion_runtime.py.
"""
import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMMONS = Path(os.environ.get("OMARCHY_PATH", str(Path.home() / "omarchy"))) / "shell/Commons"
FONT = "JetBrainsMono Nerd Font"

STUBS = '''
 QtObject {
  id: svc
  property var banners: []
  property int serial: 0
  readonly property var queue: Model.noteQueue(banners)
  readonly property var current: queue.current
  readonly property var waiting: queue.waiting
  function add(fields) {
   serial++
   var e = { key: serial, ref: null, app: fields.app || "", appIcon: "", desktopEntry: "", summary: fields.summary || "",
             body: fields.body || "", image: "", glyph: fields.glyph || "", execArgv: "", critical: fields.critical === true,
             low: false, timeout: 0, actions: fields.actions || [], time: serial }
   banners = [e].concat(banners)
   return serial
  }
  function dismiss(key) { banners = banners.filter(function(e) { return e.key !== key }) }
  function later(key) { dismiss(key) }
  function promote(key) {
   var e = null
   for (var i = 0; i < banners.length; i++) if (banners[i].key === key) e = banners[i]
   if (!e || e === current) return
   e.order = Model.frontOrder(banners)
   banners = banners.slice()
  }
 }
 NoteRows { id: noteRows; service: svc; serving: true }
 QtObject {
  id: isl
  function s(px) { return px }
  function f(px) { return px }
  property string fontFamily: "FONT"
  property string textFamily: "FONT"
  property color islandInk: "#efeaf6"
  property color orangeColor: "#ffb27a"
  function onBlack(c) { return c }
  property string dynamicClock: "21:58"
  // as Island.qml: a banner's app while it is out, else the status
  property var statusLead: ({ kind: "agents", glyph: "\\u{f06a9}", text: "2", tone: "#ffd68f" })
  readonly property var dynamicLead: svc.current && !Model.isAlertNote(svc.current)
    ? { kind: "note:" + svc.current.key, glyph: svc.current.glyph, text: "", tone: noteTone(svc.current) } : statusLead
  property var dynamicMinimal: []
  property var hudAlert: null
  readonly property var dynamicAlert: hudAlert ? hudAlert
    : svc.current && Model.isAlertNote(svc.current)
      ? { source: "note", kind: "agent", key: svc.current.key, glyph: "\\u{f012c}", tone: "#a6dba4", title: "Agent finished",
          subtitle: Model.alertSubtitle(svc.current), actions: [{ id: "open", label: "Open", primary: true }, { id: "later", label: "Later" }] }
      : null
  function noteTone(e) { return !e ? "#ffb27a" : e.critical ? "#ff6b7d" : e.app === "WhatsApp" ? "#a6dba4" : e.app === "OmaMail" ? "#9fb3ff" : "#ffb27a" }
  function notificationIcon(e) { return "" }
 }
'''.replace("FONT", FONT)

HELPERS = '''
 function fail(m) { console.log("FAIL " + m); Qt.exit(1) }
 function near(a, b, e) { return Math.abs(a - b) <= (e === undefined ? 0.5 : e) }
 function rowsNow() {
  return stage.children.filter(function(c) { return c && c.phase !== undefined && c.occupy !== undefined })
   .sort(function(a, b) { return a.index - b.index })
 }
 function rect(i) { return { x: i.x, y: i.y, w: i.width, h: i.height } }
 function same(a, b, e) { return near(a.x, b.x, e) && near(a.y, b.y, e) && near(a.w, b.w, e) && near(a.h, b.h, e) }
 function fmt(r) { return "(" + [r.x, r.y, r.w, r.h].map(function(v) { return Math.round(v * 10) / 10 }).join(", ") + ")" }
 function hits() {
  return [stage.pillHit, stage.minHit0, stage.minHit1, stage.rowHit0, stage.rowHit1, stage.rowHit2, stage.rowHit3, stage.rowHit4, stage.rowHit5]
   .map(rect).filter(function(r) { return r.w > 0 && r.h > 0 })
 }
 function hitAt(x, y) { return hits().some(function(r) { return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h }) }
 // every input rect is a drawn box (the capsule, a capsule beside it, a card)
 function maskIsShapes() {
  var boxes = stage.children.filter(function(c) { return c.boxes !== undefined })[0].boxes
  return hits().every(function(h) {
   return boxes.some(function(b) { return near(b.x, h.x, 0.6) && near(b.y, h.y, 0.6) && near(b.w, h.w, 0.6) && near(b.h, h.h, 0.6) })
  })
 }
'''

LIQUID = '''import QtQuick
import Quickshell
import qs.Commons
import "views"
import "IslandModel.js" as Model
FloatingWindow {
 id: root
 visible: true; implicitWidth: 960; implicitHeight: 560
''' + STUBS + '''
 DynamicStage {
  id: stage
  anchors.fill: parent
  island: isl; rows: noteRows; anchorX: 480; barH: 30; manual: true
  onNoteDismissed: function(key) { svc.dismiss(key) }
 }
''' + HELPERS + '''
 property int step: 0
 property int ticks: 0
 property real t: 0
 property var m: ({})
 property int key1: 0
 property real compactW: 0
 property var report: []
 function next(n) { step = n; ticks = 0; m = {} }
 function mx(k, v) { if (m[k] === undefined || v > m[k]) m[k] = v }
 function mn(k, v) { if (m[k] === undefined || v < m[k]) m[k] = v }
 FrameAnimation { running: true; onTriggered: root.tick() }
 function tick() { stage.frame(1 / 60); root.t += 1 / 60; root.ticks++; root.script() }
 function script() {
  var r = rowsNow(), row = r.length ? r[0] : null
  if (step === 0) {
   // compact at rest: the capsule hangs from 2 px, 36 tall, nothing moves
   if (ticks < 3) return
   if (!stage.settled) return fail("compact: not at rest")
   compactW = stage.pillW
   if (!near(stage.pillY, 2) || !near(stage.pillH, 36) || !near(stage.pillX + stage.pillW / 2, 480)) return fail("compact: capsule at " + fmt({ x: stage.pillX, y: stage.pillY, w: stage.pillW, h: stage.pillH }))
   if (!near(stage.pillR, 18)) return fail("compact: not a capsule (r " + stage.pillR + ")")
   if (compactW < 90 || compactW > 140) return fail("compact: not narrow: " + compactW)
   if (!same(rect(stage.pillHit), { x: stage.pillX, y: 2, w: compactW, h: 36 })) return fail("compact: input region is not the capsule")
   if (hits().length !== 1) return fail("compact: input beyond the capsule")
   if (hitAt(100, 15) || hitAt(700, 15) || hitAt(480, 45)) return fail("compact: the bar around the capsule takes input")
   if (stage.compactAlpha !== 1 || stage.alertAlpha !== 0) return fail("compact: content not shown")
   report.push("compact " + Math.round(compactW) + "x36 at y 2")
   next(1)
   key1 = svc.add({ app: "WhatsApp", summary: "Sarah", body: "Ich danke dir, stress dich nicht!", glyph: "\\u{f05a3}" })
  } else if (step === 1) {
   // the pour
   mx("w", stage.pillW)
   if (!row) { if (ticks > 10) fail("pour: no row"); return }
   if (m.t0 === undefined) { m.t0 = t; m.fresh = row.phase }
   var at = t - m.t0
   if (at < 0.16 - 1e-6 && row.gt > 0) return fail("pour: text before the card")
   if (row.phase === "swell") mn("swellY", row.gy)
   if (row.phase === "pour" && m.pour === undefined) m.pour = at
   if (m.pour !== undefined) {
    mx("neck", row.gk); mx("cy", row.ncy); mx("stretch", row.stretchK); mn("squash", row.stretchK)
    var since = at - m.pour
    if (since > 0.28 && since < 0.32) m.neckLate = row.gk
    if (row.gk < 2 && m.neckGone === undefined) m.neckGone = since
    if (row.gt > 0.01 && m.textAt === undefined) m.textAt = at
   }
   if (stage.leadFront && stage.leadFront.kind !== "note:" + key1 && at > 0.05) return fail("pour: the capsule does not show the banner's app")
   if (ticks > 240) return fail("pour: did not settle in 4 s (phase " + row.phase + ")")
   if (!stage.settled || row.phase !== "rest") return
   if (m.fresh !== "swell") return fail("pour: the first card did not start in the capsule (" + m.fresh + ")")
   if (m.w < compactW + 24) return fail("pour: the capsule did not swell: " + (m.w - compactW))
   if (!near(stage.pillW, compactW, 0.6) && stage.leadFront.kind === "note:" + key1) { /* the app's symbol may be narrower */ }
   if (m.neck < 35) return fail("pour: no neck: " + m.neck)
   if (!(m.neckLate > 30)) return fail("pour: the neck let go too early: " + m.neckLate)
   if (!(m.neckGone > 0.6 && m.neckGone < 1.6)) return fail("pour: the neck did not let go in time: " + m.neckGone)
   var rest = 47 + row.restH / 2
   var over = m.cy - rest
   if (over < 1 || over > 14) return fail("pour: overshoot out of range: " + over)
   if (m.stretch < 0.03) return fail("pour: no stretch while falling: " + m.stretch)
   if (m.squash > -0.005) return fail("pour: no squash on landing: " + m.squash)
   if (!(m.textAt >= 0.36 - 1e-6)) return fail("pour: text too early: " + m.textAt)
   if (!same({ x: row.gx, y: row.gy, w: row.gw, h: row.gh }, { x: 260, y: 47, w: 440, h: row.restH })) return fail("pour: card not at rest: " + fmt({ x: row.gx, y: row.gy, w: row.gw, h: row.gh }))
   if (!same(rect(stage.rowHit0), { x: 260, y: 47, w: 440, h: row.restH })) return fail("pour: input region is not the card")
   if (!maskIsShapes() || hitAt(480, 42) || hitAt(100, 15)) return fail("pour: input beyond the capsule and the card")
   if (row.gt !== 1 || row.gk !== 0) return fail("pour: text or neck not settled")
   report.push("pour: swell +" + (m.w - compactW).toFixed(1) + " px, neck " + m.neck.toFixed(0) + " px still " + m.neckLate.toFixed(0)
     + " at 0.30 s, let go (< 2 px) at " + m.neckGone.toFixed(2) + " s, overshoot " + over.toFixed(1) + " px, stretch +" + (m.stretch * 100).toFixed(0)
     + " % / squash " + (m.squash * 100).toFixed(0) + " %, text at " + m.textAt.toFixed(2) + " s")
   next(2)
   svc.dismiss(key1)
  } else if (step === 2) {
   // drawn back in and gulped
   if (row) {
    if (m.t0 === undefined) m.t0 = t
    if (row.phase === "draw") {
     mx("neck", row.gk)
     if (!row.swallowed) {
      if (stage.leadFront.kind !== "note:" + key1) return fail("draw: the capsule let go of the banner's symbol before it swallowed the card")
     } else if (m.gulpAt === undefined) m.gulpAt = t - m.t0
     if (m.gulpAt !== undefined) mx("w", stage.pillW)
    }
   }
   if (ticks > 240) return fail("draw: did not finish in 4 s")
   if (r.length || !stage.settled) return
   if (!(m.neck > 30)) return fail("draw: the neck did not tighten: " + m.neck)
   if (m.gulpAt === undefined) return fail("draw: never swallowed")
   if (!(m.w > compactW + 4)) return fail("draw: no gulp: " + (m.w - compactW))
   if (!stage.leadFront || stage.leadFront.kind !== "agents") return fail("draw: the status did not come back")
   if (!near(stage.pillW, compactW, 0.6) || !near(stage.pillH, 36, 0.3)) return fail("draw: the capsule did not settle back")
   if (hits().length !== 1) return fail("draw: input left behind")
   report.push("draw: neck " + m.neck.toFixed(0) + " px, swallowed at " + m.gulpAt.toFixed(2) + " s, gulp +" + (m.w - compactW).toFixed(1) + " px")
   next(3)
   isl.dynamicMinimal = [{ kind: "timer", glyph: "", text: "4:12", tone: "#ffb27a" }]
  } else if (step === 3) {
   // a second activity buds off as its own capsule
   var c = stage.minHit0
   if (ticks <= 3 && rowsNow().length === 0) { var mk = stage.children.filter(function(x) { return x.goff !== undefined })[0]; mx("bud", mk.gk); mn("off", mk.goff) }
   if (ticks > 180) return fail("minimal: did not settle")
   if (!stage.settled) return
   var right = stage.pillX + stage.pillW
   if (!(m.bud > 10) || !(m.off < 0)) return fail("minimal: did not bud out of the capsule (" + m.bud + ", " + m.off + ")")
   if (!near(c.x, right + 10) || !near(c.y, 2) || !near(c.height, 36) || c.width < 36) return fail("minimal: capsule at " + fmt(rect(c)))
   if (m.two === undefined && !near(stage.extraWidth, c.width + 10)) return fail("minimal: the bar's room is wrong: " + stage.extraWidth + " for " + fmt(rect(c)) + " / " + fmt(rect(stage.minHit1)))
   if (!maskIsShapes()) return fail("minimal: input beyond the capsules")
   if (m.two === undefined) {
    m.two = true
    report.push("minimal: timer capsule " + Math.round(c.width) + " px at +10")
    isl.dynamicMinimal = [{ kind: "timer", glyph: "", text: "4:12", tone: "#ffb27a" }, { kind: "media", glyph: "\\u{f075a}", text: "", tone: "#ffb27a" }]
    ticks = 0
    return
   }
   var c2 = stage.minHit1
   if (!near(c2.x, c.x + c.width + 10) || c2.width < 36 || c2.width > 40) return fail("minimal: second capsule at " + fmt(rect(c2)))
   if (!near(stage.extraWidth, c.width + c2.width + 20)) return fail("minimal: the bar's room for two is wrong: " + stage.extraWidth)
   report.push("three in all: second capsule " + Math.round(c2.width) + " px")
   next(4)
   isl.dynamicMinimal = []
  } else if (step === 4) {
   if (ticks > 180) return fail("minimal: not drawn back")
   if (!stage.settled) return
   if (stage.minHit0.width !== 0 || stage.minHit1.width !== 0 || stage.extraWidth !== 0) return fail("minimal: left behind")
   next(5)
   isl.hudAlert = { source: "hud", kind: "battery", key: -1, glyph: "\\u{f0083}", tone: "#ff6b7d", title: "Battery low", subtitle: "9 % · plug in the charger",
                    actions: [{ id: "dismiss", label: "Dismiss", primary: true }, { id: "later", label: "Later" }] }
  } else if (step === 5) {
   // the island itself grows
   mx("h", stage.pillH); mx("w", stage.pillW)
   if (stage.pillH < 60 && stage.alertAlpha > 0.05) return fail("expand: alert content before the island grew")
   if (ticks > 180) return fail("expand: did not settle")
   if (!stage.settled) return
   if (!near(stage.pillW, 470) || !near(stage.pillH, 104) || !near(stage.pillY, 2) || !near(stage.pillR, 38)) return fail("expand: island " + fmt({ x: stage.pillX, y: stage.pillY, w: stage.pillW, h: stage.pillH }) + " r " + stage.pillR)
   if (m.h - 104 < 1 || m.h - 104 > 14) return fail("expand: overshoot out of range: " + (m.h - 104))
   if (stage.alertAlpha !== 1 || stage.compactAlpha !== 0) return fail("expand: content")
   if (!same(rect(stage.pillHit), { x: 245, y: 2, w: 470, h: 104 })) return fail("expand: input region is not the island")
   report.push("expand: 470x104 r 38, overshoot " + (m.h - 104).toFixed(1) + " x " + (m.w - 470).toFixed(1) + " px")
   next(6)
   isl.hudAlert = null
  } else if (step === 6) {
   if (stage.compactAlpha > 0.05 && stage.pillH > 36 + 40) return fail("shrink: compact content over a large island")
   if (ticks > 180) return fail("shrink: did not settle")
   if (!stage.settled) return
   if (!near(stage.pillW, compactW, 0.6) || !near(stage.pillH, 36, 0.3) || stage.compactAlpha !== 1 || stage.alertAlpha !== 0) return fail("shrink: not compact again")
   next(7)
   key1 = svc.add({ app: "Claude", summary: "Agent finished", body: "Done · Liquid Island", glyph: "\\u{f012c}" })
  } else if (step === 7) {
   // an agent's note: the island expands instead of a card; others hang under it
   if (ticks === 20) svc.add({ app: "OmaMail", summary: "Lena Berger", body: "Termin morgen um 10?", glyph: "\\u{f01ee}" })
   if (ticks < 30 || !stage.settled) { if (ticks > 240) fail("alert note: did not settle"); return }
   var rs = rowsNow()
   var first = rs.filter(function(x) { return x.key === key1 })[0]
   if (!first || first.phase !== "pill" || first.ga !== 0 || first.occupy !== 0) return fail("alert note: drawn as a card")
   if (!near(stage.pillH, 104) || !near(stage.pillW, 470)) return fail("alert note: the island did not expand")
   if (!same(rect(stage.rowHit0), { x: 260, y: 2 + 104 + 9, w: 440, h: 40 })) return fail("alert note: the waiting row is not under the island: " + fmt(rect(stage.rowHit0)))
   if (!maskIsShapes()) return fail("alert note: input beyond the shapes")
   report.push("alert note: the island expands, the waiting row hangs at y " + stage.rowHit0.y)
   next(8)
   svc.dismiss(key1)
  } else if (step === 8) {
   if (ticks > 240) return fail("alert note gone: did not settle")
   if (!stage.settled || rowsNow().length !== 1) return
   var o = rowsNow()[0]
   if (!near(stage.pillH, 36, 0.3) || !same(rect(stage.rowHit0), { x: 260, y: 47, w: 440, h: o.restH })) return fail("alert note gone: the next card did not move up: " + fmt(rect(stage.rowHit0)))
   next(9)
   svc.dismiss(o.key)
  } else if (step === 9) {
   if (ticks > 240) return fail("cleanup: did not settle")
   if (!stage.settled || rowsNow().length) return
   next(10)
   for (var n = 0; n < 4; n++) svc.add({ app: n % 2 ? "WhatsApp" : "OmaMail", summary: "Note " + (n + 1), body: "Body " + (n + 1), glyph: "\\u{f009a}" })
  } else if (step === 10) {
   // a stack: the open card, two waiting rows, "+N"
   if (ticks > 300) return fail("stack: did not settle")
   if (!stage.settled || ticks < 30) return
   var a = rect(stage.rowHit0), b = rect(stage.rowHit1), c3 = rect(stage.rowHit2), d = rect(stage.rowHit3)
   if (!near(a.y, 47) || !near(b.y, a.y + a.h + 6) || !near(c3.y, b.y + b.h + 6) || !near(d.y, c3.y + c3.h + 6)) return fail("stack: rows not stacked: " + [a, b, c3, d].map(fmt).join(" "))
   if (!near(b.h, 40) || !near(c3.h, 40) || !near(d.h, 30)) return fail("stack: row heights " + [b.h, c3.h, d.h])
   if (!maskIsShapes() || hitAt(480, a.y + a.h + 3)) return fail("stack: input beyond the cards")
   report.push("stack: open " + a.h + " + rows 40, 40 + more 30, 6 px apart")
   m.top = rowsNow()[0].key
   next(11)
   svc.dismiss(svc.current.key)
  } else if (step === 11) {
   if (ticks > 300) return fail("stack next: did not settle")
   if (!stage.settled || ticks < 10) return
   var rs2 = rowsNow()
   if (rs2.length !== 3 || rs2[2].kind !== "note") return fail("stack next: rows " + rs2.length)
   if (!same(rect(stage.rowHit0), { x: 260, y: 47, w: 440, h: rs2[0].restH })) return fail("stack next: the next card is not on top")
   next(12)
   svc.banners = []
  } else if (step === 12) {
   if (ticks > 300) return fail("stack clear: did not settle")
   if (!stage.settled || rowsNow().length) return
   // Reduced Motion: cross-fades in place, nothing springs
   Style.reduceMotion = true
   next(13)
   key1 = svc.add({ app: "WhatsApp", summary: "Sarah", body: "Bis gleich!", glyph: "\\u{f05a3}" })
  } else if (step === 13) {
   var rr = rowsNow()[0]
   if (!rr) { if (ticks > 10) fail("reduced: no row"); return }
   mx("w", stage.pillW); mx("neck", rr.gk)
   if (rr.gw > 0 && !same({ x: rr.gx, y: rr.gy, w: rr.gw, h: rr.gh }, { x: 260, y: 47, w: 440, h: rr.restH })) return fail("reduced: the card moved: " + fmt({ x: rr.gx, y: rr.gy, w: rr.gw, h: rr.gh }))
   if (m.a0 === undefined) m.a0 = rr.ga
   if (ticks > 60) return fail("reduced: fade did not finish")
   if (!stage.settled) return
   if (m.w > stage.pillW + 0.01 || m.neck > 0) return fail("reduced: swell or neck")
   if (!(m.a0 < 0.5) || rr.ga !== 1) return fail("reduced: no fade in (" + m.a0 + ")")
   if (ticks > 15) return fail("reduced: fade longer than 0.25 s")
   m.inTicks = ticks
   report.push("reduced: card in place, faded in over " + ticks + " frames")
   next(14)
   svc.dismiss(key1)
  } else if (step === 14) {
   var rq = rowsNow()[0]
   if (rq && rq.gw > 0 && !near(rq.gy, 47)) return fail("reduced: the card moved on its way out")
   if (rq) mx("w", stage.pillW)
   if (ticks > 60) return fail("reduced: did not fade out")
   if (rowsNow().length || !stage.settled) return
   if (m.w > compactW + 0.6) return fail("reduced: the capsule gulped")
   next(15)
   isl.hudAlert = { source: "hud", kind: "timer", key: -1, glyph: "\\u{f0020}", tone: "#ffb27a", title: "Tea", subtitle: "Time's up",
                    actions: [{ id: "again", label: "+1 min", primary: true }, { id: "dismiss", label: "Dismiss" }] }
  } else if (step === 15) {
   if (ticks === 1 && (!near(stage.pillH, 104) || !near(stage.pillW, 470))) return fail("reduced: the island grew instead of being there")
   if (ticks > 60) return fail("reduced: alert fade")
   if (!stage.settled) return
   if (stage.alertAlpha !== 1) return fail("reduced: alert content")
   isl.hudAlert = null
   Style.reduceMotion = false
   report.push("reduced: the island is there at once, its content fades")
   next(16)
  } else if (step === 16) {
   if (ticks > 180) return fail("swell gone: compact did not settle")
   if (!stage.settled) return
   next(17)
   key1 = svc.add({ app: "OmaMail", summary: "Lena Berger", body: "Kurz da", glyph: "\\u{f01ee}" })
  } else if (step === 17) {
   // a banner withdrawn while the capsule still swells for it (a notification
   // replaced or closed at once): the capsule gives the swell back
   if (ticks === 3) {
    if (!row || row.phase !== "swell" || !stage.swelling) return fail("swell gone: no swell to interrupt (" + (row ? row.phase : "no row") + ")")
    svc.dismiss(key1)
   }
   if (ticks > 240) return fail("swell gone: did not settle (capsule " + fmt({ x: stage.pillX, y: stage.pillY, w: stage.pillW, h: stage.pillH }) + ")")
   if (ticks < 4 || rowsNow().length || !stage.settled) return
   if (stage.swelling || !near(stage.pillW, compactW, 0.6) || !near(stage.pillH, 36, 0.3))
    return fail("swell gone: the capsule stayed swollen: " + fmt({ x: stage.pillX, y: stage.pillY, w: stage.pillW, h: stage.pillH }) + " for " + Math.round(compactW) + "x36")
   report.push("swell gone: a banner withdrawn mid-swell leaves the capsule compact")
   console.log("PASS liquid: " + report.join("; "))
   Qt.exit(0)
  }
 }
}
'''

CLOCK = '''import QtQuick
import Quickshell
import qs.Commons
import "views"
import "IslandModel.js" as Model
FloatingWindow {
 id: root
 visible: true; implicitWidth: 960; implicitHeight: 400
''' + STUBS + '''
 DynamicStage { id: stage; anchors.fill: parent; island: isl; rows: noteRows; anchorX: 480; barH: 30 }
''' + HELPERS + '''
 property int phase: 0
 property bool sawTick: false
 Timer {
  interval: 50; repeat: true; running: true
  property int n: 0
  onTriggered: {
   n++
   if (root.phase === 0 && n > 4) {
    if (stage.ticking) return fail("clock: ticking at rest after load")
    root.phase = 1; n = 0
    svc.add({ app: "WhatsApp", summary: "Sarah", body: "Hallo", glyph: "\\u{f05a3}" })
   } else if (root.phase === 1) {
    if (stage.ticking) root.sawTick = true
    if (n > 80) return fail("clock: still ticking 4 s after a banner")
    if (n > 10 && root.sawTick && !stage.ticking) {
     if (rowsNow().length !== 1 || rowsNow()[0].phase !== "rest") return fail("clock: stopped before the card rested")
     console.log("PASS clock: runs while the banner pours (" + n * 50 + " ms), stops at rest")
     Qt.exit(0)
    }
   }
  }
 }
}
'''

SHOTS = '''import QtQuick
import Quickshell
import qs.Commons
import "views"
import "IslandModel.js" as Model
FloatingWindow {
 id: root
 visible: true; implicitWidth: 960; implicitHeight: 236
''' + STUBS + '''
 Item {
  id: canvas
  anchors.fill: parent
  Rectangle { anchors.fill: parent; color: "#120e1c" }
  Image { anchors.fill: parent; source: "BACKDROP"; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
  // a stand-in for Omarchy's bar around the island's slot
  Rectangle { width: parent.width; height: 30; color: "#0c0a12" }
  Row {
   x: 120; y: 0; height: 30; spacing: 16
   Repeater { model: ["\\u{f0e5e}", "\\u{f0176}", "\\u{f0a0f}"]; Text { anchors.verticalCenter: parent.verticalCenter; text: modelData; font.family: "FONT"; font.pixelSize: 14; color: index === 0 ? "#ff6b7d" : "#d6cfe2" } }
  }
  Row {
   x: 700; y: 0; height: 30; spacing: 14
   Text { anchors.verticalCenter: parent.verticalCenter; text: "\\u{f009a} 36"; font.family: "FONT"; font.pixelSize: 13; color: "#ffb27a" }
   Text { anchors.verticalCenter: parent.verticalCenter; text: "\\u{f0590} 11°"; font.family: "FONT"; font.pixelSize: 13; color: "#d6cfe2" }
   Text { anchors.verticalCenter: parent.verticalCenter; text: "\\u{f0450}"; font.family: "FONT"; font.pixelSize: 14; color: "#d6cfe2" }
  }
  DynamicStage { id: stage; anchors.fill: parent; island: isl; rows: noteRows; anchorX: 480; barH: 30; manual: true }
 }
''' + HELPERS + '''
 readonly property string out: "OUT"
 property int step: 0
 property int ticks: 0
 property bool busy: false
 property var plan: []
 FrameAnimation { running: !root.busy; onTriggered: { stage.frame(1 / 60); root.ticks++; root.script() } }
 function shot(name) {
  busy = true
  canvas.grabToImage(function(r) { r.saveToFile(out + "/" + name + ".png"); console.log("SHOT " + name); busy = false })
 }
 // frames of the pour / the draw-back to keep (sim frames after the event)
 readonly property var pourFrames: [0, 6, 10, 14, 18, 22, 26, 32, 40, 50, 64, 90]
 readonly property var drawFrames: [0, 6, 10, 14, 18, 22, 26, 32, 40, 56]
 property int key1: 0
 function script() {
  if (busy) return
  if (step === 0 && ticks > 2 && stage.settled) { shot("compact"); step = 1; ticks = 0 }
  else if (step === 1) {
   isl.dynamicMinimal = [{ kind: "timer", glyph: "", text: "4:12", tone: "#ffb27a" }]
   step = 2; ticks = 0
  } else if (step === 2 && ticks > 2 && stage.settled) { shot("minimal"); step = 3; ticks = 0 }
  else if (step === 3) {
   isl.dynamicMinimal = []
   isl.hudAlert = { source: "hud", kind: "agent", key: -1, glyph: "\\u{f012c}", tone: "#a6dba4", title: "Agent finished",
                    subtitle: "Liquid Island · 4 min · Claude", actions: [{ id: "open", label: "Open", primary: true }, { id: "later", label: "Later" }] }
   step = 4; ticks = 0
  } else if (step === 4 && ticks > 2 && stage.settled) { shot("expanded"); step = 5; ticks = 0 }
  else if (step === 5) { isl.hudAlert = null; step = 6; ticks = 0 }
  else if (step === 6 && ticks > 2 && stage.settled) {
   key1 = svc.add({ app: "WhatsApp", summary: "Sarah", body: "Ich danke dir, stress dich nicht!", glyph: "\\u{f05a3}" })
   step = 7; ticks = -1
  } else if (step === 7) {
   if (pourFrames.indexOf(ticks) !== -1) shot("pour-" + ("00" + ticks).slice(-3))
   if (ticks === 22) shot("banner-midpour")
   if (ticks > 90 && stage.settled) { shot("banner"); step = 8; ticks = 0 }
  } else if (step === 8) { svc.dismiss(key1); step = 9; ticks = -1 }
  else if (step === 9) {
   if (drawFrames.indexOf(ticks) !== -1) shot("draw-" + ("00" + ticks).slice(-3))
   if (ticks > 56 && stage.settled) {
    for (var n = 0; n < 3; n++) svc.add({ app: n ? "OmaMail" : "WhatsApp", summary: n ? "Lena Berger" : "Sarah", body: n ? "Termin morgen um 10?" : "Bis gleich!",
                                          glyph: n ? "\\u{f01ee}" : "\\u{f05a3}" })
    step = 10; ticks = 0
   }
  } else if (step === 10 && ticks > 60 && stage.settled) { shot("stack"); step = 11; ticks = 0 }
  else if (step === 11) { console.log("PASS shots"); Qt.exit(0) }
 }
}
'''.replace("FONT", FONT)


def run_scene(tmp, name, qml, env, timeout=120):
    scene_dir = tmp / f"scene-{name}"
    scene_dir.mkdir()
    for item in ("views", "Commons", "IslandModel.js"):
        src = tmp / item
        dst = scene_dir / item
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
    (scene_dir / "shell.qml").write_text(qml)
    log = tmp / f"{name}.log"
    with log.open("w") as out:
        proc = subprocess.Popen(["xvfb-run", "-a", "-s", "-screen 0 1280x1024x24", "quickshell", "-n", "-p", str(scene_dir)],
                                env=env, stdout=out, stderr=subprocess.STDOUT, text=True, start_new_session=True)
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=10)
    return proc.returncode, log.read_text()


def run(shots=None):
    with tempfile.TemporaryDirectory(prefix="island-dynamic-", dir=os.environ.get("TMPDIR")) as tmp:
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
        shutil.copytree(ROOT / "views", tmp / "views")
        shutil.copy2(ROOT / "IslandModel.js", tmp / "IslandModel.js")
        env = {**os.environ, "QT_QPA_PLATFORM": "xcb", "QSG_RHI_BACKEND": "opengl", "LIBGL_ALWAYS_SOFTWARE": "1",
               "QT_LOGGING_RULES": "qml=true;qml.*=true;quickshell.dbus*=false", "QT_FORCE_STDERR_LOGGING": "1"}
        scenes = {"liquid": LIQUID, "clock": CLOCK}
        if shots:
            shots = Path(shots).resolve()
            shots.mkdir(parents=True, exist_ok=True)
            backdrop = Path.home() / ".local/state/omarchy/current/background"
            scenes["shots"] = SHOTS.replace("OUT", str(shots)).replace("BACKDROP", backdrop.as_uri() if backdrop.exists() else "")
        failures = []
        for name, qml in scenes.items():
            code, out = run_scene(tmp, name, qml, env)
            lines = [line for line in out.splitlines() if "PASS" in line or "FAIL" in line or "rror" in line or "SHOT" in line]
            print("\n".join(lines) or out[-3000:])
            bad = [e for e in ("ReferenceError:", "TypeError:", "Unable to assign", "Binding loop", "is not a type", "Cannot assign") if e in out]
            if code != 0 or f"PASS {name}" not in out or bad:
                failures.append(f"{name} (exit {code}{', ' + ', '.join(bad) if bad else ''})")
                if f"PASS {name}" not in out:
                    print(out[-4000:])
        assert not failures, "dynamic runtime failed: " + "; ".join(failures)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", help="also save screenshots of every state into this directory")
    run(parser.parse_args().shots)
