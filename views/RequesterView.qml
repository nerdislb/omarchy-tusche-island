import QtQuick
import qs.Commons

// An agent is waiting for input or approval (herdr, Corgi, OpenCode
// "blocked"). Laid out like the expanded island's "Agent finished"
// (views/DynamicAlert.qml, hybrid board 01): a round tile in the status
// colour with its glyph in black, the title in sentence case and a line
// under it, the actions as capsules. Approving happens in the agent itself
// ("Open"); the bar never answers for you.
Item {
  id: view

  property var island: null
  readonly property var agent: island ? island.attentionAgent : null
  readonly property var others: island ? island.desktop.blocked.slice(1) : []

  function s(px) { return island ? island.s(px) : px }
  function f(px) { return island ? island.f(px) : px }
  readonly property string family: island ? island.fontFamily : ""
  readonly property string words: island ? island.textFamily : ""
  readonly property color tone: island ? island.orangeColor : "#ffb27a"
  readonly property color ink: island ? island.fg : "#f2f2f2"
  readonly property color dim: Util.alpha(ink, 0.62)

  function since(a) {
    if (!a || !island) return ""
    var seen = island.desktop.seen[a.pane]
    if (!seen) return ""
    var m = Math.max(0, Math.round((Date.now() - seen.since) / 60000))
    return m < 1 ? "just now" : "for " + m + " min"
  }

  readonly property var actions: [
    { id: "open", label: "Open", primary: true },
    { id: "snooze", label: "Later (10 min)", primary: false },
    { id: "close", label: "Dismiss", primary: false }
  ]
  function run(id) {
    var a = view.agent
    if (id === "open") island.desktop.focusAgent(a)
    else if (id === "snooze" && a) island.desktop.snooze(a.pane)
    island.collapse()
  }

  Rectangle {
    id: tile
    x: view.s(18)
    y: view.s(18)
    width: view.s(44); height: width; radius: width / 2
    color: view.tone
    Text {
      anchors.centerIn: parent
      text: "\u{f0026}"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: view.family
      font.pixelSize: view.f(22)
      color: "#000000"
    }
  }

  Text {
    x: view.s(78)
    y: view.s(30) - implicitHeight / 2
    width: view.width - x - view.s(20)
    text: view.agent ? (view.agent.agent || "An agent") + " is waiting for you" : ""
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
    width: view.width - x - view.s(20)
    text: view.agent
      ? [view.agent.title || "Waiting for input", view.agent.project || "", view.since(view.agent),
         view.others.length ? "+" + view.others.length + " more" : ""].filter(function(t) { return !!t }).join(" · ")
      : ""
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    font.family: view.words
    font.pixelSize: view.f(12)
    color: view.dim
  }

  Row {
    x: view.s(78)
    y: view.s(72)
    spacing: view.s(10)
    Repeater {
      model: view.actions
      Rectangle {
        id: btn
        required property var modelData
        readonly property bool primary: !!modelData.primary
        width: Math.max(view.s(84), label.implicitWidth + view.s(28))
        height: view.s(26)
        radius: height / 2
        color: primary ? Util.alpha(view.tone, area.pressed ? 0.42 : area.containsMouse ? 0.32 : 0.22)
          : Util.alpha(view.ink, area.pressed ? 0.22 : area.containsMouse ? 0.16 : 0.10)
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
          onClicked: view.run(btn.modelData.id)
        }
      }
    }
  }
}
