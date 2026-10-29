#version 440
// The dynamic island as one liquid shape (views/LiquidShape.qml): up to ten
// rounded boxes – the capsule, the capsules that detach beside it and the
// banner cards – melted into one signed distance field with a polynomial
// smooth minimum, so a card pours out of the capsule through a neck that
// lets go, and is drawn back in the same way (Liquid Island prototype v2,
// 29.10.2026). Filled true black, antialiased on the device pixel grid, with
// a thin key line along the edge in the content's status colour; where two
// boxes melt, their colours and opacities blend by distance.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // this item's size, px
    vec2 origin;    // its top-left in the stage, px (the boxes are in stage px)
    float dpr;      // device pixels per px
    float line;     // key line width, px
    // per box: rect (x, y, w, h) · shape (radius, neck k, opacity, key alpha) · key colour
    vec4 b0; vec4 s0; vec4 c0;
    vec4 b1; vec4 s1; vec4 c1;
    vec4 b2; vec4 s2; vec4 c2;
    vec4 b3; vec4 s3; vec4 c3;
    vec4 b4; vec4 s4; vec4 c4;
    vec4 b5; vec4 s5; vec4 c5;
    vec4 b6; vec4 s6; vec4 c6;
    vec4 b7; vec4 s7; vec4 c7;
    vec4 b8; vec4 s8; vec4 c8;
    vec4 b9; vec4 s9; vec4 c9;
};

float sdBox(vec2 p, vec4 b, float r) {
    vec2 h = 0.5 * b.zw;
    r = min(r, min(h.x, h.y));
    vec2 q = abs(p - (b.xy + h)) - h + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// polynomial smooth minimum (k in px; 0 = a plain union)
float smin(float a, float b, float k) {
    if (k <= 0.01) return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

float dist = 1e5;
bool any_ = false;
float wsum = 0.0;
float asum = 0.0;
vec4 ksum = vec4(0.0);

void add(vec2 p, vec4 b, vec4 s, vec4 c) {
    if (b.z <= 0.0 || b.w <= 0.0 || s.z <= 0.001) return;
    float d = sdBox(p, b, s.x);
    dist = any_ ? smin(dist, d, s.y) : d;
    any_ = true;
    // nearer boxes weigh more: inside a box it is that box's colour
    float w = exp(-max(d, 0.0) * 0.25);
    wsum += w;
    asum += w * s.z;
    ksum += w * vec4(c.rgb, c.a * s.w);
}

void main() {
    vec2 p = qt_TexCoord0 * size + origin;
    add(p, b0, s0, c0); add(p, b1, s1, c1); add(p, b2, s2, c2); add(p, b3, s3, c3); add(p, b4, s4, c4);
    add(p, b5, s5, c5); add(p, b6, s6, c6); add(p, b7, s7, c7); add(p, b8, s8, c8); add(p, b9, s9, c9);
    if (!any_ || wsum <= 1e-6) { fragColor = vec4(0.0); return; }
    float alpha = asum / wsum;
    vec4 key = ksum / wsum;
    float px = max(dpr, 0.5);
    float inside = clamp(0.5 - dist * px, 0.0, 1.0);
    float fill = inside * alpha;
    // the key line: the band of `line` px just inside the edge
    float band = (inside - clamp(0.5 - (dist + line) * px, 0.0, 1.0)) * key.a * alpha;
    float a = band + fill * (1.0 - band);
    fragColor = vec4(key.rgb * band, a) * qt_Opacity;
}
