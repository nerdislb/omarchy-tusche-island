import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "views"
import "IslandModel.js" as Model
import "bridge" as Bridge

// The island as the bar's clock. At rest it is the time; when something is
// live (agents, a timer, music, a meeting about to start, a recording) or
// announces itself (a finished agent, a limit, a track change) a tinted
// segment grows beside the time. A click opens the island as a native bar
// popup, the same card, gap, border and dismissal as every other bar popup.
//
// The state and sources live in the panel (Island.qml); this widget only
// draws them. The two meet through Bridge.IslandBus.
//
//   left click    open / close the island
//   right click   the calendar
//   middle click  play / pause
//
// When the island serves notifications, a bell segment follows the clock:
//   left click    the inbox      right click   do not disturb
BarWidget {
  id: root
  moduleName: "nerdibeard.tusche-island"

  readonly property var island: Bridge.IslandBus.island
  readonly property bool live: island !== null && island.barMode

  // One popup, from the widget that was clicked (or the first one, when the
  // island is opened over IPC). Matters only with a bar on several monitors.
  // Opened over IPC or a keybind (no click): the bar on the focused monitor.
  readonly property string screenName: button.QsWindow.window && button.QsWindow.window.screen
    ? button.QsWindow.window.screen.name : ""
  readonly property bool onFocusedScreen: !!island && island.focusedScreenName !== "" && island.focusedScreenName === screenName
  readonly property bool popupOwner: Bridge.IslandBus.owner === root
    || (Bridge.IslandBus.owner === null && Bridge.IslandBus.pick(onFocusedScreen, root))

  Component.onCompleted: Bridge.IslandBus.register(root)
  Component.onDestruction: Bridge.IslandBus.unregister(root)
  // A closed popup forgets who opened it, so the next summon follows focus.
  onOpenedChanged: if (!opened && Bridge.IslandBus.owner === root) Bridge.IslandBus.owner = null

  // ------------------------------------------------------------------
  // Bar popout contract (Bar.findPanelWidget / requestPopout)
  // ------------------------------------------------------------------
  readonly property bool opened: live && island.userExpanded && popupOwner
  property bool popoutSwitchClosing: false

  function open() {
    if (!live) return
    Bridge.IslandBus.owner = root
    island.expand()
  }
  function close() { if (live && island.userExpanded) island.collapse() }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  // Where the notification column hangs (x in the bar window = on screen).
  function anchorX() {
    var p = button.mapToItem(null, button.width / 2, 0)
    return p ? p.x : 0
  }
  // how wide the island is there (a float note grows out of its lower edge)
  function anchorWidth() { return button.width }

  // ------------------------------------------------------------------
  // Dynamic look (Island.qml `look: "dynamic"`): DynamicIsland.qml draws the
  // island as a black capsule over this bar. The widget keeps the capsule's
  // slot (and the minimal capsules' beside it) and paints nothing there; the
  // bell stays. Only on a top bar; elsewhere the classic look stays.
  // ------------------------------------------------------------------
  readonly property bool dynamicCapable: !vertical && (!bar || bar.position === undefined || String(bar.position) === "top")
  readonly property bool dyn: live && island.dynamicLook && dynamicCapable
  readonly property var barScreen: button.QsWindow.window ? button.QsWindow.window.screen : null
  readonly property bool barHidden: !!bar && bar.barHidden === true
  readonly property int barThickness: bar && typeof bar.barSizeFor === "function" && screenName !== ""
    ? bar.barSizeFor(screenName) : barSize
  // the capsule's centre in the bar's window (= on its screen), live
  readonly property real sceneCenterX: {
    var x = button.x + button.width / 2
    for (var p = root; p; p = p.parent) x += p.x
    return x
  }
  // set by the overlay: the compact capsule's width and the capsules beside it
  property real dynamicPill: 0
  property real dynamicExtra: 0
  // the bar makes room as the capsule grows, on the capsule's own spring
  SpringValue { id: dynPill; target: root.dynamicPill; response: 0.40; damping: 0.78; live: button.visible }
  SpringValue { id: dynExtra; target: root.dynamicExtra; response: 0.40; damping: 0.78; live: button.visible }

  // The island's buttons: left opens (or opens the quiet line), right the
  // calendar, middle plays/pauses – from the bar or from the capsule over it.
  function pillPressed(b) {
    if (!live) return
    if (b === Qt.RightButton) {
      Bridge.IslandBus.owner = root
      island.openCalendar()
    } else if (b === Qt.MiddleButton) {
      if (island.hasMedia) island.mediaToggle()
    } else if (island.columnNotes && island.noteLine) {
      // The low-urgency line is the island's: a click opens it.
      island.notificationOpen(island.noteLine.key)
    } else {
      toggle()
    }
  }
  // A minimal capsule clicked: the island opens on that activity.
  function openFocused(kind) {
    if (!live) return
    if (kind === "inbox") { toggleInbox(); return }
    Bridge.IslandBus.owner = root
    island.openFocus = kind === "agents" ? "" : kind
    island.expand()
  }

  function toggleInbox() {
    if (!live) return
    if (opened && island.inboxOpen) { close(); return }
    Bridge.IslandBus.owner = root
    island.openInbox()
  }

  readonly property real openPanelIndicatorWidth: clockLabel.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // ------------------------------------------------------------------
  // What the bar shows
  // ------------------------------------------------------------------
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  readonly property string clockText: Qt.formatDateTime(clock.date, String(setting("format", "HH:mm")))

  function glyphFor(name) {
    if (!island) return ""
    if (name === "media") return island.mediaPlaying ? "󰝚" : "󰏤"
    if (name === "timer") return "󰔛"
    if (name === "stopwatch") return "󱎫"
    if (name === "activity") return island.activity ? island.activity.icon : "󰄬"
    if (name === "recording") return "󰑊"
    if (name === "calendar") return "󰃭"
    if (name === "mic") return island.cameraActive ? "󰄀" : "󰍬"
    if (name === "inbox") return "󰂚"
    return ""
  }

  // The live segment: { glyph, text, tone, progress (-1 none) }, or null.
  readonly property var segment: {
    if (!live || island.userExpanded) return null
    var h = island.hud
    // Low urgency: one still line, the island's own voice for small news.
    var ln = island.noteLine
    if (ln && !h)
      return { glyph: ln.glyph || "\u{f02fc}", text: [ln.summary, ln.body].filter(function(t) { return !!t }).join(" · ") || ln.app,
               tone: island.noteTone(ln), progress: -1, wide: true }
    if (h) {
      if (h.layout === "toast")
        return { glyph: h.icon || "󰂚", text: (h.title || "") + (h.body ? " · " + h.body : ""), tone: h.color || island.accentColor, progress: -1 }
      if (h.layout === "track")
        return { glyph: "󰝚", text: island.mediaTitle + (island.mediaArtist ? " · " + island.mediaArtist : ""), tone: island.mediaTint, progress: -1 }
      if (h.layout === "progress")
        return { glyph: h.icon || "", text: h.valueText || "", tone: h.color || island.fg, progress: Model.clamp01(Number(h.value) || 0) }
      return { glyph: h.icon || "", text: (h.label || "") + (h.valueText ? " " + h.valueText : ""), tone: h.color || island.accentColor, progress: -1 }
    }
    var p = island.primary
    var c = island.clocks
    if (p === "attention" && island.attentionAgent) {
      var ag = island.attentionAgent, more = island.desktop.blocked.length - 1
      return { glyph: "\u{f0026}", text: (ag.agent || "Agent") + " waiting" + (more > 0 ? " +" + more : ""),
               tone: island.orangeColor, progress: -1 }
    }
    if (p === "recording")
      return { glyph: "󰑊", text: "REC " + Model.formatTime(island.recordingElapsed), tone: island.urgentColor, progress: -1 }
    if (p === "timer")
      return { glyph: c.timerPaused ? "󰏤" : "󰔛", text: Model.formatClock(Math.ceil(c.timerLeft / 1000)), tone: island.orangeColor, progress: 1 - c.timerProgress }
    if (p === "stopwatch")
      return { glyph: "󱎫", text: Model.formatClock(c.stopwatchElapsed / 1000, false), tone: island.accentColor, progress: -1 }
    if (p === "activity" && island.activity) {
      var a = island.activity
      return { glyph: a.icon, text: a.title + (a.value ? " · " + a.value : ""), tone: island.toneFor(a.color), progress: a.progress }
    }
    if (p === "media")
      return { glyph: glyphFor("media"), text: island.mediaTitle + (island.mediaArtist ? " · " + island.mediaArtist : ""), tone: island.mediaTint,
               progress: island.mediaLength > 0 ? Model.clamp01(island.mediaPosition / island.mediaLength) : -1 }
    if (p === "calendar" && island.calendar.next)
      return { glyph: "󰃭", text: island.calendar.next.title + " · " + island.calendar.countdown, tone: island.accentColor, progress: -1 }
    if (p === "mic")
      return { glyph: glyphFor("mic"), text: island.cameraActive ? "Camera" : "Mic", tone: island.cameraActive ? island.greenColor : island.orangeColor, progress: -1 }
    if (p === "inbox")
      return { glyph: "󰂚", text: String(island.inbox.length), tone: island.accentColor, progress: -1 }
    // At rest: the island's glances (agents, next meeting, limits...), if any.
    if (!island.idleQuiet && island.idleItem)
      return { glyph: "", text: island.idleItem.text, tone: island.idleItem.color || island.fg, progress: -1, ticker: true }
    return null
  }
  readonly property string secondaryGlyph: live && !island.userExpanded && !island.hud ? glyphFor(island.secondary) : ""

  // Remember the last segment so it can fade out with its content intact.
  property var shownSegment: null
  onSegmentChanged: if (segment) shownSegment = segment

  // A bell module on this monitor's bar (modules/Bell.qml) takes the bell and
  // the room for the side capsules, so the island alone is centred.
  readonly property bool externalBell: Bridge.IslandBus.bellOn(screenName)
  readonly property bool bellShown: live && island.columnNotes && !externalBell
  // the side capsules' room, for the bell module to keep beside the island
  readonly property real extraReserve: dyn && externalBell ? Math.max(0, dynExtra.value) : 0
  implicitWidth: button.implicitWidth + dynSpacer.width + (bellShown ? bell.implicitWidth : 0)
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: implicitWidth
    bar: root.bar
    fontFamily: bar ? bar.fontFamily : Style.font.family
    fontSize: Style.font.body
    text: ""
    hasVisualContent: true
    horizontalMargin: 8.75
    fixedWidth: root.dyn ? Math.max(Style.space(24), dynPill.value) : row.width + Style.spaceReal(8.75) * 2
    active: root.opened
    useActiveColor: false
    tooltipText: ""

    onPressed: function(b) { root.pillPressed(b) }
    onTooltipHoveredChanged: if (root.live && !root.dyn) root.island.barHovered = tooltipHovered

    Row {
      id: row
      // the dynamic look draws the island over the bar instead
      visible: !root.dyn
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        id: clockLabel
        anchors.verticalCenter: parent.verticalCenter
        text: root.clockText
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.features: { "tnum": 1 }
        color: button.foreground
      }

      // The live segment: a tinted gadget with its glyph, a line of text and,
      // when it has one, a progress rule along its lower edge.
      Rectangle {
        id: chip
        readonly property var seg: root.shownSegment
        readonly property bool showing: root.segment !== null
        anchors.verticalCenter: parent.verticalCenter
        height: Math.round(root.barSize - Style.space(8))
        width: Math.max(0, grow.value)
        visible: width > 1
        clip: true
        radius: Math.min(Style.cornerRadius, Style.space(2))
        color: flash ? (seg ? seg.tone : Commons.Color.accent) : Util.alpha(seg ? seg.tone : Commons.Color.accent, 0.16)

        // Flash: two short inversions when the island asks for it.
        property bool flash: false
        property int flashes: 0
        Connections {
          target: root.island
          function onFlashSerialChanged() { if (!Style.reduceMotion) { chip.flashes = 0; flashTimer.restart() } }
        }
        Timer { id: flashTimer; interval: 110; repeat: true
          onTriggered: { chip.flash = !chip.flash; chip.flashes++; if (chip.flashes >= 4) { stop(); chip.flash = false } } }

        // It grows and shrinks on a spring (response 0.32 s, damping 0.92: no
        // bounce you could see), and the clock's button follows it; a new
        // width mid-flight (a title, a second glance) carries on from there.
        SpringValue {
          id: grow
          target: chip.showing ? chipRow.implicitWidth + Style.space(12) : 0
          response: 0.32; damping: 0.92
          cap: 0
          live: button.visible
        }
        Behavior on color { ColorAnimation { duration: Style.duration(160) } }

        // metal family (Chrom & Platin): a chrome rim around the segment, a
        // glint along it when another kind of segment takes its place – keyed
        // by its glyph, since timers, stopwatches and media rebuild the
        // segment many times a second
        MetalShape {
          id: chipMetal
          readonly property var m: root.island && root.island.material && root.island.material.metal ? root.island.material.metal : null
          visible: !!m && chip.showing
          spec: m
          anchors.fill: parent
          pad: 0.5
          tube: m ? Math.max(1.2, Number(m.rim || 1.4) - 0.2) : 1.4
          radius: chip.radius
        }
        readonly property string segKey: seg ? String(seg.glyph || "") + (seg.ticker ? "|t" : "") + (seg.wide ? "|w" : "") : ""
        onSegKeyChanged: if (segKey !== "") chipMetal.play()

        Row {
          id: chipRow
          x: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(5)
          opacity: chip.showing ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }

          Text {
            visible: text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.seg ? chip.seg.glyph : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.family: button.fontFamily
            font.pixelSize: button.fontSize
            color: chip.seg ? chip.seg.tone : button.foreground
          }

          // Glances flip like the resting island did; everything else is a
          // plain line, elided so the bar never gets pushed around by a
          // long title.
          Flip {
            visible: !!(chip.seg && chip.seg.ticker)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Style.space(240))
            height: chip.height
            text: chip.seg && chip.seg.ticker ? chip.seg.text : ""
            color: chip.seg ? chip.seg.tone : button.foreground
            fontFamily: button.fontFamily
            pixelSize: button.fontSize
            bold: false
          }

          Text {
            visible: !(chip.seg && chip.seg.ticker) && text !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Style.space(chip.seg && chip.seg.wide ? 380 : 240))
            text: chip.seg ? chip.seg.text : ""
            elide: Text.ElideRight
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.family: button.fontFamily
            font.pixelSize: button.fontSize
            font.features: { "tnum": 1 }
            color: button.foreground
          }

          Text {
            visible: root.secondaryGlyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.secondaryGlyph
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.family: button.fontFamily
            font.pixelSize: button.fontSize
            color: Util.alpha(button.foreground, 0.6)
          }
        }

        Rectangle {
          readonly property real p: chip.seg && chip.seg.progress >= 0 ? chip.seg.progress : -1
          visible: p >= 0 && chip.showing
          anchors.bottom: parent.bottom
          height: Math.max(1, Style.space(2))
          width: Math.round(parent.width * Math.max(0, p))
          color: chip.seg ? chip.seg.tone : Commons.Color.accent
          Behavior on width { NumberAnimation { duration: Style.duration(240) } }
        }
      }
    }
  }

  // A card hangs from the island: a 2 px line in its tone along the bottom
  // of the clock; it runs in from the left when a card comes (not with
  // reduced motion). Float notes: only a short mark at the island's centre,
  // above the card, fading in with it.
  Item {
    id: toneLine
    readonly property var entry: root.live && root.island.columnNotes ? root.island.noteCurrent : null
    readonly property int key: entry ? entry.key : -1
    readonly property bool mark: !!root.island && !root.island.material && root.island.noteStyle === "float"
    property real run: 1
    width: mark ? Math.round(root.island.s(16)) : button.width - Style.space(8)
    x: mark ? Math.round(button.x + (button.width - width) / 2) : button.x + Style.space(4)
    height: Math.max(1, Style.space(2))
    anchors.bottom: button.bottom
    visible: entry !== null && !root.dyn
    onKeyChanged: if (key >= 0) { run = Style.reduceMotion ? 1 : 0; if (!Style.reduceMotion) runAnim.restart() }
    NumberAnimation { id: runAnim; target: toneLine; property: "run"; to: 1; duration: toneLine.mark ? 200 : 380; easing.type: toneLine.mark ? Easing.OutCubic : Easing.Linear }
    Rectangle {
      width: toneLine.mark ? parent.width : parent.width * toneLine.run
      height: parent.height
      radius: toneLine.mark ? height / 2 : 0
      color: root.island ? root.island.noteTone(toneLine.entry) : Commons.Color.accent
      opacity: toneLine.mark ? 0.95 * toneLine.run : 0.95
    }
  }

  // Dynamic look: room for the minimal capsules beside the island's.
  Item {
    id: dynSpacer
    anchors.left: button.right
    width: root.dyn && !root.externalBell ? Math.max(0, dynExtra.value) : 0
    height: 1
  }

  // The bell segment: unread count, do-not-disturb state.
  WidgetButton {
    id: bell
    visible: root.bellShown
    anchors.left: dynSpacer.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: implicitWidth
    bar: root.bar
    text: ""
    hasVisualContent: true
    labelVisible: false
    useActiveColor: false
    active: root.opened && root.island.inboxOpen
    horizontalMargin: 6
    fixedWidth: bellRow.width + Style.spaceReal(6) * 2
    tooltipText: ""
    onPressed: function(b) {
      if (!root.live) return
      if (b === Qt.RightButton) root.island.setDoNotDisturb(!root.island.doNotDisturb)
      else root.toggleInbox()
    }

    readonly property bool dnd: root.live && root.island.doNotDisturb
    readonly property int unread: root.live ? root.island.unreadCount : 0

    // (no groove before the bell: groups are set off by space, not rules)
    Row {
      id: bellRow
      anchors.centerIn: parent
      spacing: Style.space(4)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: bell.dnd ? "\u{f00a0}" : "\u{f009a}"
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        color: bell.dnd ? (root.island ? root.island.accentColor : Commons.Color.accent)
          : bell.unread > 0 ? button.foreground : Util.alpha(button.foreground, 0.55)
      }
      Text {
        visible: bell.dnd
        anchors.verticalCenter: parent.verticalCenter
        text: "DND"
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: button.fontFamily
        font.pixelSize: Math.round(button.fontSize * 0.8)
        font.bold: true
        color: root.island ? root.island.accentColor : Commons.Color.accent
      }
      Text {
        visible: bell.unread > 0
        anchors.verticalCenter: parent.verticalCenter
        text: String(bell.unread)
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        // many unread are not a warning: the count in the bar's ink
        color: bell.dnd ? Util.alpha(button.foreground, 0.7) : button.foreground
      }
    }
  }

  // ------------------------------------------------------------------
  // The opened island: a native bar popup around the island's own views.
  // ------------------------------------------------------------------
  readonly property string expandedView: live && island.userExpanded ? island.view : ""
  property string shownView: "idle-expanded"
  onExpandedViewChanged: if (expandedView !== "") shownView = expandedView
  readonly property var viewSize: island ? island.slotSize(shownView) : ({ w: 0, h: 0 })

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    padding: 0
    // Card size includes the frame (padding is 0); the frame is equal on all sides.
    contentWidth: (root.island ? root.island.s(root.viewSize.w) : Style.space(420)) + popup.verticalContentInset
    contentHeight: popup.fittedContentHeight(root.island ? root.island.s(root.viewSize.h) : Style.space(170))

    focusTarget: keys

    // Theme material (the bar's edge "theme"): the popup takes the theme's
    // card, rolls out of the bar or, on the Lavur themes, blooms out of it.
    MaterialCard { panel: popup; material: root.island ? root.island.material : null; calm: !!root.island && root.island.calmMotion; apple: !!root.island && root.island.appleMotion }

    // Esc closes (or first leaves the calendar's link field). Keys the
    // views do not take bubble up to here.
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: function(event) {
        if (root.live && root.island.calendarAdding) root.island.calendarAdding = false
        else root.close()
        event.accepted = true
      }

    Loader {
      anchors.fill: parent
      active: root.live && (popup.open || popup.visible)
      sourceComponent: {
        switch (root.shownView) {
        case "media-expanded": return mediaView
        case "recording-expanded":
        case "recording-media-expanded": return recordingView
        case "inbox-expanded": return root.island && root.island.columnNotes ? noteInboxView : inboxView
        case "clock-expanded": return clockView
        case "activity-expanded": return activityView
        case "attention-expanded": return requesterView
        case "outputs-expanded": return outputsView
        case "calendar-expanded": return calendarView
        default: return idleView
        }
      }
    }
    }
  }

  Component { id: idleView; IdleExpanded { island: root.island } }
  Component { id: mediaView; MediaExpanded { island: root.island } }
  Component { id: recordingView; RecordingExpanded { island: root.island } }
  Component { id: inboxView; InboxView { island: root.island } }
  Component { id: noteInboxView; NoteInbox { island: root.island } }
  Component { id: clockView; ClockExpanded { island: root.island } }
  Component { id: activityView; ActivityExpanded { island: root.island } }
  Component { id: requesterView; RequesterView { island: root.island } }
  Component { id: outputsView; OutputsView { island: root.island } }
  Component { id: calendarView; CalendarView { island: root.island } }
}
