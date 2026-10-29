import QtQuick
import qs.Commons

// An inset track with a raised knob, accent when on, that moves like an iOS
// switch: the knob is thrown on a spring (response 0.28 s, damping 0.8), it
// widens by a fifth while pressed (toward where it would go), and the track
// and knob take their colour from how far the knob has travelled rather than
// from a timer of their own. Unseen and with Reduced Motion it jumps.
// The caller owns the value: bind `checked`, flip it on `toggled()`.
Item {
  id: sw

  property var island: null
  property bool checked: false
  signal toggled()

  readonly property color bevelDark: Qt.darker(island.surface, 1.7)
  readonly property color offTrack: Qt.darker(island.surface, 1.25)
  readonly property color onTrack: { var c = mix(island.surface, island.accentColor, 0.45); return Qt.rgba(c.r, c.g, c.b, 1) }
  readonly property real inset: 2
  readonly property real knobRest: island.s(14)
  // How far the knob has gone, 0 off to 1 on (the knob itself may settle a
  // touch past either end; its colours do not)
  readonly property real travel: Math.max(0, Math.min(1, knobSpring.value))
  readonly property alias knob: knob
  readonly property alias track: track
  // held down (the knob widens)
  property bool pressed: mouse.pressed

  function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t) }

  implicitWidth: island.s(38)
  implicitHeight: island.s(18)

  SpringValue {
    id: knobSpring
    target: sw.checked ? 1 : 0
    response: 0.28; damping: 0.8
    precision: 0.004
    live: sw.visible
  }
  // Pressed in quickly, let go with a little give (the press feedback springs).
  SpringValue {
    id: press
    target: sw.pressed ? 1 : 0
    response: sw.pressed ? 0.10 : 0.30
    damping: sw.pressed ? 1 : 0.7
    precision: 0.004
    live: sw.visible
  }

  Rectangle {
    id: track
    anchors.fill: parent
    color: sw.mix(sw.offTrack, sw.onTrack, sw.travel)
    Rectangle { width: parent.width; height: 1; color: sw.bevelDark }
    Rectangle { width: 1; height: parent.height; color: sw.bevelDark }
    Rectangle {
      id: knob
      readonly property real free: track.width - 2 * sw.inset - width
      width: sw.knobRest * (1 + 0.2 * Math.max(0, press.value))
      height: parent.height - 2 * sw.inset
      x: sw.inset + free * knobSpring.value
      y: sw.inset
      color: sw.mix(island.fgDim, island.accentColor, sw.travel)
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -island.s(6)
    cursorShape: Qt.PointingHandCursor
    onClicked: sw.toggled()
  }
}
