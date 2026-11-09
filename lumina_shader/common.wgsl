// Shared math, time-of-day curves, noise, and ACES tone mapping for Lumina Shader.

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// 1 while the sun is above the horizon in the Overworld, 0 at night or in other dimensions.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.08, 0.16, frame.sun_direction.y), frame.dimension == 0);
}

// 1 during sunrise and sunset when the sun is near the horizon, 0 at noon and deep night.
fn twilight() -> f32 {
    let near_horizon = 1.0 - smoothstep(0.0, 0.42, abs(frame.sun_direction.y));
    let visible = smoothstep(-0.14, 0.02, frame.sun_direction.y);
    return select(0.0, near_horizon * visible, frame.dimension == 0);
}

// 1 around midday when the sun is high overhead.
fn midday() -> f32 {
    return select(0.0, smoothstep(0.32, 0.72, frame.sun_direction.y), frame.dimension == 0);
}

// 1 at night in the Overworld.
fn night_factor() -> f32 {
    return select(0.0, smoothstep(0.08, -0.16, frame.sun_direction.y), frame.dimension == 0);
}

// Fast deterministic hash for 2D grid coordinates.
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Fast deterministic hash for 3D coordinates (used for starfield).
fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth 2D value noise.
fn noise2d(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Direct light color (sun by day, moon by night) with Warm Cinematic grading.
fn direct_light_color(warmth: f32) -> vec3<f32> {
    let day = daylight();
    let tw = twilight();
    let noon_col = mix(vec3<f32>(1.0, 0.97, 0.92), vec3<f32>(1.08, 0.95, 0.80), warmth);
    let sunset_col = mix(vec3<f32>(1.10, 0.72, 0.42), vec3<f32>(1.30, 0.58, 0.22), warmth);
    let sun_col = mix(noon_col, sunset_col, tw);
    let moon_col = vec3<f32>(0.22, 0.30, 0.46);
    let clear_col = mix(moon_col, sun_col, day);
    let rain_col = mix(vec3<f32>(0.12, 0.15, 0.22), vec3<f32>(0.52, 0.56, 0.62), day);
    return mix(clear_col, rain_col, frame.rain * 0.82);
}

// ACES Filmic tone mapping curve (Narkowicz approximation).
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
