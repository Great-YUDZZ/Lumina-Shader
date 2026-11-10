// Pure Vanilla Water with Sun/Moon Specular Reflections and Gentle Micro-Ripples
// - Vanilla water texture (input.albedo) and biome water tint (input.tint)
// - Dual-lobe specular reflections (sun by day, moon by night) glistening on water
// - Subtle Fresnel sky reflection and Aurora Borealis reflection
// - Zero heavy depth/color loads or matrix inversions, ensuring 60+ FPS on Radeon 660M/680M.

override water_clarity: f32 = 0.75;
override water_specular: f32 = 0.75;
override aurora_strength: f32 = 0.85;

// Gentle micro-ripple normal perturbation for realistic sun/moon glistening
fn water_wave_normal(world_pos: vec3<f32>, base_normal: vec3<f32>, dist: f32) -> vec3<f32> {
    let wave_fade = 1.0 - smoothstep(16.0, 48.0, dist);
    if wave_fade <= 0.001 {
        return base_normal;
    }

    let t = frame.time;
    let p = world_pos.xz;

    // Harmonic 1 & 2: gentle diagonal swells
    let d1 = vec2<f32>(0.819, 0.574);
    let phase1 = dot(p, d1) * 1.1 + t * 1.5;
    let c1 = cos(phase1);

    let d2 = vec2<f32>(-0.60, 0.80);
    let phase2 = dot(p, d2) * 1.6 - t * 1.7;
    let c2 = cos(phase2);

    let deriv = (d1 * c1 * 0.022 + d2 * c2 * 0.016) * wave_fade;
    if abs(base_normal.y) > 0.5 {
        return normalize(vec3<f32>(-deriv.x, 1.0, -deriv.y));
    }
    return normalize(base_normal + vec3<f32>(-deriv.x * 0.3, 0.0, -deriv.y * 0.3));
}

fn shade_water(input: MaterialInput, shadow_vis: vec3<f32>) -> Surface {
    let world_pos = input.position + frame.camera_position;
    let dist = length(input.position);
    let wave_n = water_wave_normal(world_pos, input.normal, dist);
    let view_dir = normalize(-input.position);

    let day = daylight();
    let tw = twilight();
    let night = night_factor();
    let night_scale = mix(0.68, 0.34, night_darkness);

    // Vanilla water base color with biome water tint and animated texture
    let vanilla_base = input.albedo.rgb * input.tint.rgb;

    // Standard terrain lighting on water
    let blk_light = compute_block_and_hand_light(input, day);
    let ambient_sky = input.light.y * mix(vec3<f32>(0.04, 0.07, 0.14) * night_scale, vec3<f32>(0.55, 0.68, 0.82), day);
    let direct_col = direct_light_color(sun_warmth) * max(dot(wave_n, frame.light_direction), 0.0) * shadow_vis;
    var lit_water = vanilla_base * (ambient_sky + direct_col * 0.85) + blk_light;

    // Sky reflection (subtle Fresnel)
    let refl_dir = reflect(-view_dir, wave_n);
    let refl_up = clamp(refl_dir.y, 0.0, 1.0);
    let sky_zenith = mix(vec3<f32>(0.04, 0.08, 0.16) * night_scale, mix(vec3<f32>(0.22, 0.44, 0.78), vec3<f32>(0.20, 0.22, 0.44), tw * 0.75), day);
    let sky_horiz = mix(
        vec3<f32>(0.08, 0.15, 0.26) * night_scale,
        mix(vec3<f32>(0.58, 0.72, 0.86), vec3<f32>(1.02, 0.48, 0.20), tw),
        day
    );
    let clear_refl = mix(sky_horiz, sky_zenith, pow(refl_up, 0.6)) + aurora_borealis(vec3<f32>(refl_dir.x, max(refl_dir.y, 0.12), refl_dir.z), night, aurora_strength) * 0.55;
    let rain_refl = mix(vec3<f32>(0.05, 0.08, 0.13) * night_scale, vec3<f32>(0.15, 0.20, 0.27), day);
    let sky_refl = mix(clear_refl, rain_refl, frame.rain * 0.94);

    let ndotv = max(dot(wave_n, view_dir), 0.0);
    let fresnel = clamp(0.04 + 0.65 * pow(1.0 - ndotv, 5.0), 0.0, 0.75);

    // Smooth distance-adaptive sun and moon specular highlight:
    // Tight glittering lobe near player, fading into a wide calm sheen at distance (>24 blocks)
    // to prevent specular aliasing and stair-step banding.
    let half_vec = normalize(view_dir + frame.light_direction);
    let ndoth = max(dot(wave_n, half_vec), 0.0);
    let tight_fade = 1.0 - smoothstep(20.0, 48.0, dist);
    let spec_tight = pow(ndoth, 140.0) * 1.80 * tight_fade;
    let spec_wide = pow(ndoth, 18.0) * 0.28;
    let sun_glitter = (spec_tight + spec_wide) * direct_light_color(sun_warmth) * shadow_vis * water_specular * (1.0 - frame.rain * 0.85);

    // Combine vanilla water with subtle sky reflection and sun/moon sparkle
    var final_water = mix(lit_water, sky_refl, fresnel * 0.42) + sun_glitter;

    // Atmospheric fog
    let fog_f = compute_fog_factor(dist, input.light.y, fog_strength);
    if fog_f > 0.0 {
        let fog_c = atmospheric_fog_color(-view_dir, sun_warmth, night_darkness);
        final_water = mix(final_water, fog_c, fog_f);
    }

    // Vanilla water alpha transparency (~0.70 to 0.90 with Fresnel and clarity)
    let clarity_mult = mix(1.20, 0.80, clamp(water_clarity, 0.0, 1.0));
    let alpha = clamp(input.albedo.a * mix(0.92, 1.15, fresnel) * clarity_mult, 0.45, 0.95);
    return Surface(vec4<f32>(max(final_water, vec3<f32>(0.0)), alpha));
}
