import QtQuick
import qs.Commons

// Keep each view at its natural size. A view comes in the way the Dynamic
// Island's content does: it fades in (140 ms) while it grows from 96 % around
// the island's centre on a soft spring (response 0.30 s, no overshoot) that
// lands with the shape's settle. Going, it only fades, quicker (60 ms), where
// it stands: no zoom. Unseen (parent.live false) and Reduced Motion: at once.
Item {
  id: slot
  property bool active: false
  readonly property real dpr: parent && parent.dpr > 0 ? parent.dpr : 1
  readonly property bool live: !parent || parent.live !== false
  x: parent ? Math.round((parent.width - width) / 2 * dpr) / dpr : 0
  y: parent ? Math.round((parent.height - height) / 2 * dpr) / dpr : 0
  opacity: 0
  scale: grow.value
  visible: opacity > 0.01
  enabled: active

  SpringValue { id: grow; target: 1; response: 0.30; damping: 1; precision: 0.0005 }
  NumberAnimation { id: fade; target: slot; property: "opacity"; easing.type: Easing.OutCubic }

  function show(now) {
    fade.stop()
    if (now || !live || Style.reduceMotion) {
      grow.place()
      opacity = active ? 1 : 0
      return
    }
    if (active) {
      // From nothing it grows in; caught on its way out it carries on from there.
      grow.restartFrom(opacity <= 0.01 ? 0.96 : grow.position)
      fade.to = 1
      fade.duration = Style.duration(140)
    } else {
      grow.hold()
      fade.to = 0
      fade.duration = Style.duration(60)
    }
    fade.start()
  }
  onActiveChanged: show(false)
  Component.onCompleted: show(true)
}
