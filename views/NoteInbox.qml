import QtQuick
import qs.Commons
import "../IslandModel.js" as Model

// The inbox when the island serves notifications in the bar (bell segment):
// a bevelled head, Mark read / Clear all, the waiting notifications with
// their app and unread mark, and an explicit do-not-disturb switch.
// Click a row to open it, right click (or ×) to clear it.
Item {
  id: view

  property var island: null
  readonly property var items: island ? island.inbox : []
  readonly property real headH: island.s(28)
  readonly property real toolH: island.s(34)
  readonly property real rowH: island.s(Model.noteInboxRow)
  readonly property real footH: island.s(44)
  readonly property color bevelDark: Qt.darker(island.surface, 1.7)
  readonly property color bevelLight: Util.alpha(island.fg, 0.18)

  function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }

  // ------------------------------------------------------------ head
  //
  // The head speaks the theme's material family instead of being a fixed slab:
  // glass (Smoke, Frost) keeps the panel's translucent surface and separates
  // with the theme's quiet edge hairline, Lavur drops fill and line (its cards
  // bring their own halo), Tusche/Papier keep the quiet tonal step with the
  // card frame colour as the crisp separator, Chrom/Platin get a chrome
  // hairline. Themes without bar-material.json keep the old bevelled slab.
  readonly property var material: island ? island.material : null
  readonly property bool glassHead: !!(material && material.glass && material.glass.enabled !== false)
  readonly property bool bloomHead: !!(material && material.card && material.card.bloom === true)
  readonly property var headRule: {
    if (!material || bloomHead) return null
    var edge = material.edge || {}
    if (glassHead && edge.line) return edge.line
    var frame = material.card ? material.card.frame : null
    if (frame) return frame
    var metal = material.metal
    if (metal && metal.tint) return { color: metal.tint, alpha: 0.5, width: 1 }
    return null
  }
  readonly property int headRuleWidth: headRule && headRule.width ? Math.max(1, Math.round(headRule.width)) : 1
  readonly property color headRuleColor: headRule
    ? Util.alpha(headRule.color, headRule.alpha !== undefined ? headRule.alpha : 1)
    : bevelDark

  Rectangle {
    id: head
    width: parent.width
    height: view.headH
    color: (view.glassHead || view.bloomHead) ? "transparent" : view.mix(island.surface, island.fg, 0.06)
    // A solid head keeps its faint top bevel; glass and Lavur have no slab.
    Rectangle { visible: !view.glassHead && !view.bloomHead; width: parent.width; height: 1; color: view.bevelLight }
    Rectangle {
      visible: !view.bloomHead
      y: parent.height - view.headRuleWidth
      width: parent.width
      height: view.headRuleWidth
      color: view.headRuleColor
      opacity: view.glassHead ? 0.9 : 1
    }
    Text {
      x: island.s(12)
      anchors.verticalCenter: parent.verticalCenter
      text: "INBOX"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(12)
      font.bold: true
      color: island.accentColor
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: island.s(12)
      anchors.verticalCenter: parent.verticalCenter
      text: island.unreadCount + " unread"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(11)
      color: island.fgDim
    }
  }

  // ------------------------------------------------------------ toolbar
  Item {
    id: tools
    y: head.height
    width: parent.width
    height: view.toolH
    Text {
      x: island.s(14)
      anchors.verticalCenter: parent.verticalCenter
      text: view.items.length === 0 ? "No notifications" : view.items.length + (view.items.length === 1 ? " notification" : " notifications")
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(11)
      color: island.fgDim
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: island.s(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: island.s(8)
      BevelButton { label: "Mark read"; enabled: island.unreadCount > 0; onClicked: island.markAllRead() }
      BevelButton { label: "Clear all"; enabled: view.items.length > 0; onClicked: island.notificationClearInbox() }
    }
    Rectangle {
      visible: !view.bloomHead
      y: parent.height - 1; width: parent.width; height: 1
      // Soft separation for the materials that have no slab edge of their own.
      color: (view.glassHead || view.bloomHead) ? Util.alpha(island.fg, 0.08) : view.bevelDark
    }
  }

  // ------------------------------------------------------------ rows
  ListView {
    id: list
    y: tools.y + tools.height
    width: parent.width
    height: parent.height - y - view.footH
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: view.items

    delegate: Item {
      id: row
      required property var modelData
      required property int index
      width: ListView.view.width
      height: view.rowH

      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: rowMouse.containsMouse ? Util.alpha(island.accentColor, 0.16) : "transparent"
        Rectangle { visible: rowMouse.containsMouse; width: 2; height: parent.height; color: island.accentColor }
      }
      // unread mark
      Rectangle {
        visible: row.modelData.unread !== false
        x: island.s(9)
        anchors.verticalCenter: parent.verticalCenter
        width: island.s(6); height: width
        color: island.accentColor
      }
      Rectangle {
        id: tile
        x: island.s(22)
        anchors.verticalCenter: parent.verticalCenter
        width: island.s(30); height: width
        color: view.mix(island.surface, island.noteTone(row.modelData), 0.22)
        readonly property string icon: island.notificationIcon(row.modelData)
        Image {
          anchors.fill: parent
          anchors.margins: island.s(4)
          visible: tile.icon !== "" && status === Image.Ready
          source: tile.icon
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          fillMode: Image.PreserveAspectFit
          asynchronous: true
        }
        Text {
          anchors.centerIn: parent
          visible: tile.icon === ""
          text: row.modelData.glyph || (row.modelData.critical ? "\u{f0ecc}" : "\u{f009a}")
          textFormat: Text.PlainText
          renderType: Text.NativeRendering
          font.family: island.fontFamily
          font.pixelSize: island.f(15)
          color: island.noteTone(row.modelData)
        }
      }
      Text {
        id: tag
        anchors.right: close.left
        anchors.rightMargin: island.s(6)
        y: island.s(9)
        text: row.modelData.critical ? "\u{f0ecc} request" : String(row.modelData.app || "")
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: island.fontFamily
        font.pixelSize: island.f(10)
        color: row.modelData.critical ? island.urgentColor : island.fgDim
      }
      Column {
        x: tile.x + tile.width + island.s(12)
        width: tag.x - x - island.s(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: island.s(2)
        Text {
          width: parent.width
          text: row.modelData.summary || row.modelData.app || ""
          textFormat: Text.PlainText
          renderType: Text.NativeRendering
          elide: Text.ElideRight
          font.family: island.textFamily
          font.pixelSize: island.f(13)
          font.bold: true
          color: island.fg
        }
        Text {
          width: parent.width + tag.width
          visible: text !== ""
          text: row.modelData.body || ""
          textFormat: Text.PlainText
          renderType: Text.NativeRendering
          elide: Text.ElideRight
          font.family: island.textFamily
          font.pixelSize: island.f(12)
          color: row.modelData.unread !== false ? island.fg : island.fgDim
        }
      }
      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) island.notificationDismiss(row.modelData.key)
          // A deferred requester whose sender is still there goes back to
          // its buttons; anything else opens.
          else if (row.modelData.critical && row.modelData.ref) island.requeueNote(row.modelData.key)
          else island.notificationOpen(row.modelData.key)
        }
      }
      Text {
        id: close
        anchors.right: parent.right
        anchors.rightMargin: island.s(10)
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{f0156}"
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: island.fontFamily
        font.pixelSize: island.f(13)
        color: closeMouse.containsMouse ? island.fg : island.fgDim
        MouseArea {
          id: closeMouse
          anchors.fill: parent
          anchors.margins: -island.s(6)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: island.notificationDismiss(row.modelData.key)
        }
      }
      Rectangle { visible: row.index < view.items.length - 1; x: island.s(64); y: parent.height - 1; width: parent.width - x - island.s(10); height: 1; color: Util.alpha(island.fg, 0.08) }
    }
  }

  // ------------------------------------------------------------ footer: DND
  Item {
    y: parent.height - view.footH
    width: parent.width
    height: view.footH
    Rectangle { width: parent.width; height: 1; color: view.bevelDark }
    Rectangle { y: 1; width: parent.width; height: 1; color: view.bevelLight }
    Text {
      id: dndLabel
      x: island.s(14)
      anchors.verticalCenter: parent.verticalCenter
      text: "Do not disturb"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(12)
      color: island.fg
    }
    // An inset track with a raised knob, accent when on.
    Rectangle {
      id: track
      x: dndLabel.x + dndLabel.implicitWidth + island.s(14)
      anchors.verticalCenter: parent.verticalCenter
      width: island.s(38); height: island.s(18)
      color: island.doNotDisturb ? view.mix(island.surface, island.accentColor, 0.45) : Qt.darker(island.surface, 1.25)
      Rectangle { width: parent.width; height: 1; color: view.bevelDark }
      Rectangle { width: 1; height: parent.height; color: view.bevelDark }
      Rectangle {
        x: island.doNotDisturb ? parent.width - width - 2 : 2
        y: 2
        width: island.s(14); height: parent.height - 4
        color: island.doNotDisturb ? island.accentColor : island.fgDim
        Behavior on x { NumberAnimation { duration: Style.duration(120) } }
      }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -island.s(6)
        cursorShape: Qt.PointingHandCursor
        onClicked: island.setDoNotDisturb(!island.doNotDisturb)
      }
    }
    Text {
      x: track.x + track.width + island.s(8)
      anchors.verticalCenter: parent.verticalCenter
      text: island.doNotDisturb ? "On" : "Off"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(11)
      color: island.doNotDisturb ? island.accentColor : island.fgDim
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: island.s(14)
      anchors.verticalCenter: parent.verticalCenter
      text: "Omarchy alerts still come through"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(10)
      color: island.fgDim
    }
  }

  component BevelButton: Rectangle {
    id: b
    property string label: ""
    signal clicked()
    width: t.implicitWidth + island.s(20)
    height: island.s(22)
    opacity: enabled ? 1 : 0.45
    color: Util.alpha(island.fg, m.containsMouse ? 0.14 : 0.07)
    Rectangle { width: parent.width; height: 1; color: m.pressed ? view.bevelDark : view.bevelLight }
    Rectangle { width: 1; height: parent.height; color: m.pressed ? view.bevelDark : view.bevelLight }
    Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: m.pressed ? view.bevelLight : view.bevelDark }
    Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: m.pressed ? view.bevelLight : view.bevelDark }
    Text {
      id: t
      anchors.centerIn: parent
      text: b.label
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(11)
      color: island.fg
    }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
  }
}
