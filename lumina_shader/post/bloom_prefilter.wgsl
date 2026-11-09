// Post Pass 2 (Quarter Resolution, scale = 0.25, output = "bloom_a"):
// Extracts bright highlights while protecting white snowfields and clouds from hazing over at noon.

fn post(input: PostInput) -> vec4<f32> {
    let px = 1.0 / frame.resolution;
    var sum = vec3<f32>(0.0);
    var weight = 0.0;

    for (var i = 0; i < 4; i++) {
        let corner = vec2<f32>(f32(i & 1), f32(i >> 1u)) * 2.0 - 1.0;
        let uv = clamp(input.uv + corner * px, vec2<f32>(0.001), vec2<f32>(0.999));
        let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
        let l = luminance(c);
        let max_ch = max(c.r, max(c.g, c.b));
        let min_ch = min(c.r, min(c.g, c.b));
        let chroma = max_ch - min_ch;

        // Open sky and neutral white surfaces (snow, clouds, quartz in daylight) glow much less
        // than saturated light sources (torches, lava, glowing ores, golden sunset).
        let sky_weight = select(1.0, 0.15, depth_at(uv) == 0.0);
        let white_protect = mix(0.18, 1.0, smoothstep(0.06, 0.28, chroma));
        let signal = max(l * white_protect, max_ch * smoothstep(0.12, 0.35, chroma));
        let bright = c * smoothstep(0.76, 1.02, signal) * sky_weight;

        // Karis average prevents fireflies
        let w = 1.0 / (1.0 + luminance(bright));
        sum += bright * w;
        weight += w;
    }

    return vec4<f32>(sum / max(weight, 1e-4), 1.0);
}
