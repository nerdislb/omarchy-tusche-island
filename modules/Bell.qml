import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../bridge" as Bridge

// The island's notification bell as a bar module of its own, so the island
// alone sits in the middle of the bar (bar alignment, 3 Nov 2026). Custom QML
// module, first in the section after the island:
//   { "id": "tusche.bell", "source": ".../modules/Bell.qml" }   (centerEnd)
// While one is mounted the island's widget leaves its own bell out. It shows
// what the bell did: unread count, do not disturb; the inbox still opens from
// the island.
//   left click    the inbox      right click   do not disturb
Item {
  id: root

  property var bar: null
  property string moduleName: "tusche.bell"
  property var settings: ({})

  readonly property var island: Bridge.IslandBus.island
  readonly property bool live: island !== null && island.barMode && island.columnNotes
  readonly property int barSize: bar && bar.barSize ? bar.barSize : Style.bar.sizeHorizontal
  readonly property string screenName: button.QsWindow.window && button.QsWindow.window.screen
    ? button.QsWindow.window.screen.name : ""

  Component.onCompleted: Bridge.IslandBus.registerBell(root)
  Component.onDestruction: Bridge.IslandBus.unregisterBell(root)

  visible: live
  implicitHeight: barSize
  implicitWidth: live ? button.width : 0

  readonly property bool dnd: live && island.doNotDisturb
  readonly property int unread: live ? island.unreadCount : 0

  WidgetButton {
    id: button
    bar: root.bar
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: implicitWidth
    text: ""
    hasVisualContent: true
    labelVisible: false
    useActiveColor: false
    active: root.live && root.island.userExpanded && root.island.inboxOpen
    horizontalMargin: 6
    fixedWidth: row.width + Style.spaceReal(6) * 2
    tooltipText: ""
    onPressed: function(b) {
      if (!root.live) return
      if (b === Qt.RightButton) { root.island.setDoNotDisturb(!root.island.doNotDisturb); return }
      var w = Bridge.IslandBus.widgetOn(root.screenName)
      if (w) w.toggleInbox()
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.space(4)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.dnd ? "\u{f00a0}" : "\u{f009a}"
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        // the state (do not disturb) in colour; a quiet bell otherwise
        color: root.dnd ? (root.island ? root.island.accentColor : Commons.Color.accent)
          : root.unread > 0 ? button.foreground : Util.alpha(button.foreground, 0.55)
      }
      Text {
        visible: root.dnd
        anchors.verticalCenter: parent.verticalCenter
        text: "DND"
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: button.fontFamily
        font.pixelSize: Math.round(button.fontSize * 0.8)
        font.bold: true
        color: root.island ? root.island.accentColor : Commons.Color.accent
      }
      // many unread are not a warning: the count in the bar's ink
      Text {
        visible: root.unread > 0
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.unread)
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.features: { "tnum": 1 }
        color: root.dnd ? Util.alpha(button.foreground, 0.7) : button.foreground
      }
    }
  }
}
