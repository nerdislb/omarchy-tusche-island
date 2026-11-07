import QtQuick
import qs.Commons
import "../IslandModel.js" as Model

// The expanded dynamic island (views/DynamicStage.qml): for the events that
// matter (an agent finished, the battery runs low, a timer ran out) the
// island itself grows instead of a banner (HIG Live Activities; owner's
// choice 29.10.2026). Laid out as the approved board: a round tile in the
// status colour with its glyph in black where the compact island has its
// status, the title and a line under it, the clock top right where it was,
// the actions as capsules. 84 px tall without actions, 104 with.
//
// A click on it runs the first action (or dismisses it when it has none), a
// right click dismisses; the capsules run their own action.
Item {
  id: view

  property var island: null
  property var alert: null      // { glyph, tone, title, subtitle, actions: [{ id, label, primary }] }
  property string clock: ""
  property color ink: "#f2f2f2"
  readonly property string flavor: island && island.flavor !== undefined ? island.flavor : ""
  readonly property bool completion: !!alert && alert.title === "Agent finished"
  readonly property real sealSpace: completion && flavor === "tusche" ? s(64) : 0
  readonly property color dim: Util.alpha(ink, 0.62)
  readonly property color tone: alert && alert.tone ? alert.tone : ink
  readonly property var actions: alert && Array.isArray(alert.actions) ? alert.actions : []

  signal action(string id)
  signal dismissed()

  function s(px) { return island ? island.s(px) : px }
  function f(px) { return island ? island.f(px) : px }
  function gf(px) { return island ? island.gf(px) : px }
  readonly property string family: island ? island.fontFamily : ""
  readonly property string words: island ? island.textFamily : ""

  implicitHeight: actions.length > 0 ? s(104) : s(84)

  property bool hovering: hover.hovered
  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton || view.actions.length === 0) view.dismissed()
      else view.action(view.actions[0].id)
    }
  }

  Rectangle {
    id: tile
    x: view.s(18)
    y: view.s(18)
    width: view.s(44); height: width; radius: width / 2
    color: view.tone
    Text {
      anchors.centerIn: parent
      text: view.alert ? view.alert.glyph || "" : ""
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: view.family
      font.pixelSize: view.gf(22)
      color: "#000000"
    }
  }

  Text {
    id: clockText
    anchors.right: parent.right
    anchors.rightMargin: view.s(20)
    y: view.s(30) - implicitHeight / 2
    text: view.clock
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    font.family: view.family
    font.pixelSize: view.f(13)
    font.bold: true
    font.features: { "tnum": 1 }
    color: view.ink
  }

  Text {
    x: view.s(78)
    y: view.s(30) - implicitHeight / 2
    width: clockText.x - x - view.s(16)
    text: view.alert ? (view.completion ? Model.completionTitle(view.alert.title, view.flavor) : view.alert.title || "") : ""
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    font.family: view.words
    font.pixelSize: view.f(15)
    font.bold: true
    color: view.ink
  }

  Text {
    x: view.s(78)
    y: view.s(52) - implicitHeight / 2
    width: view.width - x - view.s(20) - view.sealSpace
    text: view.alert ? view.alert.subtitle || "" : ""
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    font.family: view.words
    font.pixelSize: view.f(12)
    color: view.dim
  }

  Row {
    x: view.s(78)
    y: view.s(70)
    spacing: view.s(10)
    visible: view.actions.length > 0
    Repeater {
      model: view.actions
      Rectangle {
        id: btn
        required property var modelData
        readonly property bool primary: !!modelData.primary
        width: Math.max(view.s(100), label.implicitWidth + view.s(28))
        height: view.s(24)
        radius: height / 2
        color: primary ? Util.alpha(view.tone, area.containsMouse ? 0.32 : 0.22)
          : Util.alpha(view.ink, area.containsMouse ? 0.16 : 0.10)
        Text {
          id: label
          anchors.centerIn: parent
          text: btn.modelData.label
          textFormat: Text.PlainText
          renderType: Text.NativeRendering
          font.family: view.family
          font.pixelSize: view.f(12)
          font.bold: btn.primary
          color: btn.primary ? view.tone : view.ink
        }
        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: view.action(btn.modelData.id)
        }
      }
    }
  }
}
