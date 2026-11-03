import QtQuick
import qs.Commons
import "Liquid.js" as L

// The dynamic island on one bar (Island.qml `look: "dynamic"`; drawn over the
// bar by DynamicIsland.qml): Apple's Dynamic Island as a true black capsule
// hanging from the top bar (hybrid design 29.10.2026, rule 4 and board 01).
//
//   compact   a capsule a few pixels under the top edge, hanging below the
//             bar: the status on the left in its colour, the clock on the
//             right, both halves balanced and as narrow as possible
//   minimal   up to two more live activities bud off beside it as their own
//             small capsules with live data (three in all)
//   expanded  for the events that matter (Island.qml dynamicAlert) the
//             capsule itself grows into a rounded island with the alert
//   banners   every other notification pours out of the capsule as one
//             liquid shape (views/LiquidShape.qml): the capsule swells, the
//             card falls out through a neck that lets go, stretching as it
//             falls and squashing as it lands; drawn back, the neck tightens,
//             the card shrinks into the capsule and the capsule gulps it
//             (Liquid Island prototype v2, "Verspielt"). Waiting rows and
//             "+N" hang under it as plain black cards (views/NoteRows.qml).
//
// Everything moves on one clock (Liquid.js: Apple springs stepped exactly,
// the timing in the frame loop as in the prototype), which stops as soon as
// nothing moves. Reduced Motion: nothing springs, things cross-fade in place.
// Off screen (`live` false): everything is placed at once.
Item {
  id: stage

  // ------------------------------------------------------------ inputs
  property var island: null
  property var rows: null              // NoteRows, on the monitor that shows the notes
  property real anchorX: width / 2     // the island's slot in the bar (its centre)
  property real barH: 30               // the bar's thickness here
  property bool popupOpen: false       // the island's popup hangs from this bar: tuck in
  property bool ownsAlert: true        // the expanded island shows here
  property bool live: true             // on screen
  property bool manual: false          // tests: frames come from frame(dt) only

  // ------------------------------------------------------------ outputs
  signal pillPressed(int button)
  signal minimalPressed(string kind)
  signal noteOpened(int key)
  signal noteDismissed(int key)
  signal noteLater(int key)
  signal noteAction(int key, string id)
  signal notePromoted(int key, string kind)
  signal alertAction(string id)
  signal alertDismissed()

  // what the bar reserves: the compact capsule, and the capsules beside it
  readonly property real slotWidth: compactW
  property real extraWidth: 0
  readonly property bool pillHovered: pillHover.hovered
  property int hoverCount: 0
  readonly property bool notesHovered: hoverCount > 0
  readonly property bool alertHovered: alertShown && alertView.hovering
  readonly property bool ticking: clock.running
  // the last frame left everything at rest (the clock stops then)
  property bool settled: true
  // the input region: the capsule, the capsules beside it, the cards
  readonly property alias pillHit: pillArea
  readonly property alias minHit0: minHitA
  readonly property alias minHit1: minHitB
  readonly property alias rowHit0: rowHitA
  readonly property alias rowHit1: rowHitB
  readonly property alias rowHit2: rowHitC
  readonly property alias rowHit3: rowHitD
  readonly property alias rowHit4: rowHitE
  readonly property alias rowHit5: rowHitF

  // ------------------------------------------------------------ measures
  function s(px) { return island ? island.s(px) : px }
  function f(px) { return island ? island.f(px) : px }
  readonly property real unit: s(100) / 100
  readonly property string family: island ? island.fontFamily : ""
  readonly property real capTop: s(2)
  // the compact height: the island's `capsuleHeight` in screen pixels like the
  // bar's own height (only the island's scale applies, not the spacing scale)
  readonly property real capH: island && island.dynamicCapsuleHeight !== undefined
    ? Math.round(island.dynamicCapsuleHeight * (island.scaleFactor > 0 ? island.scaleFactor : 1))
    : Math.max(s(30), barH + s(6))
  readonly property real tuckH: Math.max(s(18), barH - s(6))
  readonly property real tuckTop: Math.round((barH - tuckH) / 2)
  readonly property real cardW: Math.max(s(200), Math.min(s(440), width - 2 * s(12)))
  readonly property real alertW: Math.max(s(240), Math.min(s(470), width - 2 * s(12)))
  readonly property real gap: s(9)          // under the capsule
  readonly property real rowGap: s(6)       // between cards
  readonly property real minGap: s(10)      // between capsules
  readonly property real cardCx: Math.max(cardW / 2 + s(8), Math.min(width - cardW / 2 - s(8), anchorX))
  property real dpr: 1                      // device pixels per px (the window's)
  readonly property bool reduced: Style.reduceMotion
  readonly property bool instant: reduced || !live

  // ------------------------------------------------------------ colours
  readonly property color ink: island && island.islandInk !== undefined ? island.islandInk : "#f2f2f2"
  readonly property color dim: Util.alpha(ink, 0.62)
  function tone(c) { return island && typeof island.onBlack === "function" ? island.onBlack(c) : c }

  // ------------------------------------------------------------ what it shows
  readonly property string clockText: island ? island.dynamicClock : ""
  readonly property var alertNow: ownsAlert && !popupOpen && island ? island.dynamicAlert : null
  readonly property bool alertShown: !!alertNow
  readonly property int alertNoteKey: alertNow && alertNow.source === "note" ? alertNow.key : -1
  property var shownAlert: null
  onAlertNowChanged: { if (alertNow) shownAlert = alertNow; retarget() }
  onAlertShownChanged: retarget()
  readonly property var minimalNow: alertShown || !island || !island.dynamicMinimal ? [] : island.dynamicMinimal.slice(0, 2)
  readonly property int currentKey: rows && rows.service && rows.service.current ? rows.service.current.key : -1

  // The leading half. A banner's event stays in the capsule until the
  // capsule has swallowed its card (the prototype's words change then).
  property var holdLead: null
  readonly property var leadSource: island ? island.dynamicLead : null
  property var leadFront: null
  property var leadBack: null
  onLeadSourceChanged: swapLead()
  function swapLead() {
    var next = holdLead || leadSource
    // a banner going back to the status: its symbol stays until the capsule
    // has swallowed the card (released by the card, or after half a second)
    if (!holdLead && leadFront && /^note:/.test(leadFront.kind) && !(next && /^note:/.test(next.kind))
        && cardShowing(leadFront.kind)) {
      holdAge = 0
      holdLead = leadFront
      return
    }
    if (leadFront && next && leadFront.kind === next.kind) { leadFront = next; retarget(); return }
    if (!leadFront && !next) return
    leadBack = leadFront
    leadFront = next
    if (sp) { L.place(sp.mix, 0); fadeTo(sp.mix, 1, 0.22) }
    retarget()
  }
  property real holdAge: 0
  function holdFor(key) {
    if (!holdLead && leadFront && leadFront.kind === "note:" + key) { holdAge = 0; holdLead = leadFront }
  }
  function releaseHold() { if (holdLead) { holdLead = null; swapLead() } }
  // the row of a "note:<key>" lead, out as a card (not on its way back)
  function cardOf(kind) {
    var key = parseInt(String(kind).substring(5), 10)
    for (var i = 0; i < rowRep.count; i++) {
      var r = rowRep.itemAt(i)
      if (r && r.key === key && !r.finished) return r
    }
    return null
  }
  function cardShowing(kind) {
    var r = cardOf(kind)
    return !!r && !r.leaving && ["swell", "pour", "rest", "drop"].indexOf(r.phase) !== -1 && r.ga > 0.5
  }

  TextMetrics { id: leadGlyphM; font.family: stage.family; font.pixelSize: stage.f(15); text: stage.leadFront && stage.leadFront.glyph ? stage.leadFront.glyph : "" }
  TextMetrics { id: leadTextM; font.family: stage.family; font.pixelSize: stage.f(13); font.bold: true; text: stage.leadFront && stage.leadFront.text ? stage.leadFront.text : "" }
  TextMetrics { id: clockM; font.family: stage.family; font.pixelSize: stage.f(13); font.bold: true; text: stage.clockText }
  function leadTextCap(l) { return l && l.wide ? s(260) : s(150) }
  readonly property real leadTextW: Math.min(leadTextM.advanceWidth, leadTextCap(leadFront))
  readonly property real leadW: !leadFront ? 0 : (leadFront.glyph ? leadGlyphM.advanceWidth : 0)
    + (leadFront.text ? (leadFront.glyph ? s(6) : 0) + leadTextW : 0)
  readonly property real clockW: Math.ceil(clockM.advanceWidth)
  readonly property real compactW: L.compactWidth(leadW, clockW, s(16), s(12))
  onCompactWChanged: retarget()
  onPopupOpenChanged: retarget()
  onCapHChanged: retarget()
  onWidthChanged: retarget()
  onAnchorXChanged: {
    if (!sp) return
    // a layout jump (the bar mapped, moved) is followed at once
    var cx = pillCenterTarget(sp.pw.target)
    if (Math.abs(cx - sp.px.x) > s(60)) L.place(sp.px, cx)
    retarget()
  }
  onLiveChanged: retarget()
  onReducedChanged: retarget()

  // ------------------------------------------------------------ the clock
  // Spring helpers: geometry springs (placed at once under Reduced Motion or
  // off screen); opacities spring, or fade in 150 ms under Reduced Motion.
  function go(sv, target, response, damping) { L.go(sv, target, response, damping, instant) }
  function fadeTo(sv, target, response) {
    if (sv.target === target && (sv.moving || sv.x === target)) return
    if (!live) L.place(sv, target)
    else if (reduced) L.fade(sv, target, L.tune.fade)
    else L.go(sv, target, response, 0.99)
  }

  property var sp: null
  // drawn: the capsule
  property real pillX: 0
  property real pillY: 0
  property real pillW: 0
  property real pillH: 0
  property real pillR: 0
  property real pillCx: 0
  // drawn: the content's opacities, the status crossfade
  property real compactAlpha: 1
  property real alertAlpha: 0
  property real mixValue: 1
  property bool swelling: false
  property bool wasAlert: false
  property real baseBottom: 0

  FrameAnimation {
    id: clock
    running: false
    onTriggered: stage.frame(Math.min(frameTime > 0 ? frameTime : 1 / 60, 1 / 30))
  }
  function wake() {
    if (manual || !sp) return
    if (!clock.running) clock.running = true
  }

  Component.onCompleted: {
    sp = {
      pw: L.spring(0), ph: L.spring(0), pt: L.spring(0), px: L.spring(anchorX),
      mix: L.spring(1, 0.002), compactA: L.spring(1, 0.002), alertA: L.spring(0, 0.002)
    }
    swapLead()
    retarget()
    var t = pillTargets()
    L.place(sp.pw, t.w); L.place(sp.ph, t.h); L.place(sp.pt, t.top); L.place(sp.px, pillCenterTarget(t.w))
    frame(0)
  }

  function pillTargets() {
    if (alertNow) return { w: alertW, h: Math.max(s(84), alertView.implicitHeight), top: capTop }
    if (popupOpen) return { w: compactW, h: tuckH, top: tuckTop }
    return { w: compactW, h: capH, top: capTop }
  }
  function pillCenterTarget(w) {
    return Math.max(w / 2 + s(8), Math.min(width - w / 2 - s(8), anchorX))
  }

  // kind: undefined (a plain change of size: a moving capsule keeps its
  // spring, a resting one morphs), "swell", "give", "gulp"
  function retarget(kind) {
    if (!sp) return
    var t = pillTargets()
    baseBottom = t.top + t.h
    var w = t.w, h = t.h
    var expanded = !!alertNow
    if (swelling && !expanded) { w += s(L.tune.swell); h += s(4) }
    var resp = L.tune.morphResponse, damp = L.tune.morphDamping
    if (expanded !== wasAlert) {
      resp = expanded ? L.tune.expandResponse : L.tune.shrinkResponse
      damp = expanded ? L.tune.expandDamping : L.tune.shrinkDamping
      wasAlert = expanded
    } else if (kind === "swell") { resp = L.tune.swellResponse; damp = L.tune.swellDamping }
    else if (kind === "give") { resp = L.tune.giveResponse; damp = L.tune.giveDamping }
    else if (kind === "gulp") { resp = L.tune.gulpResponse; damp = L.tune.gulpDamping }
    else if (sp.pw.moving || sp.ph.moving) { resp = undefined; damp = undefined }
    go(sp.pw, w, resp, damp)
    go(sp.ph, h, resp, damp)
    go(sp.pt, t.top, resp === undefined ? undefined : resp, damp === undefined ? undefined : Math.max(0.8, damp))
    go(sp.px, pillCenterTarget(t.w), L.tune.morphResponse, 0.9)
    contentTargets()
    wake()
  }

  // the compact content shows once the capsule is (nearly) compact again; the
  // alert once the island has (mostly) grown, and goes first
  function contentTargets() {
    if (!sp) return
    var t = pillTargets()
    if (alertNow) {
      fadeTo(sp.compactA, 0, 0.10)
      fadeTo(sp.alertA, sp.ph.x > 0.7 * t.h || instant ? 1 : sp.alertA.target, 0.22)
    } else {
      fadeTo(sp.alertA, 0, 0.08)
      fadeTo(sp.compactA, sp.ph.x < capH + s(30) || instant ? 1 : sp.compactA.target, 0.20)
    }
  }

  // A card about to pour: the capsule swells first, then gives.
  function swell() {
    if (alertNow || instant) return
    swelling = true
    retarget("swell")
  }
  function giveBack() {
    if (!swelling) return
    swelling = false
    retarget("give")
  }
  function swellingRow() {
    for (var r = 0; r < rowRep.count; r++) {
      var row = rowRep.itemAt(r)
      if (row && !row.finished && row.phase === "swell") return true
    }
    return false
  }
  // A card drawn back in: the capsule gulps it with a wobble.
  function gulp() {
    releaseHold()
    retarget("gulp")
    L.kick(sp.pw, L.tune.gulpWidth * unit, instant)
    L.kick(sp.ph, L.tune.gulpHeight * unit, instant)
    wake()
  }

  // One frame: step every spring, lay the cards out under the capsule, draw.
  function frame(dt) {
    if (!sp) return
    var moving = false
    var list = [sp.pw, sp.ph, sp.pt, sp.px, sp.mix, sp.compactA, sp.alertA]
    for (var i = 0; i < list.length; i++) if (L.tick(list[i], dt)) moving = true
    contentTargets()
    if (sp.compactA.moving || sp.alertA.moving) moving = true
    // the drawn capsule
    pillW = Math.max(1, sp.pw.x)
    pillH = Math.max(1, sp.ph.x)
    pillX = sp.px.x - pillW / 2
    pillY = sp.pt.x
    pillR = Math.min(pillH / 2, s(38))
    pillCx = sp.px.x
    compactAlpha = sp.compactA.x
    alertAlpha = sp.alertA.x
    mixValue = sp.mix.x
    // the capsules beside it
    var off = minGap, extra = 0
    for (var m = 0; m < minRep.count; m++) {
      var c = minRep.itemAt(m)
      if (!c) continue
      if (c.step(dt, off)) moving = true
      if (c.want) { off += c.wantW + minGap; extra += c.wantW + minGap }
    }
    extraWidth = extra
    // a held banner symbol whose card is not being drawn back lets go
    if (holdLead) {
      holdAge += dt
      var held = cardOf(holdLead.kind)
      if (!held || held.finished || (held.phase !== "draw" && holdAge > 0.5)) releaseHold()
      else moving = true
    }
    // the cards, top to bottom
    var y = baseBottom + gap
    for (var r = 0; r < rowRep.count; r++) {
      var row = rowRep.itemAt(r)
      if (!row || !row.sp) continue
      if (row.step(dt, y, y <= baseBottom + gap + 0.5)) moving = true
      var occ = row.occupy
      y += occ + rowGap * Math.min(1, occ / s(12))
    }
    // The capsule swells only for a card about to pour out of it. A card that
    // never poured (withdrawn mid-swell, taken into the island, gone with its
    // column) would otherwise leave it swollen over the bar beside its slot.
    if (swelling && !swellingRow()) { giveBack(); moving = true }
    draw()
    settled = !moving
    if (!moving) clock.running = false
  }

  // The liquid shape and the input region from the drawn geometry.
  function draw() {
    var keyA = alertShown || leadFront ? 0.45 : 0.16
    var boxes = [{ x: pillX, y: pillY, w: pillW, h: pillH, r: pillR, k: 0, a: 1, key: pillKey, keyAlpha: keyA }]
    place(pillArea, pillX, pillY, pillW, pillH)
    var hits = [rowHitA, rowHitB, rowHitC, rowHitD, rowHitE, rowHitF]
    var h = 0
    for (var r = 0; r < rowRep.count; r++) {
      var row = rowRep.itemAt(r)
      if (!row || !row.sp) continue
      var shown = row.ga > 0.001 && row.gw > 0.5 && row.gh > 0.5
      row.inShape = shown && boxes.length < 8
      if (row.inShape)
        boxes.push({ x: row.gx, y: row.gy, w: row.gw, h: row.gh, r: row.gr, k: row.gk, a: row.ga, key: row.keyTone, keyAlpha: row.keyAlpha })
      if (shown && row.ga > 0.5 && h < hits.length) place(hits[h++], row.gx, row.gy, row.gw, row.gh)
    }
    for (; h < hits.length; h++) place(hits[h], 0, 0, 0, 0)
    var mins = [minHitA, minHitB]
    for (var m = 0; m < 2; m++) {
      var c = minRep.itemAt(m)
      if (c && c.ga > 0.001 && c.gw > 0.5) {
        boxes.push({ x: c.gx, y: c.gy, w: c.gw, h: c.gh, r: c.gh / 2, k: c.gk, a: c.ga, key: c.keyTone, keyAlpha: 0.45 })
        place(mins[m], c.gx, c.gy, c.ga > 0.5 ? c.gw : 0, c.gh)
      } else place(mins[m], 0, 0, 0, 0)
    }
    liquid.boxes = boxes
  }
  function place(item, x, y, w, h) {
    item.x = x; item.y = y; item.width = Math.max(0, w); item.height = Math.max(0, h)
  }

  // the capsule's key line: the status colour (or the alert's, a banner's)
  readonly property color pillKeyWanted: alertShown && alertNow.tone ? tone(alertNow.tone)
    : leadFront && leadFront.tone ? tone(leadFront.tone) : ink
  property color pillKey: pillKeyWanted
  Behavior on pillKey { ColorAnimation { duration: stage.instant ? 0 : 200 } }
  onPillKeyChanged: wake()

  // ------------------------------------------------------------ drawing
  LiquidShape {
    id: liquid
    dpr: stage.dpr
    line: 1
  }

  // The capsule: its input region, its clicks (left opens the island's
  // popup, right the calendar, middle plays/pauses: BarWidget.pillPressed).
  Item {
    id: pillArea
    MouseArea {
      anchors.fill: parent
      enabled: !stage.alertShown
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { stage.pillPressed(mouse.button) }
    }
    HoverHandler { id: pillHover }
  }

  // compact: the status (its last value fading out under the new one) and the clock
  Item {
    id: compactView
    x: stage.pillX; y: stage.pillY
    width: stage.pillW; height: stage.pillH
    opacity: stage.compactAlpha
    visible: opacity > 0.01

    Repeater {
      model: 2
      delegate: Row {
        id: leadRow
        required property int index
        readonly property var info: index === 0 ? stage.leadBack : stage.leadFront
        x: stage.s(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: stage.s(6)
        opacity: !info ? 0 : (index === 0 ? 1 - stage.mixValue : stage.mixValue)
        visible: opacity > 0.01
        Text {
          visible: text !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: leadRow.info && leadRow.info.glyph ? leadRow.info.glyph : ""
          textFormat: Text.PlainText
          renderType: Text.NativeRendering
          font.family: stage.family
          font.pixelSize: stage.f(15)
          color: leadRow.info ? stage.tone(leadRow.info.tone) : stage.ink
        }
        Text {
          visible: text !== ""
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, stage.leadTextCap(leadRow.info))
          text: leadRow.info && leadRow.info.text ? leadRow.info.text : ""
          elide: Text.ElideRight
          textFormat: Text.PlainText
          renderType: Text.NativeRendering
          font.family: stage.family
          font.pixelSize: stage.f(13)
          font.bold: true
          font.features: { "tnum": 1 }
          color: leadRow.info ? stage.tone(leadRow.info.tone) : stage.ink
        }
      }
    }

    Text {
      id: clockLabel
      // right with a status beside it, centred without
      readonly property real rightX: stage.pillW - stage.s(16) - width
      readonly property real midX: (stage.pillW - width) / 2
      x: Math.round(stage.leadBack ? rightX * (1 - stage.mixValue) + (stage.leadFront ? rightX : midX) * stage.mixValue
                                   : (stage.leadFront ? midX + (rightX - midX) * stage.mixValue : midX))
      anchors.verticalCenter: parent.verticalCenter
      text: stage.clockText
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: stage.family
      font.pixelSize: stage.f(13)
      font.bold: true
      font.features: { "tnum": 1 }
      color: stage.ink
    }
  }

  // expanded: the alert, centred in the growing island
  DynamicAlert {
    id: alertView
    island: stage.island
    alert: stage.shownAlert ? ({ glyph: stage.shownAlert.glyph, tone: stage.tone(stage.shownAlert.tone),
                                 title: stage.shownAlert.title, subtitle: stage.shownAlert.subtitle,
                                 actions: stage.shownAlert.actions }) : null
    clock: stage.clockText
    ink: stage.ink
    width: stage.alertW
    height: implicitHeight
    x: stage.pillCx - width / 2
    y: stage.pillY
    opacity: stage.alertAlpha
    visible: opacity > 0.01
    enabled: stage.alertShown
    onImplicitHeightChanged: stage.retarget()
    onAction: function(id) { stage.alertAction(id) }
    onDismissed: stage.alertDismissed()
  }

  // ------------------------------------------------------------ minimal
  Repeater {
    id: minRep
    model: 2
    delegate: Item {
      id: cap
      required property int index
      readonly property var want: stage.minimalNow.length > index ? stage.minimalNow[index] : null
      property var shown: null
      property var sp: null
      // drawn
      property real gx: 0
      property real gy: 0
      property real gw: 0
      property real gh: 0
      property real ga: 0
      property real gk: 0
      property real goff: 0
      readonly property color keyTone: shown ? stage.tone(shown.tone) : stage.ink

      TextMetrics { id: capGlyph; font.family: stage.family; font.pixelSize: stage.f(14); text: cap.want && cap.want.glyph ? cap.want.glyph : "" }
      TextMetrics { id: capText; font.family: stage.family; font.pixelSize: stage.f(12); font.bold: true; text: cap.want && cap.want.text ? cap.want.text : "" }
      readonly property real wantW: !want ? 0 : Math.max(stage.capH, Math.ceil(
        (want.glyph ? capGlyph.advanceWidth : 0) + (want.text ? (want.glyph ? stage.s(5) : 0) + Math.min(capText.advanceWidth, stage.s(90)) : 0) + stage.s(28)))

      Component.onCompleted: {
        sp = { off: L.spring(0), w: L.spring(0), k: L.spring(0), a: L.spring(0, 0.002) }
        update()
      }
      // after its measures follow the new activity
      onWantChanged: Qt.callLater(update)
      onWantWChanged: if (sp && want) { stage.go(sp.w, wantW, L.tune.morphResponse, L.tune.morphDamping); stage.wake() }

      // bud out of the capsule, or be drawn back into it
      function update() {
        if (!sp) return
        if (want) {
          var fresh = !shown || sp.a.target <= 0
          shown = want
          if (fresh) {
            L.place(sp.w, wantW)
            if (stage.instant) {
              L.place(sp.off, 0); L.place(sp.k, 0)
              if (!stage.live) L.place(sp.a, 1); else { L.place(sp.a, 0); stage.fadeTo(sp.a, 1, 0.2) }
            } else {
              L.place(sp.off, -wantW); L.place(sp.k, stage.s(24)); L.place(sp.a, 1)
              stage.go(sp.k, 0, 0.60, 0.99)
            }
          } else stage.go(sp.w, wantW, L.tune.morphResponse, L.tune.morphDamping)
        } else if (shown) {
          if (stage.instant) stage.fadeTo(sp.a, 0, 0.2)
          else { stage.go(sp.off, -sp.w.x, L.tune.shrinkResponse, 0.9); stage.go(sp.k, stage.s(24), 0.25, 0.99) }
        }
        stage.wake()
      }

      function step(dt, slot) {
        if (!sp) return false
        var moving = false
        if (want && !stage.instant) stage.go(sp.off, slot, 0.50, L.tune.cardDamping)
        else if (want) L.place(sp.off, slot)
        var list = [sp.off, sp.w, sp.k, sp.a]
        for (var i = 0; i < list.length; i++) if (L.tick(list[i], dt)) moving = true
        // drawn back far enough: gone
        if (!want && shown && !stage.instant && sp.off.x <= -sp.w.x * 0.8 && sp.a.target > 0) { stage.fadeTo(sp.a, 0, 0.12); moving = true }
        if (!want && shown && sp.a.x <= 0.002 && !sp.a.moving) { shown = null; L.place(sp.k, 0) }
        gw = Math.max(0, sp.w.x)
        gh = stage.popupOpen ? stage.tuckH : stage.capH
        gx = stage.pillX + stage.pillW + sp.off.x
        gy = stage.pillY + (stage.pillH - gh) / 2
        ga = shown ? sp.a.x : 0
        gk = sp.k.x
        goff = sp.off.x
        return moving
      }

      Row {
        x: cap.gx + (cap.gw - width) / 2
        y: cap.gy + (cap.gh - height) / 2
        spacing: stage.s(5)
        opacity: cap.ga * Math.max(0, 1 - Math.max(0, -cap.goff) / Math.max(1, cap.gw * 0.5))
        visible: opacity > 0.01
        Text {
          visible: text !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: cap.shown && cap.shown.glyph ? cap.shown.glyph : ""
          textFormat: Text.PlainText
          renderType: Text.NativeRendering
          font.family: stage.family
          font.pixelSize: stage.f(14)
          color: cap.keyTone
        }
        Text {
          visible: text !== ""
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, stage.s(90))
          elide: Text.ElideRight
          text: cap.shown && cap.shown.text ? cap.shown.text : ""
          textFormat: Text.PlainText
          renderType: Text.NativeRendering
          font.family: stage.family
          font.pixelSize: stage.f(12)
          font.bold: true
          font.features: { "tnum": 1 }
          color: cap.keyTone
        }
      }
    }
  }
  Item {
    id: minHitA
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: { var c = minRep.itemAt(0); if (c && c.shown) stage.minimalPressed(c.shown.kind) }
    }
  }
  Item {
    id: minHitB
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: { var c = minRep.itemAt(1); if (c && c.shown) stage.minimalPressed(c.shown.kind) }
    }
  }

  // ------------------------------------------------------------ banners
  // input region of the first six cards (placed by draw())
  Item { id: rowHitA }
  Item { id: rowHitB }
  Item { id: rowHitC }
  Item { id: rowHitD }
  Item { id: rowHitE }
  Item { id: rowHitF }

  Repeater {
    id: rowRep
    model: stage.rows ? stage.rows.model : null
    onItemAdded: stage.wake()
    onItemRemoved: stage.wake()

    delegate: Item {
      id: row

      required property int index
      required property int key
      required property string kind
      required property bool leaving

      readonly property var entry: kind === "note" && stage.rows ? stage.rows.entryOf(key) : null
      readonly property bool queued: !!stage.rows && !!stage.rows.service
        && stage.rows.service.banners.some(function(b) { return b.key === row.key })
      readonly property bool open: !leaving && kind === "note" && stage.currentKey === key
      // the open alert note is the expanded island instead of a card
      readonly property bool inPill: open && stage.alertNoteKey === key
      // a card on its way out keeps the layout it had (no flip to a row)
      property bool shownOpen: false
      // (closed and no longer queued: it is about to leave, keep its layout)
      onOpenChanged: { if (!leaving && (open || stillQueued())) shownOpen = open; stage.wake() }
      function stillQueued() {
        var svc = stage.rows ? stage.rows.service : null
        return !!svc && svc.banners.some(function(b) { return b.key === row.key })
      }
      readonly property real restH: note.implicitHeight
      readonly property color rowTone: kind === "more" || !stage.island ? stage.ink : stage.tone(stage.island.noteTone(entry))
      readonly property color keyTone: rowTone
      readonly property real keyAlpha: shownOpen ? 0.35 : 0.22

      // swell → pour → rest; drop → rest; draw | fall | pill | gone
      property string phase: "new"
      property real t: 0
      property bool neckFree: false
      property bool textIn: false
      property bool swallowed: false
      property real sinceSwallow: 0
      property bool finished: false
      property var sp: null
      // drawn (set each frame)
      property real gx: 0
      property real gy: 0
      property real gw: 0
      property real gh: 0
      property real gr: 0
      property real gk: 0
      property real ga: 0
      property real gt: 0
      property real ncx: 0
      property real ncy: 0
      property real occupy: 0
      property real slotTop: 0
      property bool inShape: true
      property real stretchK: 0

      Component.onCompleted: {
        sp = { cx: L.spring(stage.cardCx), cy: L.spring(0), w: L.spring(0), h: L.spring(0), neck: L.spring(0),
               a: L.spring(0, 0.002), text: L.spring(0, 0.002), keep: L.spring(1, 0.002) }
        shownOpen = open
        begin()
      }
      Component.onDestruction: if (note.hovering) stage.hoverCount = Math.max(0, stage.hoverCount - 1)

      function home() { return { cx: stage.sp.px.x, cy: stage.pillY + stage.pillH / 2, w: stage.s(60), h: stage.s(12) } }
      function topNow() {
        var y = stage.baseBottom + stage.gap
        for (var i = 0; i < index; i++) {
          var o = rowRep.itemAt(i)
          if (o && o.sp) y += o.occupy + stage.rowGap * Math.min(1, o.occupy / stage.s(12))
        }
        return y
      }

      function begin() {
        var top = topNow()
        slotTop = top
        if (leaving) { finish(); return }
        if (inPill) { toPill(true); return }
        var cy = top + restH / 2
        if (stage.instant) {
          L.place(sp.cx, stage.cardCx); L.place(sp.cy, cy); L.place(sp.w, stage.cardW); L.place(sp.h, restH)
          L.place(sp.text, 1); L.place(sp.a, 0); stage.fadeTo(sp.a, 1, 0.2)
          phase = "rest"
        } else if (top <= stage.baseBottom + stage.gap + 0.5 && kind === "note") {
          // the first card pours out of the capsule
          var h = home()
          L.place(sp.cx, h.cx); L.place(sp.cy, h.cy); L.place(sp.w, h.w); L.place(sp.h, h.h)
          L.place(sp.a, 1); L.place(sp.text, 0); L.place(sp.neck, 0)
          phase = "swell"; t = 0
          stage.swell()
        } else {
          // a row under others drops into its place
          L.place(sp.cx, stage.cardCx); L.place(sp.cy, cy - stage.s(10)); L.place(sp.w, stage.cardW); L.place(sp.h, restH)
          L.place(sp.a, 0); L.place(sp.text, 1)
          stage.fadeTo(sp.a, 1, 0.18)
          stage.go(sp.cy, cy, 0.42, 0.86)
          phase = "drop"
        }
        stage.wake()
      }

      function pour() {
        phase = "pour"; t = 0
        stage.go(sp.neck, stage.instant ? 0 : stage.s(L.tune.neck), 0.10, 0.99)
        stage.go(sp.cy, slotTop + restH / 2, L.tune.cardResponse, L.tune.cardDamping)
        stage.go(sp.h, restH, 0.36, L.tune.cardDamping)
        stage.go(sp.w, stage.cardW, 0.50, L.tune.cardDamping)
        stage.go(sp.cx, stage.cardCx, 0.50, L.tune.cardDamping)
        stage.giveBack()
      }

      function draw() {
        phase = "draw"; t = 0; swallowed = false; sinceSwallow = 0
        stage.holdFor(key)
        stage.fadeTo(sp.text, 0, 0.08)
        var h = home()
        stage.go(sp.neck, stage.instant ? 0 : stage.s(L.tune.neck), 0.20, 0.99)
        stage.go(sp.w, h.w, 0.30, L.tune.closeDamping)
        stage.go(sp.h, h.h, 0.38, L.tune.closeDamping)
        stage.go(sp.cy, h.cy, 0.40, L.tune.closeDamping)
        stage.go(sp.cx, h.cx, 0.40, L.tune.closeDamping)
      }

      function fall() {
        phase = "fall"
        stage.fadeTo(sp.text, 0, 0.08)
        stage.fadeTo(sp.a, 0, 0.18)
        if (!stage.instant) stage.go(sp.keep, 0, 0.30, 0.99)
      }

      function toPill(now) {
        phase = "pill"
        if (now || stage.instant) { L.place(sp.a, 0); L.place(sp.keep, 0) }
        else { stage.fadeTo(sp.a, 0, 0.12); stage.go(sp.keep, 0, 0.30, 0.99) }
      }

      function back() {
        phase = "rest"; swallowed = false; neckFree = true; textIn = true
        stage.releaseHold()
        stage.go(sp.neck, 0, 0.30, 0.99)
        stage.fadeTo(sp.a, 1, 0.18)
        stage.fadeTo(sp.text, 1, 0.20)
        stage.go(sp.keep, 1, 0.30, 0.99)
        stage.go(sp.cy, slotTop + restH / 2, L.tune.cardResponse, L.tune.closeDamping)
        stage.go(sp.h, restH, 0.36, L.tune.closeDamping)
        stage.go(sp.w, stage.cardW, 0.50, L.tune.closeDamping)
        stage.go(sp.cx, stage.cardCx, 0.50, L.tune.closeDamping)
      }

      function finish() {
        if (finished) return
        finished = true
        phase = "gone"
        var q = stage.rows, k = key
        if (holdingLead()) stage.releaseHold()
        Qt.callLater(function() { if (q) q.finishLeave(k) })
      }
      function holdingLead() { return !!stage.holdLead && stage.holdLead.kind === "note:" + key }

      onLeavingChanged: {
        if (!sp || finished) return
        if (leaving) {
          if (phase === "pill" || phase === "new" || sp.a.x < 0.01) finish()
          else if (stage.instant) { phase = "fall"; stage.fadeTo(sp.text, 1, 0.01); stage.fadeTo(sp.a, 0, 0.2) }
          else if (slotTop <= stage.baseBottom + stage.gap + 0.5 && kind === "note") draw()
          else fall()
        } else back()
        stage.wake()
      }
      onInPillChanged: {
        if (!sp || finished || leaving) return
        if (inPill) toPill(false)
        else if (phase === "pill") {
          L.place(sp.keep, 1); L.place(sp.cx, stage.cardCx); L.place(sp.cy, slotTop + restH / 2 - stage.s(10))
          L.place(sp.w, stage.cardW); L.place(sp.h, restH); L.place(sp.text, 1)
          stage.fadeTo(sp.a, 1, 0.18)
          phase = "drop"
        }
        stage.wake()
      }
      onRestHChanged: stage.wake()

      // One frame: phase timing (as the prototype's loop), the springs, the
      // drawn box. `top` is where this row's slot starts; `first` whether
      // nothing is above it.
      function step(dt, top, first) {
        if (!sp) return false
        slotTop = top
        t += dt
        var pending = false
        var cy = top + restH / 2
        if (phase === "swell") {
          var h0 = home()
          L.place(sp.cx, h0.cx); L.place(sp.cy, h0.cy)
          if (t >= L.tune.swellHold || stage.instant) pour()
          pending = true
        } else if (phase === "pour") {
          stage.go(sp.cy, cy); stage.go(sp.h, restH); stage.go(sp.w, stage.cardW); stage.go(sp.cx, stage.cardCx)
          if (!neckFree && t >= L.tune.neckRelease) { neckFree = true; stage.go(sp.neck, 0, L.tune.neckResponse, 0.99) }
          if (!textIn && t >= L.tune.textAfter && sp.h.x > 0.75 * restH) { textIn = true; stage.fadeTo(sp.text, 1, 0.20) }
          if (neckFree && textIn && !sp.cy.moving && !sp.h.moving && !sp.w.moving && !sp.neck.moving && !sp.text.moving) {
            phase = "rest"
            sp.cy.response = 0.42; sp.cy.damping = 0.80; sp.h.response = 0.36; sp.h.damping = 0.80
          } else pending = true
        } else if (phase === "drop" || phase === "rest") {
          stage.go(sp.cy, cy); stage.go(sp.h, restH); stage.go(sp.w, stage.cardW); stage.go(sp.cx, stage.cardCx)
          if (phase === "drop" && !sp.cy.moving && !sp.a.moving) {
            phase = "rest"
            sp.cy.response = 0.42; sp.cy.damping = 0.80
          }
        } else if (phase === "draw") {
          var h1 = home()
          stage.go(sp.cy, h1.cy); stage.go(sp.cx, h1.cx)
          if (!swallowed && sp.cy.x < stage.pillY + stage.pillH) {
            swallowed = true
            stage.go(sp.neck, 0, 0.30, 0.99)
            stage.gulp()
          }
          if (swallowed) sinceSwallow += dt
          if (swallowed && (sinceSwallow > 0.6 || (sinceSwallow > 0.25 && !sp.cy.moving && !sp.neck.moving))) finish()
          pending = !finished
        } else if (phase === "fall") {
          if (!sp.a.moving && sp.a.x <= 0.002 && !sp.keep.moving) finish()
          pending = !finished
        }
        var moving = pending
        var list = [sp.cx, sp.cy, sp.w, sp.h, sp.neck, sp.a, sp.text, sp.keep]
        for (var i = 0; i < list.length; i++) if (L.tick(list[i], dt)) moving = true

        // squash and stretch with the fall (pour, draw)
        stretchK = phase === "pour" || phase === "draw" ? L.stretch(sp.cy.v, stage.unit) : 0
        var hw = Math.max(0.5, sp.w.x / 2 * (1 - stretchK * 0.6))
        var hh = Math.max(0.5, sp.h.x / 2 * (1 + stretchK))
        gw = hw * 2; gh = hh * 2
        gx = sp.cx.x - hw; gy = sp.cy.x - hh
        gr = Math.min(kind === "note" && shownOpen ? stage.s(24) : stage.s(20), hh, hw)
        gk = Math.max(0, sp.neck.x)
        ga = phase === "pill" && sp.a.x < 0.002 ? 0 : sp.a.x
        gt = sp.text.x
        ncx = sp.cx.x
        ncy = sp.cy.x
        // the room it takes in the column: the first row down to its bottom,
        // the others their height (shrinking as they go)
        occupy = phase === "pill" ? 0
          : first ? Math.max(0, sp.cy.x + sp.h.x / 2 - top) * (phase === "fall" ? sp.keep.x : 1)
          : sp.h.x * sp.keep.x
        return moving
      }

      // a plain card for rows past the shape's ten boxes
      Rectangle {
        visible: !row.inShape && row.ga > 0.01 && row.phase !== "pill"
        x: row.gx; y: row.gy; width: row.gw; height: row.gh
        radius: row.gr
        color: "#000000"
        opacity: row.ga
        border.width: 1
        border.color: Util.alpha(row.keyTone, row.keyAlpha)
      }

      DynamicNote {
        id: note
        island: stage.island
        entry: row.entry
        kind: row.kind
        moreCount: stage.rows ? stage.rows.hiddenCount : 0
        active: row.shownOpen
        stateLabel: row.open ? "now" : !row.queued ? "" : (row.entry && row.entry.shown ? "paused" : "next")
        tone: row.rowTone
        ink: stage.ink
        x: row.ncx - width / 2
        y: row.ncy - row.restH / 2
        width: stage.cardW
        opacity: row.gt * row.ga
        visible: opacity > 0.01 && row.phase !== "pill"
        enabled: !row.leaving && row.ga > 0.5
        onHoveringChanged: stage.hoverCount = Math.max(0, stage.hoverCount + (hovering ? 1 : -1))
        onOpened: stage.noteOpened(row.key)
        onDismissed: stage.noteDismissed(row.key)
        onLater: stage.noteLater(row.key)
        onAction: function(id) { stage.noteAction(row.key, id) }
        onPromoted: stage.notePromoted(row.key, row.kind)
      }
    }
  }
}
