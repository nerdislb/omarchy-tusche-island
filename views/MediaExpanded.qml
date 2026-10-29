import QtQuick
import qs.Commons
import "../IslandModel.js" as Model

// The full player the island opens into: art, title and artist, a seekable
// progress bar with elapsed/remaining time, and transport controls.
Item {
  id: view

  property var island: null
  readonly property int pad: island.s(22)
  readonly property real progress: island.mediaLength > 0
    ? Math.max(0, Math.min(1, island.mediaPosition / island.mediaLength)) : 0

  AlbumArt {
    id: art
    x: view.pad
    y: island.s(20)
    width: island.s(58)
    height: width
    source: island.mediaArt
    tint: island.accentColor
    fontFamily: island.fontFamily
  }

  Visualizer {
    id: viz
    anchors.right: parent.right
    anchors.rightMargin: view.pad + island.s(2)
    anchors.verticalCenter: art.verticalCenter
    playing: island.mediaPlaying
    color: island.mediaTint
    barWidth: island.s(3)
    maxHeight: island.s(20)
  }

  Column {
    anchors.left: art.right
    anchors.leftMargin: island.s(14)
    anchors.right: viz.left
    anchors.rightMargin: island.s(14)
    anchors.verticalCenter: art.verticalCenter
    spacing: island.s(3)

    Text {
      width: parent.width
      text: island.mediaTitle || "Not playing"
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      elide: Text.ElideRight
      font.family: island.textFamily
      font.pixelSize: island.f(15)
      font.weight: Font.DemiBold
      color: island.fg
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: island.mediaArtist
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      elide: Text.ElideRight
      font.family: island.textFamily
      font.pixelSize: island.f(13)
      color: island.fgDim
    }
  }

  // Elapsed · bar · remaining
  Item {
    id: progressRow
    x: view.pad
    width: parent.width - view.pad * 2
    y: art.y + art.height + island.s(16)
    height: island.s(16)
    visible: island.mediaLength > 0

    Text {
      id: elapsed
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: Model.formatTime(island.mediaPosition)
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(11)
      font.features: { "tnum": 1 }
      color: island.fgDim
    }

    Text {
      id: remaining
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "-" + Model.formatTime(island.mediaLength - island.mediaPosition)
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
      font.family: island.fontFamily
      font.pixelSize: island.f(11)
      font.features: { "tnum": 1 }
      color: island.fgDim
    }

    Item {
      id: track
      anchors.left: elapsed.right
      anchors.leftMargin: island.s(10)
      anchors.right: remaining.left
      anchors.rightMargin: island.s(10)
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height

      // Under the pointer the bar and the playhead swell a little, on a
      // short spring without overshoot (response 0.20 s).
      readonly property real swell: Math.max(0, Math.min(1, swellSpring.value))
      readonly property real barHeight: island.s(5) + (island.s(7) - island.s(5)) * swell
      SpringValue { id: swellSpring; target: seek.containsMouse ? 1 : 0; response: 0.20; damping: 1; precision: 0.004; live: view.visible }
      // The played part follows the player as it plays (no lag); only a
      // click on the bar glides it there (response 0.20 s, no overshoot).
      property bool seekGlide: false
      SpringValue {
        id: seekSpring
        target: view.progress
        response: 0.20; damping: 1
        precision: 0.0005
        live: track.seekGlide && view.visible
        onSettled: track.seekGlide = false
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: track.barHeight
        radius: Math.min(Style.cornerRadius, Style.space(2))
        color: Util.alpha(island.fg, 0.16)

        Rectangle {
          id: played
          readonly property real k: Math.max(0, Math.min(1, seekSpring.value))
          height: parent.height
          radius: Math.min(Style.cornerRadius, Style.space(2))
          width: Math.max(k > 0 ? height : 0, parent.width * k)
          color: island.accentColor
        }

        // The playhead.
        Rectangle {
          readonly property real d: island.s(9) + (island.s(13) - island.s(9)) * track.swell
          width: d
          height: d
          radius: Math.min(Style.cornerRadius, Style.space(2))
          x: played.width - d / 2
          anchors.verticalCenter: parent.verticalCenter
          color: island.fg
          border.width: Math.max(1, island.s(2))
          border.color: island.bodyAt(0.6)
        }
      }

      MouseArea {
        id: seek
        anchors.fill: parent
        hoverEnabled: true
        enabled: island.mediaCanSeek
        cursorShape: island.mediaCanSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: function(mouse) {
          track.seekGlide = true
          island.mediaSeek(mouse.x / width)
          // a click where it already is: nothing to glide
          if (!seekSpring.moving) track.seekGlide = false
        }
      }
    }
  }

  // Where the sound goes (speakers, headphones, Bluetooth, HDMI).
  IconButton {
    anchors.right: parent.right
    anchors.rightMargin: view.pad - island.s(8)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: island.s(16)
    glyph: island.outputGlyph(island.sink)
    glyphSize: island.f(15)
    color: island.fgDim
    fontFamily: island.fontFamily
    onClicked: island.openOutputs()
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: island.s(14)
    spacing: island.s(26)

    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: "󰒮"
      glyphSize: island.f(22)
      color: island.fg
      fontFamily: island.fontFamily
      available: island.mediaCanPrevious
      onClicked: island.mediaPrevious()
    }

    // Rectangular accent action, matching the theme controls.
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: island.s(44)
      height: width
      radius: Math.min(Style.cornerRadius, Style.space(2))
      color: playMouse.pressed ? Qt.darker(island.accentColor, 1.12) : island.accentColor


      Text {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: island.mediaPlaying ? 0 : island.s(1)
        text: island.mediaPlaying ? "󰏤" : "󰐊"
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        font.family: island.fontFamily
        font.pixelSize: island.f(22)
        color: island.accentText
      }

      MouseArea {
        id: playMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: island.mediaToggle()
      }
    }

    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      glyph: "󰒭"
      glyphSize: island.f(22)
      color: island.fg
      fontFamily: island.fontFamily
      available: island.mediaCanNext
      onClicked: island.mediaNext()
    }
  }
}
