import QtQuick
import qs.Commons
import "../IslandModel.js" as Model

// One notification of the dynamic island (Island.qml `look: "dynamic"`), the
// content of a black banner card that pours out of the capsule
// (views/DynamicStage.qml draws the card itself). Laid out as the approved
// board (hybrid design 29.10.2026, board 01): a round tile in the app's tone
// with its glyph in black, the title, the text, the app's name small in its
// tone at the top right; the sender's actions (a requester's Open, Later,
// Dismiss) as capsules underneath. Waiting rows are one line, "+N more" a
// short one. Sentence case throughout.
//
// The same paths as the classic card (views/NoteCard.qml): a click opens the
// open card (or brings a waiting row forward), a right click or the × that
// shows on hover dismisses, the buttons run their actions.
Item {
  id: card

  property var island: null
  property var entry: null
  property string kind: "note"          // note | more
  property int moreCount: 0
  property bool active: false           // the open card, not a waiting row
  property string stateLabel: "now"     // now | next | paused | ""
  property color tone: "white"
  property color ink: "#f2f2f2"         // text on the island's black
  readonly property string flavor: island && island.flavor !== undefined ? island.flavor : ""
  readonly property bool completion: Model.isAgentCompletion(entry)
  readonly property real sealSpace: completion && flavor === "tusche" ? s(64) : 0
  readonly property color dim: Util.alpha(ink, 0.62)

  signal opened()
  signal dismissed()
  signal promoted()
  signal later()
  signal action(string id)

  function s(px) { return island ? island.s(px) : px }
  function f(px) { return island ? island.f(px) : px }
  function gf(px) { return island ? island.gf(px) : px }
  readonly property string family: island ? island.fontFamily : ""
  readonly property string words: island ? island.textFamily : ""

  readonly property bool critical: !!(entry && entry.critical) && kind === "note"
  readonly property string mode: kind === "more" ? "more" : active ? "open" : "row"
  readonly property real pad: s(16)
  readonly property real tileD: s(38)
  readonly property real textX: pad + tileD + s(14)

  readonly property real openH: Math.max(pad * 2 + tileD,
    pad + titleText.implicitHeight + s(3) + (bodyText.visible ? bodyText.implicitHeight : 0)
      + (buttonRow.visible ? s(10) + s(26) : 0) + pad)
  readonly property real rowH: s(40)
  readonly property real moreH: s(30)
  implicitHeight: mode === "open" ? openH : mode === "more" ? moreH : rowH
  height: implicitHeight

  property bool hovering: hover.hovered
  HoverHandler { id: hover }

  // Left click: open (the open card) or bring forward (a waiting row, +N);
  // right click dismisses. Buttons and × sit above and take their own clicks.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) { if (card.kind === "note") card.dismissed(); return }
      if (card.kind === "more" || !card.active) card.promoted()
      else if (!card.critical) card.opened()
    }
  }

  // ------------------------------------------------------------ the tile
  component Tile: Rectangle {
    id: tile
    property real d: card.tileD
    property real glyphPx: card.gf(18)
    width: d; height: d; radius: d / 2
    readonly property string icon: card.island && card.entry ? card.island.notificationIcon(card.entry) : ""
    readonly property bool hasIcon: icon !== "" && image.status === Image.Ready
    color: hasIcon ? Util.alpha(card.tone, 0.22) : card.tone
    Image {
      id: image
      anchors.fill: parent
      anchors.margins: tile.d * 0.18
      visible: tile.hasIcon
      source: tile.icon
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }
    Text {
      anchors.centerIn: parent
      visible: !tile.hasIcon
      text: card.entry && card.entry.glyph ? card.entry.glyph : (card.critical ? "\u{f0ecc}" : "\u{f009a}")
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: card.family
      font.pixelSize: tile.glyphPx
      color: "#000000"
    }
  }

  // ------------------------------------------------------------ open card
  Item {
    id: openView
    anchors.fill: parent
    visible: opacity > 0.01
    opacity: card.mode === "open" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Tile { x: card.pad; y: card.pad }

    Text {
      id: titleText
      x: card.textX
      y: card.pad + card.s(1)
      width: appText.x - x - card.s(12)
      text: card.entry ? (card.completion ? Model.completionTitle(card.entry.summary, card.flavor) : card.entry.summary || card.entry.app || "") : ""
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      elide: Text.ElideRight
      maximumLineCount: 1
      font.family: card.words
      font.pixelSize: card.f(13)
      font.bold: true
      color: card.ink
    }
    // the app's name, small, in its tone; a requester says so
    Text {
      id: appText
      anchors.right: parent.right
      anchors.rightMargin: card.s(18)
      y: card.pad + card.s(2)
      width: Math.min(implicitWidth, card.width * 0.35)
      opacity: closeMark.shown ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 120 } }
      text: (card.entry && card.entry.app ? card.entry.app : "Notification") + (card.critical ? " · request" : "")
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignRight
      font.family: card.family
      font.pixelSize: card.f(10)
      color: card.tone
    }
    // × on hover (a requester answers with its buttons)
    Text {
      id: closeMark
      readonly property bool shown: card.hovering && !card.critical
      anchors.right: parent.right
      anchors.rightMargin: card.s(16)
      y: card.pad - card.s(1)
      visible: opacity > 0.01
      opacity: shown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }
      text: "\u{f0156}"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: card.family
      font.pixelSize: card.f(13)
      color: closeArea.containsMouse ? card.ink : card.dim
      MouseArea {
        id: closeArea
        anchors.fill: parent
        anchors.margins: -card.s(6)
        enabled: closeMark.shown
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.dismissed()
      }
    }
    Text {
      id: bodyText
      x: card.textX
      y: titleText.y + titleText.implicitHeight + card.s(3)
      width: card.width - x - card.s(18) - card.sealSpace
      visible: text !== ""
      text: card.entry ? card.entry.body : ""
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight
      font.family: card.words
      font.pixelSize: card.f(12)
      color: card.dim
    }

    // The sender's actions; a requester adds Later and Dismiss (positive first).
    Row {
      id: buttonRow
      x: card.textX
      y: (bodyText.visible ? bodyText.y + bodyText.implicitHeight : titleText.y + titleText.implicitHeight) + card.s(10)
      spacing: card.s(10)
      visible: card.buttons.length > 0
      Repeater {
        model: card.buttons
        Rectangle {
          id: btn
          required property var modelData
          readonly property bool primary: !!modelData.primary
          width: Math.max(card.s(88), label.implicitWidth + card.s(28))
          height: card.s(26)
          radius: height / 2
          color: primary ? Util.alpha(card.tone, btnArea.containsMouse ? 0.32 : 0.22)
            : Util.alpha(card.ink, btnArea.containsMouse ? 0.16 : 0.10)
          Text {
            id: label
            anchors.centerIn: parent
            text: btn.modelData.label
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.family: card.family
            font.pixelSize: card.f(12)
            font.bold: btn.primary
            color: btn.primary ? card.tone : card.ink
          }
          MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var k = btn.modelData.kind
              if (k === "open") card.opened()
              else if (k === "later") card.later()
              else if (k === "dismiss") card.dismissed()
              else card.action(btn.modelData.id)
            }
          }
        }
      }
    }
  }

  readonly property var buttons: {
    if (kind !== "note" || !entry) return []
    var acts = (entry.actions || []).slice(0, critical ? 2 : 3).map(function(a) {
      return { id: a.id, label: a.text, kind: "action", primary: false }
    })
    if (!critical) return acts
    if (acts.length === 0) acts = [{ id: "open", label: "Open", kind: "open", primary: false }]
    acts[0].primary = true
    return acts.concat([{ id: "later", label: "Later", kind: "later" },
                        { id: "dismiss", label: "Dismiss", kind: "dismiss" }])
  }

  // ------------------------------------------------------------ waiting row
  Item {
    anchors.fill: parent
    visible: opacity > 0.01
    opacity: card.mode === "row" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Tile {
      d: card.s(24)
      glyphPx: card.gf(12)
      x: card.s(10)
      anchors.verticalCenter: parent.verticalCenter
    }
    Row {
      x: card.s(44)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - rowState.width - card.s(28)
      spacing: card.s(8)
      clip: true
      Text {
        id: rowApp
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.4)
        text: (card.entry && card.entry.app ? card.entry.app : "Notification") + (card.critical ? " · request" : "")
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideRight
        font.family: card.family
        font.pixelSize: card.f(12)
        font.bold: true
        color: card.critical ? card.tone : card.ink
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - rowApp.width - parent.spacing
        text: card.entry ? [card.entry.summary, card.entry.body].filter(function(t) { return !!t }).join(" · ") : ""
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideRight
        font.family: card.words
        font.pixelSize: card.f(12)
        color: card.dim
      }
    }
    Text {
      id: rowState
      anchors.right: parent.right
      anchors.rightMargin: card.s(18)
      anchors.verticalCenter: parent.verticalCenter
      text: card.stateLabel === "now" ? "" : card.stateLabel
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: card.family
      font.pixelSize: card.f(11)
      color: card.stateLabel === "paused" && card.island ? card.island.orangeColor : card.dim
    }
  }

  // ------------------------------------------------------------ +N more
  Text {
    anchors.centerIn: parent
    visible: card.mode === "more"
    text: "+" + card.moreCount + " more"
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    font.family: card.family
    font.pixelSize: card.f(12)
    color: card.dim
  }
}
