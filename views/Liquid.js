.pragma library
.import "GlassMath.js" as GlassMath

// The dynamic island's motion, as plain values stepped by one clock
// (views/DynamicStage.qml): Apple springs (response in seconds, damping
// fraction, GlassMath.step exactly) and timed fades for Reduced Motion. A
// value only says whether it still moves; the stage stops its clock once
// nothing does, so nothing ticks at rest.

// "Verspielt", as chosen on the Liquid Island prototype v2 (29.10.2026).
var tune = {
  cardResponse: 0.40, cardDamping: 0.68,       // a card pours out
  closeDamping: 0.80,                          // and is drawn back
  swell: 30, swellResponse: 0.30, swellDamping: 0.58, swellHold: 0.16,
  giveResponse: 0.42, giveDamping: 0.62,       // the capsule gives after its swell
  neck: 40, neckRelease: 0.34, neckResponse: 0.70,
  gulpResponse: 0.34, gulpDamping: 0.45, gulpWidth: 380, gulpHeight: 60,
  expandResponse: 0.50, expandDamping: 0.68,   // the island itself grows
  shrinkResponse: 0.42, shrinkDamping: 0.80,
  morphResponse: 0.40, morphDamping: 0.78,     // the compact capsule's width
  textAfter: 0.20,                             // a card's text comes in late
  fade: 0.15                                   // Reduced Motion's crossfades
}

function spring(x, eps) {
  return { x: x, v: 0, target: x, response: 0.4, damping: 0.99, eps: eps || 0.05, moving: false, fade: false }
}

// Spring to `target`; Reduced Motion (or nothing on screen) puts it there.
function go(s, target, response, damping, now) {
  s.fade = false
  s.target = target
  if (response !== undefined && response !== null) s.response = response
  if (damping !== undefined && damping !== null) s.damping = damping
  if (now) { place(s, target); return }
  s.moving = Math.abs(s.x - target) > s.eps || Math.abs(s.v) > s.eps * 20
  if (!s.moving) { s.x = target; s.v = 0 }
}

// A push of velocity (the capsule gulping a card), springing back to its target.
function kick(s, velocity, now) {
  if (now) return
  s.v += velocity
  s.fade = false
  s.moving = true
}

function place(s, x) {
  s.x = x; s.target = x; s.v = 0; s.moving = false; s.fade = false
}

// A timed, eased move instead of a spring (Reduced Motion's crossfades).
function fade(s, target, seconds, now) {
  s.target = target
  if (now || !(seconds > 0) || Math.abs(s.x - target) <= s.eps) { place(s, target); return }
  s.fade = true; s.from = s.x; s.t = 0; s.d = seconds; s.v = 0; s.moving = true
}

function tick(s, dt) {
  if (!s.moving) return false
  if (s.fade) {
    s.t += dt
    var k = Math.min(1, s.t / s.d)
    s.x = s.from + (s.target - s.from) * k * k * (3 - 2 * k)
    if (k >= 1) place(s, s.target)
    return s.moving
  }
  var st = GlassMath.step(s.x, s.v, s.target, dt, GlassMath.omega(s.response), s.damping)
  s.x = st.x; s.v = st.v
  if (Math.abs(s.x - s.target) < s.eps && Math.abs(s.v) < s.eps * 20) { s.x = s.target; s.v = 0; s.moving = false }
  return s.moving
}

// Squash and stretch with the fall: from the card's vertical speed (px/s at
// scale 1), its height stretches by up to 16 % falling and squashes by up to
// 10 % as it lands; the width gives 0.6 of that the other way.
function stretch(velocity, scale) {
  return Math.max(-0.10, Math.min(0.16, velocity / (2600 * Math.max(0.1, scale || 1))))
}

// Compact capsule: leading (status) and trailing (clock) halves balanced
// around the centre, as narrow as possible: `inset` from either end, at least
// `gap` between them. A leading half much wider than the clock is allowed
// past the balance (then it no longer centres). Without a status the clock
// sits alone in the middle.
function compactWidth(leadW, clockW, inset, gap) {
  if (!(leadW > 0)) return Math.ceil(clockW + 2 * inset)
  if (leadW <= clockW * 1.5) return Math.ceil(2 * (Math.max(leadW, clockW) + inset + gap / 2))
  return Math.ceil(inset + leadW + gap + clockW + inset)
}
