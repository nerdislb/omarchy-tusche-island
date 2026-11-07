pragma ComponentBehavior: Bound
import QtQuick

// Decoration shares the caller's drawn bounds and opacity. Removing its
// completion or changing flavor cancels every transient, including the ink.
Item {
  id: seal
  property string flavor: ""
  property bool active: false
  property string eventKey: ""
  property bool reduced: false
  property color accent: "#ffb27a"
  property real unit: 1
  property real stampY: height / 2
  property real stampAlpha: 0
  property real stampScale: 1
  property real stampAngle: -3
  property real inkAlpha: 0
  property real inkScale: 1
  property real marksAlpha: 0
  property real marksInset: 0
  readonly property bool animating: stampIn.running || inkIn.running || marksIn.running
  visible: active && (flavor === "tusche" || flavor === "register")

  function sync() {
    stampIn.stop(); inkIn.stop(); marksIn.stop()
    stampAlpha = 0; inkAlpha = 0; marksAlpha = 0
    stampScale = reduced ? 1 : 1.45; stampAngle = reduced ? -3 : -8
    inkScale = 1; marksInset = reduced ? 0 : 4
    if (!active) return
    if (flavor === "tusche") { stampIn.start(); if (!reduced) inkIn.start() }
    if (flavor === "register") marksIn.start()
  }
  onActiveChanged: sync()
  onEventKeyChanged: sync()
  onFlavorChanged: sync()
  onReducedChanged: sync()
  Component.onCompleted: sync()

  ParallelAnimation {
    id: stampIn
    NumberAnimation { target: seal; property: "stampAlpha"; to: 1; duration: seal.reduced ? 180 : 110 }
    SequentialAnimation {
      NumberAnimation { target: seal; property: "stampScale"; to: seal.reduced ? 1 : 0.96; duration: seal.reduced ? 0 : 180; easing.type: Easing.OutCubic }
      NumberAnimation { target: seal; property: "stampScale"; to: 1; duration: seal.reduced ? 0 : 80; easing.type: Easing.OutQuad }
    }
    NumberAnimation { target: seal; property: "stampAngle"; to: -3; duration: seal.reduced ? 0 : 260; easing.type: Easing.OutCubic }
  }
  ParallelAnimation {
    id: inkIn
    NumberAnimation { target: seal; property: "inkAlpha"; from: 0.2; to: 0; duration: 400 }
    NumberAnimation { target: seal; property: "inkScale"; from: 1; to: 1.25; duration: 400; easing.type: Easing.OutQuad }
  }
  ParallelAnimation {
    id: marksIn
    NumberAnimation { target: seal; property: "marksAlpha"; to: 1; duration: 90 }
    NumberAnimation { target: seal; property: "marksInset"; to: 0; duration: seal.reduced ? 0 : 90; easing.type: Easing.OutCubic }
  }
  Item {
    x: seal.width - 72 * seal.unit
    y: seal.stampY - height / 2
    width: 44 * seal.unit; height: width
    visible: seal.flavor === "tusche"
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "#db463e"
      opacity: seal.inkAlpha
      scale: seal.inkScale
    }
    Image {
      anchors.fill: parent
      source: "../assets/tusche/stamp-done.svg"
      sourceSize.width: Math.ceil(width * 2)
      sourceSize.height: Math.ceil(width * 2)
      opacity: seal.stampAlpha
      scale: seal.stampScale
      rotation: seal.stampAngle
    }
  }
  Repeater {
    model: seal.flavor === "register" ? 4 : 0
    Item {
      id: corner
      required property int index
      readonly property bool atRight: index % 2 === 1
      readonly property bool atBottom: index >= 2
      width: 10; height: 10
      x: atRight ? seal.width + 3 + seal.marksInset - width : -3 - seal.marksInset
      y: atBottom ? seal.height + 3 + seal.marksInset - height : -3 - seal.marksInset
      opacity: seal.marksAlpha
      Rectangle { width: 10; height: 2; y: corner.atBottom ? 8 : 0; color: seal.accent }
      Rectangle { width: 2; height: 10; x: corner.atRight ? 8 : 0; color: seal.accent }
    }
  }
}
