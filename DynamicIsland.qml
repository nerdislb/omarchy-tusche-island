import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "views"
import "IslandModel.js" as Model
import "bridge" as Bridge

// The island's dynamic look (Island.qml `look: "dynamic"`): Apple's Dynamic
// Island in Omarchy's top bar. The bar is only as tall as its strip, so the
// island cannot hang below it from there; instead every bar that holds the
// island gets one more layer-shell window over it (the overlay layer, above
// the bar's top layer, ignoring the bar's exclusive zone so it starts at the
// screen's top edge). It draws the island (views/DynamicStage.qml) centred on
// the island's slot in the bar, which keeps that slot free (BarWidget.qml).
//
// Only what is drawn takes input (the capsule, the capsules beside it, the
// cards); the rest of the window passes clicks through to the bar and the
// windows below, and it never takes the keyboard. The notes and the expanded
// island show on one monitor: where the notes column latched (the focused
// monitor when the first note came), as in the classic look. Under a
// fullscreen window the window goes too; while the bar is hidden it only
// comes for a banner or an expanded island.
Item {
  id: dyn

  property var island: null
  property var service: null
  property var column: null          // NotificationColumn: its rows and their monitor

  readonly property bool on: !!island && island.dynamicLook
  readonly property var widgets: on
    ? Bridge.IslandBus.list.filter(function(w) { return !!w && w.dynamicCapable === true && !!w.barScreen }) : []

  // The bar hidden by `omarchy-toggle-bar` (its `bar-off` flag, watched the
  // way the bar watches it; a plugin's bar API does not say).
  property bool barOff: false
  onOnChanged: if (on) barOffProbe.running = true
  Component.onCompleted: if (on) barOffProbe.running = true
  Process {
    id: barOffProbe
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { dyn.barOff = String(line).trim() === "yes" } }
  }
  FileView {
    path: dyn.on ? Quickshell.env("HOME") + "/.local/state/omarchy/toggles" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: barOffProbe.running = true
  }

  readonly property string notesScreen: column && column.latchedScreen ? String(column.latchedScreen.name || "") : ""
  // (a monitor without a top bar holding the island passes on to the next)
  function showsHere(name) {
    function has(n) { return n !== "" && widgets.some(function(w) { return w.screenName === n }) }
    if (has(notesScreen)) return name === notesScreen
    var focused = island ? String(island.focusedScreenName || "") : ""
    if (has(focused)) return name === focused
    return widgets.length > 0 && widgets[0].screenName === name
  }

  Variants {
    model: dyn.widgets

    delegate: PanelWindow {
      id: win

      required property var modelData
      readonly property var widget: modelData
      readonly property string screenName: widget ? String(widget.screenName || "") : ""
      readonly property bool here: dyn.showsHere(screenName)
      // Under a fullscreen window it goes, as the bar fades (and as the
      // classic column hides under it). With the bar hidden only a banner or
      // an expanded island brings it out, as the classic column still shows.
      readonly property bool fullscreen: !!widget && Commons.Compositor.fullscreenOn(screenName)
      readonly property bool barGone: dyn.barOff || (!!widget && widget.barHidden === true)
      readonly property bool busy: here && ((!!dyn.column && dyn.column.rows.count > 0) || (!!dyn.island && !!dyn.island.dynamicAlert))

      screen: widget ? widget.barScreen : null
      // (the bar's screen, not this window's own `screen`: the window resets
      // that as it maps, which looped the binding)
      visible: dyn.on && !!(widget && widget.barScreen) && !fullscreen && (!barGone || busy)
      anchors { top: true; left: true; right: true }
      // the expanded island, a requester and the rows under it
      implicitHeight: dyn.island ? dyn.island.s(560) : 560
      color: "transparent"

      WlrLayershell.namespace: "tusche-island-dynamic"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // From the screen's top edge, over the bar; reserves nothing.
      exclusionMode: ExclusionMode.Ignore

      mask: Region {
        item: stage.pillHit
        Region { item: stage.minHit0; intersection: Intersection.Combine }
        Region { item: stage.minHit1; intersection: Intersection.Combine }
        Region { item: stage.rowHit0; intersection: Intersection.Combine }
        Region { item: stage.rowHit1; intersection: Intersection.Combine }
        Region { item: stage.rowHit2; intersection: Intersection.Combine }
        Region { item: stage.rowHit3; intersection: Intersection.Combine }
        Region { item: stage.rowHit4; intersection: Intersection.Combine }
        Region { item: stage.rowHit5; intersection: Intersection.Combine }
      }

      DynamicStage {
        id: stage
        anchors.fill: parent
        island: dyn.island
        rows: win.here && dyn.column ? dyn.column.queue : null
        anchorX: win.widget ? win.widget.sceneCenterX : width / 2
        barH: win.widget ? win.widget.barThickness : 30
        popupOpen: !!win.widget && win.widget.opened === true
        ownsAlert: win.here
        live: win.visible
        dpr: win.devicePixelRatio > 0 ? win.devicePixelRatio : 1

        onPillPressed: function(button) { if (win.widget) win.widget.pillPressed(button) }
        onMinimalPressed: function(kind) { if (win.widget) win.widget.openFocused(kind) }
        onNoteOpened: function(key) { dyn.island.notificationOpen(key) }
        onNoteDismissed: function(key) { dyn.island.notificationDismiss(key) }
        onNoteLater: function(key) { dyn.service.later(key) }
        onNoteAction: function(key, id) { dyn.island.notificationAction(key, id) }
        onNotePromoted: function(key, kind) {
          if (kind === "more") {
            var w = dyn.service.waiting
            if (w.length > Model.maxWaitingRows) dyn.service.promote(w[Model.maxWaitingRows].key)
          } else dyn.service.promote(key)
        }
        onAlertAction: function(id) { dyn.island.dynamicAlertAction(id) }
        onAlertDismissed: dyn.island.dynamicAlertAction("dismiss")
        // the pointer on the capsule holds the quiet line, as on the bar
        onPillHoveredChanged: if (dyn.island) dyn.island.barHovered = pillHovered
      }

      // The bar keeps the slot the capsule and the capsules beside it take.
      Binding { target: win.widget; property: "dynamicPill"; value: stage.slotWidth; when: !!win.widget }
      Binding { target: win.widget; property: "dynamicExtra"; value: stage.extraWidth; when: !!win.widget }
      // The pointer on the cards (or an expanded agent note) holds their time;
      // on an expanded battery or timer alert, the alert's.
      Binding {
        target: dyn.service
        property: "columnHovered"
        value: stage.notesHovered || (stage.alertHovered && !!dyn.island.dynamicAlert && dyn.island.dynamicAlert.source === "note")
        when: win.here && !!dyn.service
      }
      Binding { target: dyn.island; property: "dynamicHold"; value: stage.alertHovered; when: win.here && !!dyn.island }
    }
  }
}
