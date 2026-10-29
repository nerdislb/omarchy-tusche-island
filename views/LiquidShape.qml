import QtQuick

// The dynamic island's black, as one liquid shape (shaders/liquid.frag): up
// to ten rounded boxes melted with a smooth minimum. `boxes` is a list of
// { x, y, w, h, r, k, a, key, keyAlpha } in the stage's pixels, the capsule
// first: `k` is how far a box melts into everything before it (the neck of
// a card pouring out of the capsule; 0 keeps it apart), `a` its opacity,
// `key` and `keyAlpha` the thin line along its edge. The item itself only
// covers what the boxes need (their bounds, plus room for the necks), so a
// frame shades that and no more; nothing redraws while the boxes rest.
ShaderEffect {
  id: liquid

  property var boxes: []
  property real dpr: 1
  property real line: 1

  readonly property var bounds: {
    var b = boxes || []
    var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, reach = 2
    for (var i = 0; i < b.length && i < 10; i++) {
      var o = b[i]
      if (!o || !(o.w > 0) || !(o.h > 0) || !(o.a > 0.001)) continue
      x0 = Math.min(x0, o.x); y0 = Math.min(y0, o.y)
      x1 = Math.max(x1, o.x + o.w); y1 = Math.max(y1, o.y + o.h)
      reach = Math.max(reach, (o.k || 0) / 2 + 2)
    }
    if (x1 < x0) return { x: 0, y: 0, w: 0, h: 0 }
    return { x: Math.floor(x0 - reach), y: Math.floor(y0 - reach),
             w: Math.ceil(x1 - x0 + 2 * reach) + 1, h: Math.ceil(y1 - y0 + 2 * reach) + 1 }
  }

  x: bounds.x
  y: bounds.y
  width: bounds.w
  height: bounds.h
  visible: bounds.w > 0 && bounds.h > 0

  property size size: Qt.size(width, height)
  property point origin: Qt.point(x, y)

  function rect(i) {
    var o = boxes && boxes[i]
    return o && o.w > 0 && o.h > 0 ? Qt.vector4d(o.x, o.y, o.w, o.h) : Qt.vector4d(0, 0, 0, 0)
  }
  function shape(i) {
    var o = boxes && boxes[i]
    return o ? Qt.vector4d(o.r || 0, o.k || 0, o.a === undefined ? 1 : o.a, o.keyAlpha || 0) : Qt.vector4d(0, 0, 0, 0)
  }
  function tone(i) {
    var o = boxes && boxes[i]
    return o && o.key !== undefined ? o.key : "transparent"
  }

  property vector4d b0: rect(0); property vector4d s0: shape(0); property color c0: tone(0)
  property vector4d b1: rect(1); property vector4d s1: shape(1); property color c1: tone(1)
  property vector4d b2: rect(2); property vector4d s2: shape(2); property color c2: tone(2)
  property vector4d b3: rect(3); property vector4d s3: shape(3); property color c3: tone(3)
  property vector4d b4: rect(4); property vector4d s4: shape(4); property color c4: tone(4)
  property vector4d b5: rect(5); property vector4d s5: shape(5); property color c5: tone(5)
  property vector4d b6: rect(6); property vector4d s6: shape(6); property color c6: tone(6)
  property vector4d b7: rect(7); property vector4d s7: shape(7); property color c7: tone(7)
  property vector4d b8: rect(8); property vector4d s8: shape(8); property color c8: tone(8)
  property vector4d b9: rect(9); property vector4d s9: shape(9); property color c9: tone(9)

  fragmentShader: Qt.resolvedUrl("shaders/liquid.frag.qsb")
}
