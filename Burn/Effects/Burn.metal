//
//  Burn.metal
//
//  The dissolve at the heart of the app.
//
//  The algorithm is the classic burn-dissolve: build a noise field over the
//  view, compare it against an advancing threshold, and decide per pixel
//  whether that spot is ash, on fire, or still untouched. Because the field is
//  ragged rather than a straight line, the edge eats into the glyphs the way
//  paper actually chars.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// How strongly the burn front leans across (x) and down (y) the view.
///
/// `EmberParticles.swift` mirrors these two numbers so the sparks light up as
/// the fire reaches them. Change them here and change them there.
constant float kBurnSweepX = 0.72;
constant float kBurnSweepY = 0.18;

/// Share of the field taken by the sweep rather than the noise. Higher values
/// give a cleaner travelling front; lower values give a more chaotic crumble.
constant float kBurnSweepWeight = 0.55;

namespace burn_fx {

/// Deterministic 2D → 1D hash. Same input, same spark, every run.
inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

/// Smoothly interpolated value noise over the unit grid.
inline float valueNoise(float2 p) {
    float2 cell = floor(p);
    float2 offset = fract(p);
    // Hermite fade so cell boundaries do not show up as creases.
    float2 fade = offset * offset * (3.0 - 2.0 * offset);

    float a = hash21(cell);
    float b = hash21(cell + float2(1.0, 0.0));
    float c = hash21(cell + float2(0.0, 1.0));
    float d = hash21(cell + float2(1.0, 1.0));

    return mix(mix(a, b, fade.x), mix(c, d, fade.x), fade.y);
}

/// Four octaves of value noise: big tongues of flame plus fine crumbling detail.
inline float fbm(float2 p) {
    float total = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 4; ++octave) {
        total += amplitude * valueNoise(p);
        p *= 2.02; // slightly off 2.0 to avoid the octaves lining up
        amplitude *= 0.5;
    }
    // The octave amplitudes sum to 0.9375, so rescale back to roughly 0...1.
    return total / 0.9375;
}

} // namespace burn_fx

/// Burns away the pixels of the view it is attached to.
///
/// - Parameters:
///   - size: view size in points, so the noise scale is resolution independent.
///   - progress: 0 = untouched, 1 = completely consumed.
///   - seed: offsets the noise field so no two thoughts burn identically.
///   - edge: width of the glowing band, in field units (0.16 is a good default).
[[ stitchable ]] half4 burn(float2 position,
                            half4 color,
                            float2 size,
                            float progress,
                            float seed,
                            float edge)
{
    // Only ink burns. Leaving transparent pixels alone keeps the fire on the
    // letters instead of scorching a rectangle around them.
    if (color.a <= 0.001h || progress <= 0.0) {
        return color;
    }

    float2 uv = position / max(size, float2(1.0));

    // A ragged field, biased left-to-right and slightly downward so the page
    // catches at one corner and the front travels, rather than the whole
    // paragraph fading at once.
    float noise = burn_fx::fbm(uv * 3.4 + seed);
    float sweep = uv.x * kBurnSweepX + uv.y * kBurnSweepY;
    float field = mix(noise, sweep, kBurnSweepWeight);

    // Push the threshold past both ends of the field so progress == 1 really
    // does consume everything, edge band included.
    float band = max(edge, 0.001);
    float threshold = progress * (1.0 + band * 2.0) - band;
    float ahead = field - threshold;

    if (ahead <= 0.0) {
        return half4(0.0h); // behind the front: ash
    }
    if (ahead >= band) {
        return color; // beyond the heat: untouched
    }

    // Inside the burning band. `heat` runs 1 at the burn line down to 0 at the
    // outer edge of the glow.
    float t = ahead / band;
    float heat = 1.0 - t;

    const half3 whiteHot = half3(1.00h, 0.96h, 0.78h);
    const half3 ember    = half3(1.00h, 0.44h, 0.08h);
    const half3 charred  = half3(0.14h, 0.08h, 0.06h);

    half3 tint;
    if (t < 0.35) {
        tint = mix(whiteHot, ember, half(smoothstep(0.0, 0.35, t)));
    } else {
        tint = mix(ember, charred, half(smoothstep(0.35, 1.0, t)));
    }

    // Ease the char back into the original ink at the trailing edge so there is
    // no visible seam between "hot" and "not".
    half3 ink = color.rgb / max(color.a, 0.001h); // un-premultiply
    tint = mix(tint, ink, half(smoothstep(0.75, 1.0, t)));

    // Bloom the leading edge. Clamping to display range still reads as heat.
    tint *= 1.0h + 0.9h * half(smoothstep(0.5, 1.0, heat));

    return half4(tint * color.a, color.a); // back to premultiplied
}
