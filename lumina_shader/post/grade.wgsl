// Post Pass 4 (Full Resolution Composite):
// Combines quarter-res volumetric godrays (`rays`) and soft bloom (`bloom_b`) with
// Warm Cinematic split-toning and ACES Filmic tone mapping (no vignette).

override bloom_strength: f32 = 0.35;
override sun_warmth: f32 = 0.65;
override shadow_tint: f32 = 0.45;
override exposure: f32 = 1.0;
override contrast: f32 = 1.06;
override saturation: f32 = 1.10;

fn sample_rays_smooth(uv: vec2<f32>) -> vec3<f32> {
    let texel = 1.25 / vec2<f32>(textureDimensions(rays));
    let c = textureSampleLevel(rays, linear_sampler, uv, 0.0).rgb * 0.36;
    let a = textureSampleLevel(rays, linear_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb * 0.16;
    let b = textureSampleLevel(rays, linear_sampler, uv + vec2<f32>(texel.x, -texel.y), 0.0).rgb * 0.16;
    let d = textureSampleLevel(rays, linear_sampler, uv + vec2<f32>(-texel.x, texel.y), 0.0).rgb * 0.16;
    let e = textureSampleLevel(rays, linear_sampler, uv + vec2<f32>(texel.x, texel.y), 0.0).rgb * 0.16;
    return c + a + b + d + e;
}

fn post(input: PostInput) -> vec4<f32> {
    var c = input.color.rgb;

    // Add quarter-res bloom and smoothed volumetric godrays (softened over already-bright surfaces)
    if bloom_strength > 0.001 {
        c += textureSampleLevel(bloom_b, linear_sampler, input.uv, 0.0).rgb * bloom_strength;
    }
    let ray_col = sample_rays_smooth(input.uv);
    c += ray_col * (vec3<f32>(1.0) - min(c, vec3<f32>(1.0)) * 0.45);

    c *= exposure;

    // Warm Cinematic split-toning: golden highlights during day/sunset, cool shadows
    let day = daylight();
    let tw = twilight();
    let golden_factor = sun_warmth * mix(0.22, 0.85, tw) * day * (1.0 - frame.rain * 0.75);
    let highlight_warmth = mix(vec3<f32>(1.0), vec3<f32>(1.06, 0.99, 0.89), golden_factor);

    let luma_pre = luminance(c);
    let shadow_weight = (1.0 - smoothstep(0.0, 0.42, luma_pre)) * shadow_tint * 0.18;
    let cool_lift = vec3<f32>(0.93, 0.98, 1.06);

    c *= mix(vec3<f32>(1.0), cool_lift, shadow_weight);
    c *= mix(vec3<f32>(1.0), highlight_warmth, smoothstep(0.25, 0.85, luma_pre));

    // ACES filmic tone curve
    c = aces_tonemap(c * 0.86) * 1.05;

    // Midtone contrast around pivot 0.45
    c = clamp((c - 0.45) * contrast + 0.45, vec3<f32>(0.0), vec3<f32>(1.0));

    // Final saturation adjustment
    let luma_post = luminance(c);
    c = mix(vec3<f32>(luma_post), c, saturation);

    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
