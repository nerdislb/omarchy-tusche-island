import QtQuick
import Quickshell
import qs.Commons
import "../IslandModel.js" as Model

// What the island opens into when nothing is live. The bar above already
// shows the time, so this is about what comes next: the next meeting from
// the desktop's calendars (OmaMail), what the agents, the AI limits, the
// phone and the laptop are doing, and one-tap timers and a stopwatch.
Item {
  id: view

  property var island: null
  readonly property int pad: island.s(22)
  readonly property var nextEvent: island.calendar.next
  readonly property var desk: island.desktop

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  function timeText(t) {
    return Qt.formatDateTime(new Date(t), island.clockFormat.indexOf("AP") !== -1 ? "h:mm AP" : "HH:mm")
  }

  function sameDay(a, b) {
    var x = new Date(a), y = new Date(b)
    return x.getFullYear() === y.getFullYear() && x.getMonth() === y.getMonth() && x.getDate() === y.getDate()
  }

  // Status lines for the right column; only what is actually there.
  readonly property var statusLines: {
    var out = []
    var w = desk.working
    if (w.length > 0)
      out.push({ text: "󰚩 " + (w.length === 1 ? "1 agent working" : w.length + " agents working"), color: island.accentColor })
    var top = desk.topLimit
    if (top && top.percent >= 0.75)
      out.push({ text: "󰚩 " + Model.providerName(top.provider) + " " + Model.shortLimit(top.label) + " " + Math.round(top.percent * 100) + "%",
                 color: top.percent >= 0.999 ? island.urgentColor : (top.percent >= 0.9 ? island.orangeColor : island.fgDim) })
    if (desk.phone)
      out.push({ text: (desk.phone.charging ? "󰂄 " : "󰄜 ") + desk.phone.name + " " + Math.round(desk.phone.charge) + "%",
                 color: desk.phoneLow ? island.urgentColor : island.fgDim })
    if (island.hasBattery)
      out.push({ text: Model.batteryIcon(island.batteryLevel, island.charging) + " " + Model.percentText(island.batteryLevel),
                 color: island.charging ? island.greenColor : (island.batteryLevel <= 0.2 ? island.urgentColor : island.fgDim) })
    return out
  }

  // The agenda: opens the calendar.
  Column {
    id: agenda
    x: view.pad
    y: island.s(16)
    width: parent.width - view.pad * 2 - status.width - island.s(16)
    spacing: island.s(3)

    Text {
      width: parent.width
      elide: Text.ElideRight
      text: view.nextEvent ? "NEXT" + (view.nextEvent.source ? " · " + view.nextEvent.source.toUpperCase() : "") : "TODAY"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(10)
      font.weight: Font.Bold
      font.letterSpacing: island.s(1)
      color: Qt.darker(island.fg, 1.4)
    }

    Text {
      id: headline
      width: parent.width
      text: view.nextEvent ? (view.nextEvent.title || "Busy") : Qt.formatDateTime(clock.date, "dddd, d MMMM")
      elide: Text.ElideRight
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.textFamily
      font.pixelSize: island.f(15)
      font.weight: Font.DemiBold
      font.underline: agendaMouse.containsMouse
      color: island.fg
    }

    Text {
      width: parent.width
      text: {
        var e = view.nextEvent
        if (!e) {
          var today = island.calendar.todayAllDay
          return today.length > 0 ? "✦ " + today.join(" · ")
            : (island.calendar.hasAny ? "Nothing scheduled" : "No calendar connected")
        }
        var when = (view.sameDay(e.start, clock.date) ? "" : Qt.formatDateTime(new Date(e.start), "ddd") + " ")
          + view.timeText(e.start)
        return when + " · " + Model.untilText(e.start, clock.date.getTime())
      }
      elide: Text.ElideRight
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(11)
      font.features: { "tnum": 1 }
      color: view.nextEvent ? island.accentColor : island.fgDim
    }
  }

  MouseArea {
    id: agendaMouse
    x: agenda.x; y: agenda.y
    width: agenda.width; height: agenda.height
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: island.openCalendar()
  }

  Column {
    id: status
    anchors.right: parent.right
    anchors.rightMargin: view.pad
    y: island.s(18)
    spacing: island.s(3)

    Repeater {
      model: view.statusLines

      Text {
        required property var modelData
        anchors.right: parent.right
        text: modelData.text
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: island.fontFamily
        font.pixelSize: island.f(11)
        font.features: { "tnum": 1 }
        color: modelData.color
      }
    }
  }

  AgentList {
    island: view.island
    x: view.pad
    y: island.s(110)
    width: parent.width - view.pad * 2
    height: Math.max(0, chips.y - y - island.s(26))
    visible: desk.panelAgents.length > 0
  }

  // A hairline between the glance and the controls, as in Omarchy panels.
  Rectangle {
    x: view.pad
    width: parent.width - view.pad * 2
    height: 1
    anchors.bottom: chips.top
    anchors.bottomMargin: island.s(12)
    color: Util.alpha(island.fg, 0.1)
  }

  // One-tap timers and the stopwatch.
  Row {
    id: chips
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: island.s(16)
    spacing: island.s(8)

    Repeater {
      model: [
        { label: "5 min", glyph: "󰔛", seconds: 300 },
        { label: "15 min", glyph: "󰔛", seconds: 900 },
        { label: "25 min", glyph: "󰔛", seconds: 1500 },
        { label: "Stopwatch", glyph: "󱎫", seconds: 0 },
        { label: "", glyph: "󰃭", seconds: -1 }
      ]

      Rectangle {
        id: chip
        required property var modelData
        height: island.s(30)
        width: chipLabel.implicitWidth + island.s(22)
        radius: Math.min(Style.cornerRadius, Style.space(2))
        color: Util.alpha(chip.modelData.seconds > 0 ? island.orangeColor : island.accentColor,
                          chipMouse.pressed ? 0.3 : (chipMouse.containsMouse ? 0.22 : 0.14))

        Behavior on color { ColorAnimation { duration: Style.duration(120) } }

        Text {
          id: chipLabel
          anchors.centerIn: parent
          text: chip.modelData.label ? chip.modelData.glyph + " " + chip.modelData.label : chip.modelData.glyph
          textFormat: Text.PlainText
          renderType: Text.NativeRendering
          font.family: island.textFamily
          font.pixelSize: island.f(12)
          font.weight: Font.DemiBold
          color: chip.modelData.seconds > 0 ? island.orangeColor : island.accentColor
        }

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (chip.modelData.seconds < 0) { island.openCalendar(); return }
            if (chip.modelData.seconds > 0) island.clocks.startTimer(chip.modelData.seconds, "")
            else island.clocks.toggleStopwatch()
            island.collapse()
          }
        }
      }
    }
  }
}
