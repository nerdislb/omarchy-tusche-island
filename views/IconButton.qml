import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// Omarchy's control (hover, focus, accent) in the island's shape: a round,
// borderless button on a quiet fill, like the capsules of the expanded
// island and the requester (hybrid bar alignment, 3 Nov 2026).
Item {
  id: button
  property string glyph: ""
  property int glyphSize: 18
  property color color: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property bool available: true
  signal clicked()
  implicitWidth: Math.round(glyphSize * 2)
  implicitHeight: implicitWidth
  Ui.PanelActionButton {
    id: control
    anchors.fill: parent
    iconText: button.glyph
    fontSize: button.glyphSize
    fontFamily: button.fontFamily
    foreground: button.color
    hoverColor: Commons.Color.accent
    enabled: button.available
    opacity: button.available ? 1 : 0.35
    bordered: false
    radius: height / 2
    color: control._hot ? Style.hoverFillFor(control.hoverColor, control.hoverColor) : Util.alpha(button.color, 0.08)
    onClicked: button.clicked()
  }
}
