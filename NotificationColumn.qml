import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import "views"
import "IslandModel.js" as Model
import "bridge" as Bridge

// Notifications in the bar: one column right under the island, rolling out
// of the bar's lower edge. The open card on top; the next ones wait as title
// rows under it and move up like a paternoster; a critical one (a requester)
// slides in on top and pauses the open card. Coming and going is mechanical:
// the head slides out of the edge, then the body unrolls; back the same way.
// Reduced motion: the same moments, faded instead of moved.
//
// A Lavur theme's bloom (material card.bloom): a drop falls out of the bar,
// grows into the card, then the text fades in; going back, the text fades,
// the card shrinks to a drop and is pulled back into the bar, leaving a faint
// residue for a moment. Every note is its own sheet of wet paper
// (views/InkSheet.qml): ink fills it, the water clears it from the top, the
// pigment dries into a rim at its calm edge; sheets never melt into each
// other (frame round 03.10.2026). Waiting rows hang under it as smaller ones.
//
// Only the cards take input; the strip never takes keyboard focus.
Item {
  id: column

  property var island: null
  property var service: null

  readonly property bool serving: !!island && island.columnNotes
  // theme material (edge "theme"): replaces window/bubble with the theme's card;
  // a Lavur theme's material blooms (card.bloom), every note a sheet of its own
  readonly property var material: island ? island.material : null
  readonly property bool bloom: !!material && !!material.card && material.card.bloom === true
  // metal family (Chrom & Platin): every note framed by a chrome tube
  readonly property var metal: material && material.metal ? material.metal : null
  // the bloom's pigment (tide colour) and its dried rim (card.rest)
  readonly property var tide: bloom ? material.card.tide || null : null
  readonly property var rest: bloom ? material.card.rest || null : null
  // the bloom's paper: the colour the bar ends in (opaque)
  readonly property color paper: Qt.rgba(Commons.Color.bar.background.r, Commons.Color.bar.background.g, Commons.Color.bar.background.b, 1)
  readonly property bool lightBar: 0.2126 * paper.r + 0.7152 * paper.g + 0.0722 * paper.b > 0.55
  readonly property bool bubble: !material && !!island && island.noteStyle === "bubble"
  readonly property real cardW: island ? island.s(480) : 480
  readonly property bool reduced: Style.reduceMotion

  // Bloom geometry: the area reaches `bloomMargin` past the cards on every
  // side (and up into the bar), so the blur never runs into its edge.
  readonly property real bloomMargin: 32
  readonly property real bloomGap: island ? island.s(8) : 8
  readonly property real dropW: island ? island.s(52) : 52
  readonly property real dropH: island ? island.s(28) : 28

  // What belongs on screen, top to bottom: the open card, two waiting rows,
  // "+N" for the rest.
  readonly property var wanted: {
    if (!serving || !service || !service.current) return []
    var out = [{ key: service.current.key, kind: "note" }]
    var w = service.waiting
    for (var i = 0; i < w.length && i < Model.maxWaitingRows; i++) out.push({ key: w[i].key, kind: "note" })
    if (w.length > Model.maxWaitingRows) out.push({ key: -1, kind: "more" })
    return out
  }
  readonly property int hiddenCount: service ? Math.max(0, service.waiting.length - Model.maxWaitingRows) : 0

  // Entries by key, kept while their row is still rolling away.
  property var cache: ({})
  function entryOf(key) {
    if (service) {
      var b = service.banners
      for (var i = 0; i < b.length; i++) if (b[i].key === key) return b[i]
    }
    return cache[key] || null
  }

  ListModel { id: rows }   // { key, kind, leaving }

  onWantedChanged: Qt.callLater(sync)

  function indexOfKey(key) {
    for (var i = 0; i < rows.count; i++) if (rows.get(i).key === key) return i
    return -1
  }
  // Where the n-th wanted row goes: before the n-th row that is not leaving.
  function slotIndex(n) {
    var seen = 0
    for (var i = 0; i < rows.count; i++) {
      if (rows.get(i).leaving) continue
      if (seen === n) return i
      seen++
    }
    return rows.count
  }

  function sync() {
    var want = wanted
    var keys = want.map(function(w) { return w.key })
    var nextCache = {}
    for (var c = 0; c < want.length; c++) {
      var e = entryOf(want[c].key)
      if (e) nextCache[want[c].key] = e
    }
    for (var i = 0; i < rows.count; i++) {
      var r = rows.get(i)
      if (keys.indexOf(r.key) === -1) {
        if (cache[r.key]) nextCache[r.key] = cache[r.key]
        if (!r.leaving) rows.setProperty(i, "leaving", true)
      }
    }
    cache = nextCache
    for (var j = 0; j < want.length; j++) {
      var at = indexOfKey(want[j].key)
      var target = slotIndex(j)
      if (at === -1) {
        rows.insert(Math.min(target, rows.count), { key: want[j].key, kind: want[j].kind, leaving: false })
        continue
      }
      if (rows.get(at).leaving) rows.setProperty(at, "leaving", false)
      if (at !== target && target < rows.count) rows.move(at, target, 1)
    }
    if (rows.count > 0) latchAnchor()
  }

  // A row has rolled away completely.
  function finishLeave(key) {
    var i = indexOfKey(key)
    if (i !== -1 && rows.get(i).leaving) rows.remove(i)
  }

  // ------------------------------------------------------------ placement
  // The column hangs from the island in the bar on the focused monitor.
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    for (var i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i]
    return island ? island.targetScreen : (screens.length ? screens[0] : null)
  }
  property real anchorX: -1
  property var latchedScreen: null
  // Screen and x are taken together when the first card comes, so the
  // column stays put (on its monitor, under its island) while the queue
  // lasts, even if focus moves or the segment beside the clock grows.
  function latchAnchor() {
    if (anchorX >= 0 && latchedScreen) return
    latchedScreen = targetScreen
    var name = latchedScreen ? latchedScreen.name : ""
    var list = Bridge.IslandBus.list
    var pick = null
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].screenName === name) pick = list[i]
    if (!pick && list.length) pick = list[0]
    anchorX = pick && typeof pick.anchorX === "function" ? pick.anchorX() : (latchedScreen ? latchedScreen.width / 2 : 960)
  }
  Connections {
    target: rows
    function onCountChanged() { if (rows.count === 0) { column.anchorX = -1; column.latchedScreen = null } }
  }

  PanelWindow {
    id: win

    screen: column.latchedScreen || column.targetScreen
    visible: column.serving && rows.count > 0
    anchors { top: true; left: true; right: true }
    // Tall enough for a requester, two rows and "+N"; only the cards take input.
    implicitHeight: island ? island.s(560) : 560
    color: "transparent"

    WlrLayershell.namespace: "tusche-island-notes"
    WlrLayershell.layer: island && island.setting("layer", "top") === "overlay" ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Below the bar (its exclusive zone), without reserving space of its own.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    mask: Region { item: stack }

    // Bloom: the notes' sheets (moved in below), over the faint residue
    // (blurred) where a note has just left.
    Item {
      id: bloomArea
      visible: column.bloom
      x: stack.x - column.bloomMargin
      y: -column.bloomMargin
      width: column.cardW + column.bloomMargin * 2
      height: win.height + column.bloomMargin

      Item {
        id: ghostLayer
        anchors.fill: parent
        // enabled only while shown: a MultiEffect created hidden never draws
        layer.enabled: ghostLayer.visible
        layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 48; autoPaddingEnabled: false }
      }
    }

    Column {
      id: stack
      readonly property real dpr: win.devicePixelRatio > 0 ? win.devicePixelRatio : 1
      x: Math.round(Math.max(0, Math.min(win.width - width, column.anchorX - width / 2)) * dpr) / dpr
      y: column.bloom ? 2 : 0
      width: column.cardW
      spacing: 0

      HoverHandler {
        onHoveredChanged: if (column.service) column.service.columnHovered = hovered
      }

      Repeater {
        model: rows

        delegate: Item {
          id: slot

          required property int index
          required property int key
          required property string kind
          required property bool leaving

          readonly property var entry: kind === "note" ? column.entryOf(key) : null
          readonly property bool queued: !!column.service && column.service.banners.some(function(b) { return b.key === slot.key })
          readonly property bool open: !leaving && kind === "note" && !!column.service
            && !!column.service.current && column.service.current.key === key
          // presence: 0 = still inside the bar (or under the row above), 1 = out
          property real presence: 0
          property real openness: 0
          // Plain values (set once below): switching the style or reduced
          // motion later must not collapse a card that is already out.
          property real spread: 1
          property real fade: 1
          property bool arrived: false
          // Bloom: the text, faded in once the sheet has grown.
          property real ink: 1
          // Bloom (Lavur): ink fills the sheet, the water clears it from the
          // bar edge downwards and pushes the pigment into its edge, where it
          // dries into the rim; while wet the edge is soft and drifts
          property real clearing: 1
          property real wet: 0
          property real phase: 0
          // Reduced Motion switched on while it is still wet: dry at once
          Connections {
            target: column
            function onReducedChanged() { if (column.reduced && wetting.running) { wetting.stop(); slot.clearing = 1; slot.wet = 0 } }
          }
          ParallelAnimation {
            id: wetting
            SequentialAnimation {
              PauseAnimation { duration: 150 }
              NumberAnimation { target: slot; property: "clearing"; from: 0; to: 1; duration: 650; easing.type: Easing.InOutQuad }
            }
            NumberAnimation { target: slot; property: "wet"; from: 1; to: 0; duration: 1600; easing.type: Easing.InQuad }
            NumberAnimation { target: slot; property: "phase"; from: 0; to: 6.283; duration: 1600 }
          }

          // Bloom: a drop (dropW × dropH) grows into the row, then the body.
          readonly property real bloomGap: index > 0 ? column.bloomGap : 0
          readonly property real blobW: column.dropW + (column.cardW - column.dropW) * spread
          readonly property real blobH: presence * column.dropH * (1 - spread) + note.rowH * spread
            + note.bodyH * Math.max(0, Math.min(1, openness))

          width: column.cardW
          height: column.bloom ? bloomGap + blobH
            : Math.max(0, note.visibleH - (1 - presence) * note.rowH)
          // The card is clipped by `cardClip` below (it slides out of the bar's
          // edge); the material's shadow and halo sit outside that clip.

          // This row's bloom shape in the bloom area's coordinates (drawn by
          // its sheet below; the residue takes it over when the row leaves).
          Item {
            id: blob
            visible: false
            x: column.bloomMargin + (column.cardW - slot.blobW) / 2
            y: column.bloomMargin + stack.y + slot.y + slot.bloomGap
            width: slot.blobW
            height: slot.blobH
          }
          // Bloom (Lavur): this note's own sheet of wet paper (moved into the
          // bloom area below) – the paper, the wet ink cleared from its top and
          // the dried rim. Sized for the whole card (no layer is resized
          // while it grows); only the first one flares up into the bar.
          InkSheet {
            id: sheet
            readonly property real pad: 40
            visible: column.bloom && slot.presence > 0
            opacity: slot.fade
            x: column.bloomMargin - pad
            y: blob.y - pad
            width: column.cardW + 2 * pad
            height: Math.max(column.dropH, note.rowH) + note.bodyH + 2 * pad
            blobX: blob.x - x
            blobY: pad
            blobW: blob.width
            blobH: blob.height
            radius: column.island.s(12)
            neck: slot.index === 0
            flare: column.island.s(14)
            barY: column.bloomMargin - y
            originX: pad
            originY: pad
            paper: column.paper
            ink: column.tide ? Qt.color(column.tide.color || "#000000") : column.island.fg
            light: column.lightBar
            rest: column.rest
            haloBase: column.material && column.material.card ? column.material.card.halo || null : null
            clearing: slot.clearing
            wet: slot.wet
            phase: slot.phase
            sourceX: blob.x + blob.width / 2 - x
            sourceY: pad - 2
            reach: Math.hypot(blob.width / 2, blob.height) + 30
            inkTop: pad - 4
            band: 40
            jitter: 18
            seed: 3 + slot.index
          }
          // A faint residue where the card was, fading after it left.
          Rectangle {
            id: ghost
            visible: column.bloom && opacity > 0
            opacity: 0
            radius: column.island.s(12)
            color: column.paper
          }

          // material (theme edge): the hard ink shadow (Papier) or the halo
          // (Tusche, Lavur) of the visible part of the card
          readonly property var matShade: column.material && column.material.card
            ? (column.material.card.shadow || null) : null
          readonly property var matHalo: column.material && column.material.card
            ? (column.material.card.halo || column.material.card.glow || null) : null
          Rectangle {
            visible: !!slot.matShade && slot.height > 0
            x: slot.matShade ? slot.matShade.dx || 0 : 0
            y: slot.matShade ? slot.matShade.dy || 0 : 0
            width: slot.width
            height: slot.height
            opacity: slot.fade
            color: slot.matShade ? note.rgba(slot.matShade.color, slot.matShade.alpha) : "transparent"
          }
          Item {
            id: haloBox
            readonly property real spread: 40
            // (a bloom's sheet brings its own halo)
            visible: !!slot.matHalo && slot.height > 0 && !column.bloom
            x: -spread
            y: -spread + (column.material && column.material.card && column.material.card.halo ? 6 : 0)
            width: slot.width + 2 * spread
            height: slot.height + 2 * spread
            opacity: slot.fade
            layer.enabled: visible
            layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: slot.matHalo ? Math.min(64, slot.matHalo.blur || 32) : 32; autoPaddingEnabled: false }
            Rectangle {
              x: haloBox.spread; y: haloBox.spread
              width: parent.width - 2 * haloBox.spread; height: parent.height - 2 * haloBox.spread
              color: slot.matHalo ? note.rgba(slot.matHalo.color, slot.matHalo.alpha) : "transparent"
            }
          }

          // metal family: a chrome rim around the visible part of the card,
          // glinting once as the note comes out of the bar
          MetalShape {
            id: noteMetal
            z: 2
            visible: !!column.metal && slot.height > 1 && !column.bloom && !(column.material && column.material.glass && column.material.glass.enabled !== false)
            spec: column.metal
            pad: 3
            x: -pad
            y: -pad
            width: slot.width + 2 * pad
            height: slot.height + 2 * pad
            opacity: slot.fade
            onVisibleChanged: if (visible) play()
          }

          Item {
            id: cardClip
            width: slot.width
            height: slot.height
            clip: true

            NoteCard {
              id: note
              y: column.bloom ? slot.bloomGap : -(1 - slot.presence) * rowH
              width: parent.width
              island: column.island
              entry: slot.entry
              kind: slot.kind
              moreCount: column.hiddenCount
              bubble: column.bubble
              bloom: column.bloom
              material: column.material
              textIn: slot.ink
              first: slot.index === 0
              active: slot.open
              // A row that is going (dismissed, answered) keeps no label rather
              // than flipping to "paused" while it rolls away.
              stateLabel: slot.open ? "now" : !slot.queued ? "" : (slot.entry && slot.entry.shown ? "paused" : "next")
              openness: slot.openness
              spread: slot.spread
              tone: column.island.noteTone(slot.entry)
              opacity: slot.fade

              onOpened: column.island.notificationOpen(slot.key)
              onDismissed: column.island.notificationDismiss(slot.key)
              onLater: column.service.later(slot.key)
              onAction: function(id) { column.island.notificationAction(slot.key, id) }
              onPromoted: {
                if (slot.kind === "more") {
                  var w = column.service.waiting
                  if (w.length > Model.maxWaitingRows) column.service.promote(w[Model.maxWaitingRows].key)
                } else column.service.promote(slot.key)
              }
            }
          }

          // Mechanical: constant speed, hard stop, Omarchy's short
          // durations. Reduced motion: final geometry, faded.
          // The target is set here, not bound: a binding to `open` may not
          // have updated yet when onOpenChanged starts the animation.
          function run(anim) {
            arrive.stop(); unroll.stop(); depart.stop(); arriveBloom.stop(); departBloom.stop()
            if (anim === unroll) {
              unroll.to = open ? 1 : 0
              unroll.duration = open ? 220 : 180
              // interrupted the bloom's arrival before its text faded in
              if (column.bloom) ink = 1
            }
            anim.start()
          }
          // Bloom: a drop, then it swells into the row (eased, liquid rather
          // than mechanical), the body follows, the text fades in last.
          SequentialAnimation {
            id: arriveBloom
            NumberAnimation { target: slot; property: "presence"; to: 1; duration: 190; easing.type: Easing.OutQuad }
            NumberAnimation { target: slot; property: "spread"; to: 1; duration: 280; easing.type: Easing.OutCubic }
            ScriptAction { script: { slot.arrived = true; if (slot.open) { unroll.to = 1; unroll.duration = 200; unroll.start() } } }
            PauseAnimation { duration: slot.open ? 180 : 0 }
            NumberAnimation { target: slot; property: "ink"; to: 1; duration: 140; easing.type: Easing.Linear }
          }
          // Back: text first, then the sheet shrinks to a drop (a faint
          // residue stays where it was) and the drop is pulled into the bar.
          SequentialAnimation {
            id: departBloom
            NumberAnimation { target: slot; property: "ink"; to: 0; duration: 110; easing.type: Easing.Linear }
            ScriptAction {
              script: {
                ghost.x = blob.x; ghost.y = blob.y; ghost.width = blob.width; ghost.height = blob.height
                ghost.opacity = 0.16
              }
            }
            ParallelAnimation {
              SequentialAnimation {
                ParallelAnimation {
                  NumberAnimation { target: slot; property: "openness"; to: 0; duration: 220; easing.type: Easing.InOutCubic }
                  NumberAnimation { target: slot; property: "spread"; to: 0; duration: 220; easing.type: Easing.InOutCubic }
                }
                NumberAnimation { target: slot; property: "presence"; to: 0; duration: 170; easing.type: Easing.InQuad }
              }
              NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: 700; easing.type: Easing.InQuad }
            }
            ScriptAction { script: column.finishLeave(slot.key) }
          }
          SequentialAnimation {
            id: arrive
            NumberAnimation { target: slot; property: "presence"; to: 1; duration: column.bubble ? 120 : 160; easing.type: Easing.Linear }
            NumberAnimation { target: slot; property: "spread"; to: 1; duration: column.bubble ? 130 : 0; easing.type: Easing.Linear }
            ScriptAction { script: { slot.arrived = true; slot.run(unroll) } }
          }
          NumberAnimation { id: unroll; target: slot; property: "openness"; easing.type: Easing.Linear }
          SequentialAnimation {
            id: depart
            NumberAnimation { target: slot; property: "openness"; to: 0; duration: 180; easing.type: Easing.Linear }
            NumberAnimation { target: slot; property: "presence"; to: 0; duration: 160; easing.type: Easing.Linear }
            ScriptAction { script: column.finishLeave(slot.key) }
          }
          // Reduced motion: fade in or out at the final geometry.
          NumberAnimation { id: fadeIn; target: slot; property: "fade"; to: 1; duration: 150 }
          SequentialAnimation {
            id: fadeOut
            NumberAnimation { target: slot; property: "fade"; to: 0; duration: 150 }
            ScriptAction { script: column.finishLeave(slot.key) }
          }

          Component.onCompleted: {
            // The residue and the sheet live in the column's bloom area (they
            // leave with this row: it still owns them).
            ghost.parent = ghostLayer
            sheet.parent = bloomArea
            if (column.bloom && !column.reduced) { clearing = 0; wet = 1; phase = 0; wetting.start() }
            if (column.reduced) {
              presence = 1; spread = 1; arrived = true; fade = 0; ink = 1
              openness = open ? 1 : 0
              fadeIn.start()
            } else if (column.bloom) {
              spread = 0; ink = 0
              run(arriveBloom)
            } else {
              spread = column.bubble ? 0 : 1
              run(arrive)
            }
          }
          onOpenChanged: {
            if (column.reduced) { openness = open ? 1 : 0; return }
            if (arrived && !leaving) run(unroll)
          }
          onLeavingChanged: {
            if (column.reduced) {
              if (leaving) fadeOut.start()
              else { fadeOut.stop(); fade = 1 }
              return
            }
            if (leaving) run(column.bloom ? departBloom : depart)
            else {
              // Back before it was gone: finish whatever its arrival left.
              presence = 1; spread = 1; arrived = true; ink = 1; ghost.opacity = 0
              run(unroll)
            }
          }
        }
      }
    }
  }
}
