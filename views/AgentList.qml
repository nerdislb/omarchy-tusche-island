import QtQuick
import qs.Commons

// The existing agent model, with explicit focus only after a user click.
ListView {
  id: list
  property var island: null
  model: island ? island.desktop.panelAgents : []
  clip: true
  spacing: island.s(4)
  boundsBehavior: Flickable.StopAtBounds
  delegate: Rectangle {
    id: row
    required property var modelData
    width: list.width
    height: list.island.s(48)
    radius: Math.min(Style.cornerRadius, Style.space(2))
    color: Util.alpha(list.island.fg, mouse.containsMouse ? 0.10 : 0.04)
    readonly property color tone: modelData.status === "blocked" ? list.island.orangeColor
      : modelData.status === "working" ? list.island.accentColor : list.island.fgDim
    Column {
      x: list.island.s(10)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - list.island.s(20)
      spacing: list.island.s(2)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.modelData.title || row.modelData.agent
        elide: Text.ElideRight
        font.family: list.island.textFamily
        font.pixelSize: list.island.f(12)
        color: list.island.fg
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: (row.modelData.source === "corgi" ? "Corgi · " : "") + row.modelData.agent + " · "
          + (row.modelData.status === "blocked" ? "Needs input" : row.modelData.status === "working" ? "Working"
            : row.modelData.status === "idle" ? "Idle" : "Status unavailable")
        elide: Text.ElideRight
        font.family: list.island.fontFamily
        font.pixelSize: list.island.f(10)
        color: row.tone
      }
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        list.island.desktop.focusAgent(row.modelData)
        list.island.collapse()
      }
    }
  }
}
