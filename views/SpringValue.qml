import QtQuick
import qs.Commons
import "GlassMath.js" as GlassMath

// One value on Apple's spring: `response` in seconds and `damping` fraction,
// stepped exactly by GlassMath.step on a frame clock. A new target mid-flight
// keeps position and velocity, so a burst of changes stays one movement; the
// clock stops once the value has settled (nothing ticks at rest). The first
// value, `live: false` (nothing on screen) and Reduced Motion put it in place
// at once. `cap` (0 or more) softly limits how far it may swing past its
// target, the way the float notes cap their overshoot.
QtObject {
  id: spring

  property real target: 0
  property real response: 0.32
  property real damping: 0.92
  property bool live: true
  // -1: no limit; 0: never past the target
  property real cap: -1
  // settled once this close and nearly still (velocity under 20 × this per s)
  property real precision: 0.2

  // The spring itself; `value` is what to show (with the cap applied).
  property real position: target
  property real velocity: 0
  // +1 / -1: the way it set out for its target, 0 at rest (for the cap)
  property int heading: 0
  property bool placed: false
  readonly property bool moving: clock.running
  readonly property real value: {
    var past = (position - target) * heading
    if (cap < 0 || past <= 0) return position
    return target + heading * (cap > 0 ? cap * Math.tanh(past / cap) : 0)
  }
  signal settled()

  function place() {
    clock.running = false
    position = target; velocity = 0; heading = 0
    placed = true
  }
  function retarget() {
    if (!placed || !live || Style.reduceMotion) { place(); return }
    if (Math.abs(target - position) > precision) heading = target > position ? 1 : -1
    clock.running = true
  }
  // An entrance: spring to the target from `from`, at rest.
  function restartFrom(from) {
    position = from; velocity = 0; heading = 0
    retarget()
  }
  // Stop where it is (an exit that must not carry on).
  function hold() { clock.running = false; velocity = 0; heading = 0 }

  onTargetChanged: retarget()
  onLiveChanged: place()
  Component.onCompleted: place()

  readonly property Connections motionWatch: Connections {
    target: Style
    function onReduceMotionChanged() { if (Style.reduceMotion) spring.place() }
  }
  readonly property FrameAnimation clock: FrameAnimation {
    onTriggered: {
      var st = GlassMath.step(spring.position, spring.velocity, spring.target, Math.min(frameTime, 1 / 30),
                              GlassMath.omega(spring.response), spring.damping)
      spring.position = st.x; spring.velocity = st.v
      if (Math.abs(st.x - spring.target) < spring.precision && Math.abs(st.v) < spring.precision * 20) {
        spring.place()
        spring.settled()
      }
    }
  }
}
