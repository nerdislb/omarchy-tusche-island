import QtQuick
import qs.Commons
import "GlassMath.js" as GlassMath

// The selection of a list of rows: one plate that glides to the selected row
// instead of every row fading its own highlight, the bar's TabLens turned on
// its side. Its top and bottom edge each ride a spring: the edge in front
// leads (response 0.22 s), the one behind follows (0.30 s), damping 0.9, so
// the plate draws out a little on the way, gives up a touch of width for it
// and lands without a bounce. Square as the theme (radius 3 px at most). A
// retarget mid-flight keeps both edges' velocity, so a burst of clicks stays
// one movement.
// It glides only when the selection changes (the target's `key`): the same
// row moving, or a Repeater rebuilding it after a model reload (a fresh
// delegate stands at y 0 until its column lays it out), takes the plate along
// at once. Not live (unseen), Reduced Motion and the first placement put it
// straight in place. Sits under the rows, in the same origin as their column.
Rectangle {
  id: lens

  // the selected row, with a `key`
  property Item target: null
  property bool live: true
  // Read from the target itself: a binding on it may still be stale when the
  // target's geometry announces the change.
  function keyOf(item) { return item && item.key !== undefined ? String(item.key) : "" }

  readonly property real leadResponse: 0.22
  readonly property real trailResponse: 0.30
  readonly property real damping: 0.9

  readonly property real targetTop: target ? target.y : 0
  readonly property real targetBottom: target ? target.y + target.height : 0
  property real edgeTop: targetTop
  property real edgeBottom: targetBottom
  property real topVelocity: 0
  property real bottomVelocity: 0
  // +1 heading down, -1 heading up
  property int heading: 0
  property bool placed: false
  property string placedKey: ""
  readonly property bool moving: glide.running
  // How far the plate is drawn out past its row; it gives up a little width for it.
  readonly property real stretch: Math.max(0, (edgeBottom - edgeTop) - (targetBottom - targetTop))
  readonly property real squeeze: Math.min(Style.space(2), stretch * 0.05)

  // How much of `item` (a row in the same column) the plate covers, 0 to 1.
  function cover(item) {
    if (!item || !visible) return 0
    return Math.max(0, Math.min(1, (Math.min(edgeBottom, item.y + item.height) - Math.max(edgeTop, item.y)) / Math.max(1, item.height)))
  }

  x: (target ? target.x : 0) + squeeze
  y: edgeTop
  width: Math.max(0, (target ? target.width : 0) - 2 * squeeze)
  height: Math.max(0, edgeBottom - edgeTop)
  visible: !!target
  radius: Math.min(Style.cornerRadius, Style.space(2), 3)

  function place() {
    glide.running = false
    edgeTop = targetTop; edgeBottom = targetBottom
    topVelocity = 0; bottomVelocity = 0
    heading = 0
    placed = !!target
    placedKey = keyOf(target)
  }
  function retarget() {
    if (!target) return
    if (!placed || !live || Style.reduceMotion || (keyOf(target) === placedKey && !glide.running)) { place(); return }
    var from = (edgeTop + edgeBottom) / 2, to = (targetTop + targetBottom) / 2
    if (Math.abs(to - from) > 0.5) heading = to > from ? 1 : -1
    glide.running = true
  }
  onTargetTopChanged: retarget()
  onTargetBottomChanged: retarget()
  onLiveChanged: place()
  Connections { target: Style; function onReduceMotionChanged() { if (Style.reduceMotion) lens.place() } }

  FrameAnimation {
    id: glide
    onTriggered: {
      var dt = Math.min(frameTime, 1 / 30)
      var topResponse = lens.heading < 0 ? lens.leadResponse : lens.trailResponse
      var bottomResponse = lens.heading > 0 ? lens.leadResponse : lens.trailResponse
      var t = GlassMath.step(lens.edgeTop, lens.topVelocity, lens.targetTop, dt, GlassMath.omega(topResponse), lens.damping)
      var b = GlassMath.step(lens.edgeBottom, lens.bottomVelocity, lens.targetBottom, dt, GlassMath.omega(bottomResponse), lens.damping)
      lens.edgeTop = t.x; lens.topVelocity = t.v
      lens.edgeBottom = b.x; lens.bottomVelocity = b.v
      if (Math.abs(t.x - lens.targetTop) < 0.2 && Math.abs(b.x - lens.targetBottom) < 0.2
          && Math.abs(t.v) < 4 && Math.abs(b.v) < 4) lens.place()
    }
  }
}
