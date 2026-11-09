// Post Pass 4 (Full Resolution Composite):
// Combines quarter-res volumetric godrays (`rays`) and soft bloom (`bloom_b`) with
// rich Golden Hour split-toning, night mob brightness synchronization via `surface_at`,
// cozy rain lo-fi balance, and ACES Filmic tone mapping (no vignette, no black crush).

override bloom_strength: f32 = 0.35;
override sun_warmth: f32 = 0.65;
override shadow_tint: f32 = 0.45;
override night_darkness: f32 = 0.75;
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
    let day = daylight();
    let tw = twilight();
    let night = night_factor();

    // Synchronize entity/mob brightness at night: Horizon renders entities with vanilla's unshaded
    // night lightmap, whereas solid terrain writes `scene_surface` (`surface_at(texel).present`).
    if night > 0.01 && input.depth > 0.0001 {
        let surf = surface_at(vec2<i32>(input.uv * frame.resolution));
        if !surf.present {
            let luma_ent = luminance(c);
            let non_emissive = 1.0 - smoothstep(0.38, 0.78, luma_ent);
            let mob_scale = mix(1.0, mix(0.68, 0.44, night_darkness), night * non_emissive);
            let mob_night_tint = mix(vec3<f32>(1.0), vec3<f32>(0.82, 0.90, 1.04), night * non_emissive * 0.55);
            c *= mob_scale * mob_night_tint;
        }
    }

    // Add quarter-res bloom and smoothed volumetric godrays
    if bloom_strength > 0.001 {
        c += textureSampleLevel(bloom_b, linear_sampler, input.uv, 0.0).rgb * bloom_strength;
    }
    let ray_col = sample_rays_smooth(input.uv);
    c += ray_col * (vec3<f32>(1.0) - min(c, vec3<f32>(1.0)) * 0.48);

    // Calmer daytime exposure (~16% softer glare at noon) while keeping night and caves readable
    let day_balance = mix(1.0, 0.85, day * (1.0 - tw * 0.30));
    c *= exposure * day_balance;

    // Rich Golden Hour & Cool Shadow split-toning
    let golden_factor = sun_warmth * mix(0.24, 0.96, tw) * day * (1.0 - frame.rain * 0.72);
    let highlight_warmth = mix(vec3<f32>(1.0), vec3<f32>(1.14, 0.96, 0.78), golden_factor);

    let luma_pre = luminance(c);
    let shadow_weight = (1.0 - smoothstep(0.0, 0.46, luma_pre)) * shadow_tint * 0.22;
    let dusk_shadow = mix(vec3<f32>(0.92, 0.97, 1.06), vec3<f32>(0.98, 0.91, 1.05), tw);

    c *= mix(vec3<f32>(1.0), dusk_shadow, shadow_weight);
    c *= mix(vec3<f32>(1.0), highlight_warmth, smoothstep(0.20, 0.80, luma_pre));

    // ACES filmic tone curve (without post-multiplier clipping)
    c = aces_tonemap(c * 0.86);

    // Toe-preserving smooth contrast (never crushes dark night terrain to 0.0; softer during cozy rain)
    let active_contrast = mix(contrast, 1.01, frame.rain * 0.65);
    let curved = pow(max(c, vec3<f32>(1e-5)), vec3<f32>(active_contrast));
    c = mix(c, curved, 0.78);

    // Final saturation adjustment (slightly calmer saturation in heavy rain for a cozy lo-fi feel)
    let active_sat = mix(saturation, saturation * 0.95, frame.rain * 0.5);
    let luma_post = luminance(c);
    c = mix(vec3<f32>(luma_post), c, active_sat);

    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
