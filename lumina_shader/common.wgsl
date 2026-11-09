// Shared math, time-of-day curves, noise, Aurora Borealis, and ACES tone mapping for Lumina Shader.

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// 1 while the sun is above the horizon in the Overworld, 0 at night or in other dimensions.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.08, 0.16, frame.sun_direction.y), frame.dimension == 0);
}

// Extended Golden Hour curve: active through morning and afternoon (up to sun_direction.y = 0.62)
// so sunrise and sunset warmth is rich and long-lasting.
fn twilight() -> f32 {
    let near_horizon = 1.0 - pow(smoothstep(0.0, 0.62, abs(frame.sun_direction.y)), 0.85);
    let visible = smoothstep(-0.14, 0.03, frame.sun_direction.y);
    return select(0.0, near_horizon * visible, frame.dimension == 0);
}

// 1 around high noon when the sun is overhead.
fn midday() -> f32 {
    return select(0.0, smoothstep(0.48, 0.82, frame.sun_direction.y), frame.dimension == 0);
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

// Direct light color (sun by day, moon by night) with rich Golden Hour and cozy slate-blue rain.
fn direct_light_color(warmth: f32) -> vec3<f32> {
    let day = daylight();
    let tw = twilight();
    let noon_col = mix(vec3<f32>(0.98, 0.95, 0.90), vec3<f32>(1.06, 0.94, 0.78), warmth);
    let sunset_col = mix(vec3<f32>(1.18, 0.70, 0.36), vec3<f32>(1.42, 0.58, 0.18), warmth);
    let sun_col = mix(noon_col, sunset_col, smoothstep(0.0, 0.85, tw));
    let moon_col = vec3<f32>(0.34, 0.46, 0.68);
    let clear_col = mix(moon_col, sun_col, day);
    let rain_col = mix(vec3<f32>(0.15, 0.21, 0.30), vec3<f32>(0.42, 0.50, 0.60), day);
    return mix(clear_col, rain_col, frame.rain * 0.85);
}

// Procedural Aurora Borealis ribbons (emerald-green to cyan-teal with soft violet upper curtains).
fn aurora_borealis(dir: vec3<f32>, night: f32, strength: f32) -> vec3<f32> {
    let vis = night * (1.0 - frame.rain * 0.85) * strength * smoothstep(0.05, 0.22, dir.y);
    if vis <= 0.005 {
        return vec3<f32>(0.0);
    }

    let p = dir.xz / (dir.y + 0.20) * 1.35;
    let t = frame.time * 0.075;

    let warp = noise2d(p * 1.35 + vec2<f32>(t * 0.65, -t * 0.45)) - 0.5;
    let wave1 = sin(p.x * 2.1 + p.y * 0.85 + warp * 3.1 + t * 1.35);
    let wave2 = sin(p.x * 3.5 - p.y * 1.45 - warp * 2.5 - t * 1.05);

    let ribbon1 = pow(smoothstep(0.45, 0.98, 1.0 - abs(wave1)), 1.6);
    let ribbon2 = pow(smoothstep(0.52, 0.99, 1.0 - abs(wave2)), 1.8) * 0.80;

    let curtain_rays = 0.62 + 0.38 * noise2d(vec2<f32>(p.x * 6.2 + t * 0.35, p.y * 6.2 - t * 0.25));
    let intensity = (ribbon1 + ribbon2) * curtain_rays;

    let zenith_fade = 1.0 - smoothstep(0.62, 0.96, dir.y);
    let color_shift = clamp((dir.y - 0.12) * 1.9 + (ribbon2 - ribbon1 * 0.3) * 0.45, 0.0, 1.0);

    let emerald_low = vec3<f32>(0.08, 0.94, 0.58);
    let teal_mid = vec3<f32>(0.14, 0.78, 0.92);
    let violet_high = vec3<f32>(0.64, 0.28, 0.96);

    let base_grad = mix(emerald_low, teal_mid, smoothstep(0.0, 0.55, color_shift));
    let aurora_col = mix(base_grad, violet_high, smoothstep(0.42, 0.95, color_shift));

    return aurora_col * intensity * zenith_fade * vis * 0.48;
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
