import QtQuick
import qs.Commons

// Volume / brightness: glyph, a slim level bar, and the percentage.
Item {
  id: view

  property var island: null
  readonly property var hud: island.hud || ({})
  readonly property real value: Math.max(0, Math.min(1, Number(hud.value) || 0))

  Text {
    id: glyph
    anchors.left: parent.left
    anchors.leftMargin: island.s(14)
    anchors.verticalCenter: parent.verticalCenter
    width: island.s(20)
    horizontalAlignment: Text.AlignHCenter
    text: view.hud.icon || ""
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    font.family: island.fontFamily
    font.pixelSize: island.gf(16)
    color: island.fg
  }

  Text {
    id: readout
    anchors.right: parent.right
    anchors.rightMargin: island.s(15)
    anchors.verticalCenter: parent.verticalCenter
    width: island.s(42)
    horizontalAlignment: Text.AlignRight
    text: view.hud.valueText || ""
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    font.family: island.fontFamily
    font.pixelSize: island.f(12)
    font.bold: true
    font.features: { "tnum": 1 }
    color: island.fg
  }

  Rectangle {
    anchors.left: glyph.right
    anchors.leftMargin: island.s(12)
    anchors.right: readout.left
    anchors.rightMargin: island.s(10)
    anchors.verticalCenter: parent.verticalCenter
    height: island.s(5)
    radius: Math.min(Style.cornerRadius, Style.space(2))
    color: Util.alpha(island.fg, 0.16)

    // The level glides to each new value (a key press, a slider elsewhere)
    // on a short spring without overshoot (response 0.20 s), quick enough
    // to keep up with key repeat.
    Rectangle {
      height: parent.height
      radius: Math.min(Style.cornerRadius, Style.space(2))
      width: Math.max(view.value > 0 ? height : 0, parent.width * Math.max(0, level.value))
      color: view.hud.color || island.fg

      SpringValue { id: level; target: view.value; response: 0.20; damping: 1; precision: 0.001; live: view.visible }
    }
  }
}
