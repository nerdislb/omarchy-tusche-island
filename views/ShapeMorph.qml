import QtQuick

// The island's shape between views, moving like the Dynamic Island: width
// and height each on a spring (response 0.40 s, damping 0.78), the one place
// with a visible, playful settle. A new size mid-flight keeps the velocity,
// so a burst of view changes stays one movement. It swings past its new size
// by at most `maxOvershoot` px and by no more than 4 % of it, so the lip and
// the pill never visibly dip below their height (and nothing below 0).
// `live: false` (unmapped, in the bar) and Reduced Motion: at once.
QtObject {
  id: shape

  property real targetWidth: 0
  property real targetHeight: 0
  property real maxOvershoot: 6
  property bool live: true

  readonly property real response: 0.40
  readonly property real damping: 0.78
  readonly property real width: widthSpring.value
  readonly property real height: heightSpring.value
  readonly property bool moving: widthSpring.moving || heightSpring.moving

  readonly property SpringValue widthSpring: SpringValue {
    target: shape.targetWidth
    response: shape.response; damping: shape.damping
    cap: Math.max(0, Math.min(shape.maxOvershoot, target * 0.04))
    live: shape.live
  }
  readonly property SpringValue heightSpring: SpringValue {
    target: shape.targetHeight
    response: shape.response; damping: shape.damping
    cap: Math.max(0, Math.min(shape.maxOvershoot, target * 0.04))
    live: shape.live
  }
}
