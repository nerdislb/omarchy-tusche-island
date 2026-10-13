import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// One notification in the column under the island.
//
// Window: a window head (close gadget, app name, state) over Omarchy's
// card body, in Omarchy's popup frame; the body rolls out like a blind.
// Bubble: a speech bubble whose notch flows out of the bar edge; a strip
// spreads from the notch, then the body rolls down.
// Bloom (a Lavur theme's material, card.bloom): no surface of its own —
// the column draws the card as a sheet of wet paper; the text sits on it
// and fades with `textIn`, with the material's rules (one brushed signal
// stroke for a critical note, no red text).
// Material (the bar's edge "theme", Tusche & Papier): Omarchy's card in the
// theme's frame with its light and shadow – a hard ink shadow (Papier) or a
// halo (Tusche, Lavur) – soft controls, no title bar; a critical note keeps
// text and frame in the theme's colours and carries one narrow signal
// stripe on its left edge (and the signal on its symbol).
// The column drives `openness` (0 = title row, 1 = open), `spread`, `textIn`.
Item {
  id: card

  property var island: null
  property var entry: null
  property string kind: "note"          // note | more
  property int moreCount: 0
  property bool bubble: false
  property bool bloom: false
  property var material: null           // theme material (bar-material.json) or null
  readonly property var mat: !bloom && !bubble && material && material.card ? material.card : null
  readonly property var glassSpec: mat && material.glass ? material.glass : null
  readonly property bool glassOn: !!glassSpec && glassSpec.enabled !== false
  property real textIn: 1               // bloom: text opacity
  property bool first: false            // hangs from the island (bubble: notch)
  property bool active: false           // the open card, not a waiting row
  property string stateLabel: "now"     // now | next | paused
  property real openness: 0
  property real spread: 1
  property color tone: island ? island.accentColor : Commons.Color.accent

  signal opened()
  signal dismissed()
  signal promoted()
  signal later()
  signal action(string id)

  readonly property bool critical: !!(entry && entry.critical) && kind === "note"
  // Bubble, bloom and material share the soft controls (no gadget, rounded buttons).
  readonly property bool soft: bubble || bloom || !!mat
  readonly property real frame: Math.max(1, island.s(2))
  readonly property real notchH: bubble && first ? island.s(11) : 0
  readonly property real headH: island.s(26)
  readonly property real rowH: notchH + frame + headH + frame
  readonly property real pad: island.s(14)
  readonly property real bodyH: kind === "note" ? body.implicitHeight + pad * 2 : 0
  readonly property real fullH: rowH + bodyH
  readonly property real visibleH: rowH + bodyH * Math.max(0, Math.min(1, openness))
  // material: text stays in the theme's colours, the signal sits on the stripe and the symbol only
  readonly property color ink: mat || bloom ? (critical ? island.fg : tone) : critical ? island.urgentColor : tone
  readonly property color frameColor: critical && !mat ? island.urgentColor
    : active ? island.rim : Util.alpha(island.fg, 0.22)

  implicitHeight: visibleH
  height: visibleH

  // Bubble: the shape spreads from the notch to the full width.
  readonly property real shapeW: bubble ? island.s(44) + (width - island.s(44)) * spread : width
  readonly property real shapeX: (width - shapeW) / 2

  function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
  function rgba(hex, alpha) { var c = Qt.color(hex || "#000000"); return Qt.rgba(c.r, c.g, c.b, alpha === undefined ? 1 : alpha) }
  readonly property color headFill: critical ? mix(island.surface, island.urgentColor, 0.2)
    : active ? mix(island.surface, tone, 0.16) : mix(island.surface, island.fg, 0.04)
  readonly property color bevelLight: mix(headFill, island.fg, 0.28)
  readonly property color bevelDark: Qt.darker(island.surface, 1.7)

  // (material: the slot in NotificationColumn draws the card's shadow / halo,
  //  outside the clip the card slides out of)

  // ------------------------------------------------------------ surface
  Ui.BorderSurface {
    id: surface
    visible: !card.bloom
    x: card.shapeX
    y: card.notchH
    width: card.shapeW
    height: Math.max(0, card.visibleH - card.notchH)
    radius: card.bubble ? island.s(10) : 0
    color: card.glassOn ? "transparent" : island.surface
    borderSpec: card.glassOn ? Border.flat("transparent", card.frame) : (card.critical && !card.mat) || !card.active ? Border.flat(card.frameColor, card.frame) : island.frameSpec
  }
  GlassSurface {
    id: glass
    z: -0.5
    visible: card.glassOn && card.visible && card.height > 0
    active: visible
    spec: card.glassSpec
    x: surface.x; y: surface.y
    width: surface.width; height: surface.height
    radius: surface.radius
    onVisibleChanged: if (visible && card.active) play()
  }
  onActiveChanged: { if (active && glass.visible) glass.play(); else glass.stop() }
  // material: a critical note's one signal stripe on the left edge; in a
  // Lavur bloom a brushed stroke inside the bloom that comes and goes with
  // the text (the bloom is still a drop before the text fades in)
  Rectangle {
    visible: (!!card.mat || card.bloom) && card.critical
    z: 3
    x: card.bloom ? Math.round(island.s(9)) : card.shapeX
    y: card.notchH + (card.bloom ? Math.round(island.s(12)) : 0)
    width: Math.max(3, Math.round(island.s(4)))
    height: Math.max(0, card.visibleH - card.notchH - (card.bloom ? 2 * Math.round(island.s(12)) : 0))
    radius: card.bloom ? width / 2 : 0
    opacity: card.bloom ? card.textIn : 1
    color: island.urgentColor
  }

  // The notch: same fill as the bubble, open to the bar above it.
  Shape {
    id: notch
    visible: card.bubble && card.first
    readonly property real cx: card.width / 2
    readonly property real topHW: island.s(5)
    readonly property real baseHW: island.s(12)
    width: card.width
    height: card.notchH + card.frame + 1
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: island.surface
      strokeColor: "transparent"
      startX: notch.cx - notch.topHW; startY: 0
      PathLine { x: notch.cx + notch.topHW; y: 0 }
      PathLine { x: notch.cx + notch.baseHW; y: card.notchH + card.frame + 1 }
      PathLine { x: notch.cx - notch.baseHW; y: card.notchH + card.frame + 1 }
      PathLine { x: notch.cx - notch.topHW; y: 0 }
    }
    ShapePath {
      fillColor: "transparent"
      strokeColor: card.frameColor
      strokeWidth: card.frame
      startX: notch.cx - notch.topHW; startY: 0
      PathLine { x: notch.cx - notch.baseHW; y: card.notchH + card.frame * 0.5 }
    }
    ShapePath {
      fillColor: "transparent"
      strokeColor: card.frameColor
      strokeWidth: card.frame
      startX: notch.cx + notch.topHW; startY: 0
      PathLine { x: notch.cx + notch.baseHW; y: card.notchH + card.frame * 0.5 }
    }
  }

  // ------------------------------------------------------------ head
  Item {
    id: head
    x: card.shapeX + card.frame
    y: card.notchH + card.frame
    width: card.shapeW - card.frame * 2
    height: card.headH
    clip: true
    opacity: card.bloom ? card.textIn : card.bubble ? Math.max(0, (card.spread - 0.7) / 0.3) : 1

    // Window title bar: flat fill with a 1 px bevel.
    Rectangle {
      anchors.fill: parent
      visible: !card.soft
      color: card.headFill
      Rectangle { width: parent.width; height: 1; color: card.bevelLight }
      Rectangle { width: 1; height: parent.height; color: card.bevelLight }
      Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: card.bevelDark }
      Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: card.bevelDark }
    }

    // Close gadget (window) / shield (requester).
    Item {
      id: gadget
      width: card.soft ? 0 : island.s(26)
      height: parent.height
      visible: !card.soft
      Rectangle {
        visible: !card.critical
        anchors.centerIn: parent
        width: island.s(11); height: width
        color: closeMouse.pressed ? Util.alpha(island.fg, 0.25) : "transparent"
        border.width: 1; border.color: card.active ? island.fg : island.fgDim
        Rectangle { anchors.centerIn: parent; width: Math.max(2, island.s(3)); height: width; color: card.ink }
      }
      Text {
        visible: card.critical
        anchors.centerIn: parent
        text: "\u{f0ecc}"
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: island.fontFamily
        font.pixelSize: island.f(14)
        color: island.urgentColor
      }
      Rectangle { x: parent.width - 2; y: 1; width: 1; height: parent.height - 2; color: card.bevelDark; visible: !card.critical }
      Rectangle { x: parent.width - 1; y: 1; width: 1; height: parent.height - 2; color: card.bevelLight; visible: !card.critical }
      MouseArea {
        id: closeMouse
        anchors.fill: parent
        enabled: !card.critical
        cursorShape: Qt.PointingHandCursor
        onClicked: card.dismissed()
      }
    }

    Row {
      x: gadget.width + island.s(card.soft ? 12 : 8)
      width: parent.width - x - stateText.width - bubbleClose.width - island.s(24)
      anchors.verticalCenter: parent.verticalCenter
      spacing: island.s(10)
      clip: true

      Text {
        id: kicker
        anchors.verticalCenter: parent.verticalCenter
        text: card.kind === "more" ? "+" + card.moreCount + " MORE"
          : (String(card.entry && card.entry.app ? card.entry.app : "Notification").toUpperCase()
             + (card.critical ? " · REQUEST" : ""))
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width * 0.6)
        font.family: island.fontFamily
        font.pixelSize: island.f(12)
        font.bold: true
        color: card.kind === "more" ? island.fgDim : card.active || card.critical ? card.ink : island.fgDim
      }
      // Waiting rows say what they hold after the app name.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - kicker.width - parent.spacing
        visible: opacity > 0.01
        opacity: card.kind === "note" ? 1 - Math.max(0, Math.min(1, card.openness)) : 0
        text: card.entry ? [card.entry.summary, card.entry.body].filter(function(s) { return !!s }).join(" · ") : ""
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideRight
        font.family: island.fontFamily
        font.pixelSize: island.f(12)
        color: card.active ? island.fg : island.fgDim
      }
    }

    // Bubbles have no gadget: a small × on the right instead.
    Text {
      id: bubbleClose
      readonly property bool shown: card.soft && !card.critical && card.kind === "note"
      visible: shown
      // from the same condition, not from `visible` (reading the effective
      // visibility here looped with the row's layout)
      width: shown ? implicitWidth : 0
      anchors.right: parent.right
      anchors.rightMargin: island.s(10)
      anchors.verticalCenter: parent.verticalCenter
      text: "\u{f0156}"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(12)
      color: bubbleCloseMouse.containsMouse ? island.fg : island.fgDim
      MouseArea {
        id: bubbleCloseMouse
        anchors.fill: parent
        anchors.margins: -island.s(6)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.dismissed()
      }
    }

    Text {
      id: stateText
      anchors.right: bubbleClose.left
      anchors.rightMargin: island.s(10)
      anchors.verticalCenter: parent.verticalCenter
      text: card.kind === "more" ? "" : card.stateLabel
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(11)
      color: card.stateLabel === "paused" ? island.orangeColor : island.fgDim
    }
  }

  // ------------------------------------------------------------ body
  Item {
    x: card.shapeX + card.frame
    y: card.notchH + card.frame + card.headH
    width: card.shapeW - card.frame * 2
    height: Math.max(0, card.visibleH - card.rowH)
    clip: true
    visible: card.kind === "note" && height > 0
    opacity: card.bloom ? card.textIn * Math.max(0, Math.min(1, (card.openness - 0.6) / 0.4))
      : card.bubble ? Math.max(0, (card.spread - 0.7) / 0.3) : 1

    Column {
      id: body
      x: card.pad
      y: card.pad
      width: parent.width - card.pad * 2
      spacing: island.s(10)

      Row {
        width: parent.width
        spacing: island.s(14)

        // App tile: the sender's icon, else its glyph, in a tinted square.
        Rectangle {
          id: tile
          width: island.s(44); height: width
          radius: card.soft ? island.s(6) : 0
          color: card.mix(island.surface, card.ink, 0.22)
          readonly property string icon: island.notificationIcon(card.entry)
          Image {
            anchors.fill: parent
            anchors.margins: island.s(6)
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
            text: card.entry && card.entry.glyph ? card.entry.glyph : (card.critical ? "\u{f0ecc}" : "\u{f009a}")
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            font.family: island.fontFamily
            font.pixelSize: island.f(22)
            color: card.critical && (card.mat || card.bloom) ? island.urgentColor : card.ink
          }
        }

        Column {
          width: parent.width - tile.width - parent.spacing
          spacing: island.s(3)
          Text {
            width: parent.width
            text: card.entry ? (card.entry.summary || card.entry.app || "") : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            font.family: island.textFamily
            font.pixelSize: island.f(15)
            font.bold: true
            color: island.fg
          }
          Text {
            width: parent.width
            visible: text !== ""
            text: card.entry ? card.entry.body : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: island.textFamily
            font.pixelSize: island.f(14)
            color: island.fg
          }
        }
      }

      // Buttons: the sender's actions; a requester adds Later and Dismiss
      // (positive left, negative right).
      Row {
        visible: card.buttons.length > 0
        x: tile.width + island.s(14)
        spacing: island.s(10)
        Repeater {
          model: card.buttons
          Rectangle {
            id: btn
            required property var modelData
            width: Math.max(island.s(84), label.implicitWidth + island.s(26))
            height: island.s(28)
            radius: card.soft ? island.s(5) : 0
            readonly property bool primary: !!modelData.primary
            readonly property color fill: primary ? (btnMouse.containsMouse ? Qt.lighter(island.accentColor, 1.12) : island.accentColor)
              : Util.alpha(island.fg, btnMouse.containsMouse ? 0.14 : 0.07)
            color: fill
            border.width: card.soft ? 1 : 0
            border.color: Util.alpha(island.fg, 0.22)
            // 1 px bevel, inverted while pressed
            Rectangle { visible: !card.soft; width: parent.width; height: 1; color: btnMouse.pressed ? card.bevelDark : Util.alpha("#ffffff", 0.35) }
            Rectangle { visible: !card.soft; width: 1; height: parent.height; color: btnMouse.pressed ? card.bevelDark : Util.alpha("#ffffff", 0.35) }
            Rectangle { visible: !card.soft; y: parent.height - 1; width: parent.width; height: 1; color: btnMouse.pressed ? Util.alpha("#ffffff", 0.35) : card.bevelDark }
            Rectangle { visible: !card.soft; x: parent.width - 1; width: 1; height: parent.height; color: btnMouse.pressed ? Util.alpha("#ffffff", 0.35) : card.bevelDark }
            Text {
              id: label
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: btnMouse.pressed ? 1 : 0
              anchors.verticalCenterOffset: btnMouse.pressed ? 1 : 0
              text: btn.modelData.label
              textFormat: Text.PlainText
              renderType: Text.NativeRendering
              font.family: island.fontFamily
              font.pixelSize: island.f(12)
              font.bold: btn.primary
              color: btn.primary ? island.accentText : btn.modelData.deny && !card.mat && !card.bloom ? island.urgentColor : island.fg
            }
            MouseArea {
              id: btnMouse
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
                        { id: "dismiss", label: "Dismiss", kind: "dismiss", deny: true }])
  }

  // Left click: open (the open card) or bring forward (a waiting row);
  // right click dismisses, like Omarchy's toasts. Buttons and the close
  // gadget sit above this and take their own clicks.
  MouseArea {
    z: -1
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) { if (card.kind === "note") card.dismissed(); return }
      if (card.kind === "more" || !card.active) card.promoted()
      else if (!card.critical) card.opened()
    }
  }
}
