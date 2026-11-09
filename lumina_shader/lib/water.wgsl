// Natural Emerald-Blue Realistic Water:
// - Multi-octave directional swell and capillary ripple waves with distance LOD fade
// - Dynamic underwater caustics dancing on shallow seabed in sunlight
// - Selective Beer-Lambert depth absorption (crystal aqua shallows to deep navy ocean)
// - Distance early-out (> 64 blocks) skipping depth/color loads to preserve iGPU memory bandwidth
// - Shoreline foam and soft edge transitions at contact points with land
// - Dual-lobe specular glitter (sun and moon) plus sky and Aurora Borealis reflections.

override water_clarity: f32 = 0.75;
override water_specular: f32 = 0.7;
override aurora_strength: f32 = 0.85;

// Perturbs the water surface normal with smooth, multi-octave directional waves and distance LOD fade.
fn water_wave_normal(world_pos: vec3<f32>, base_normal: vec3<f32>, dist: f32) -> vec3<f32> {
    let t = frame.time;
    let p = world_pos.xz;

    // Harmonic 1: primary swell traveling diagonally
    let d1 = vec2<f32>(0.819, 0.574);
    let phase1 = dot(p, d1) * 0.95 + t * 1.45;
    let c1 = cos(phase1);

    // Harmonic 2: secondary cross-cutting swell
    let d2 = vec2<f32>(-0.60, 0.80);
    let phase2 = dot(p, d2) * 1.55 - t * 1.65;
    let c2 = cos(phase2);

    // Harmonic 3: close-range capillary ripples (only within 36 blocks)
    let close_factor = clamp(1.0 - dist * 0.028, 0.0, 1.0);
    var d3 = vec2<f32>(0.0);
    if close_factor > 0.01 {
        let p3 = p * 2.8 + vec2<f32>(t * 0.75, -t * 0.55);
        let n1 = noise2d(p3) - 0.5;
        let n2 = noise2d(p3 * 1.5 + vec2<f32>(-t * 0.4, t * 0.6)) - 0.5;
        d3 = vec2<f32>(n1, n2) * (0.024 * close_factor);
    }

    let deriv = d1 * (c1 * 0.024) + d2 * (c2 * 0.018) + d3;

    // Fade out steep micro-ripples in the distance to eliminate shimmer and moire
    let dist_fade = 1.0 / (1.0 + dist * 0.032);
    let dx = deriv.x * dist_fade;
    let dz = deriv.y * dist_fade;

    if abs(base_normal.y) > 0.5 {
        return normalize(vec3<f32>(-dx, 1.0, -dz));
    }
    return normalize(base_normal + vec3<f32>(-dx * 0.4, 0.0, -dz * 0.4));
}

// Procedural underwater dynamic caustics pattern projected onto shallow seabed.
fn water_caustics(seabed_pos: vec2<f32>, water_depth: f32, day: f32, tw: f32, shadow_vis: f32) -> vec3<f32> {
    if water_depth > 10.0 || day <= 0.02 || shadow_vis <= 0.02 || frame.rain > 0.75 {
        return vec3<f32>(0.0);
    }
    let t = frame.time * 1.6;
    let p = seabed_pos * 1.35;

    // Dual-wave interference pattern
    let c1 = sin(p.x * 1.5 + p.y * 1.1 + t) + sin(p.x * 1.1 - p.y * 1.4 - t * 0.85);
    let c2 = sin(p.x * 2.0 - p.y * 0.8 + t * 1.15) + sin(-p.x * 1.0 + p.y * 2.2 + t * 0.95);
    var caustic = max(0.0, (c1 + c2) * 0.35 + 0.30);
    caustic = caustic * caustic;

    // Caustics are strongest at 0.4 to 3.0 blocks depth and attenuate in deep water
    let depth_fade = clamp(water_depth * 2.5, 0.0, 1.0) * exp(-water_depth * 0.38);
    let clear_weather = 1.0 - frame.rain * 0.88;

    let caustic_color = mix(vec3<f32>(0.85, 1.05, 1.00), vec3<f32>(1.18, 0.94, 0.65), tw * 0.65);
    return caustic_color * (caustic * depth_fade * day * shadow_vis * clear_weather * 0.48);
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

    // Precalculate sky reflection colors (shared between near and far water)
    let refl_dir = reflect(-view_dir, wave_n);
    let refl_up = clamp(refl_dir.y, 0.0, 1.0);
    let sky_zenith = mix(vec3<f32>(0.04, 0.08, 0.16) * night_scale, mix(vec3<f32>(0.22, 0.44, 0.78), vec3<f32>(0.20, 0.22, 0.44), tw * 0.75), day);
    let sky_horiz = mix(
        vec3<f32>(0.08, 0.15, 0.26) * night_scale,
        mix(vec3<f32>(0.58, 0.72, 0.86), vec3<f32>(1.02, 0.48, 0.20), tw),
        day
    );
    let clear_refl = mix(sky_horiz, sky_zenith, pow(refl_up, 0.6)) + aurora_borealis(vec3<f32>(refl_dir.x, max(refl_dir.y, 0.12), refl_dir.z), night, aurora_strength) * 0.68;
    let rain_refl = mix(vec3<f32>(0.05, 0.08, 0.13) * night_scale, vec3<f32>(0.15, 0.20, 0.27), day);
    let sky_refl = mix(clear_refl, rain_refl, frame.rain * 0.94);

    let ndotv = max(dot(wave_n, view_dir), 0.0);
    let fresnel = clamp(0.02 + 0.72 * pow(1.0 - ndotv, 4.5), 0.0, 0.78);

    // Crisp dual-lobe sun and moon specular highlight
    let half_vec = normalize(view_dir + frame.light_direction);
    let ndoth = max(dot(wave_n, half_vec), 0.0);
    let spec_tight = pow(ndoth, 180.0) * 2.10;
    let spec_wide = pow(ndoth, 28.0) * 0.28;
    let sun_glitter = (spec_tight + spec_wide) * direct_light_color(sun_warmth) * shadow_vis * water_specular * (1.0 - frame.rain * 0.85);

    // PERFORMANCE OPTIMIZATION: Water beyond 64 blocks smoothly fades to deep water body,
    // sky reflection, and atmospheric fog, completely skipping textureLoad(opaque_depth),
    // textureLoad(opaque_color) and matrix inverse math.
    if dist > 64.0 {
        let far_body = vec3<f32>(0.02, 0.10, 0.17) * mix(night_scale, 0.88, day);
        var far_col = mix(far_body, sky_refl, fresnel) + sun_glitter;
        let fog_f = compute_fog_factor(dist, input.light.y, fog_strength);
        if fog_f > 0.0 {
            let fog_c = atmospheric_fog_color(-view_dir, sun_warmth, night_darkness);
            far_col = mix(far_col, fog_c, fog_f);
        }
        return Surface(vec4<f32>(max(far_col, vec3<f32>(0.0)), mix(0.72, 0.92, fresnel)));
    }

    // Near water: sample background depth & color behind the water surface for realistic refraction
    let res = frame.resolution;
    let wave_offset = wave_n.xz * (1.8 / max(dist, 1.5));
    let refr_uv = clamp(input.screen + wave_offset * vec2<f32>(0.009, 0.014), vec2<f32>(0.001), vec2<f32>(0.999));
    let texel = vec2<i32>(clamp(refr_uv * res, vec2<f32>(0.0), res - 1.0));

    let bg_depth = textureLoad(opaque_depth, texel, 0);
    var bg_color = textureLoad(opaque_color, texel, 0).rgb;

    // Reconstruct background distance and reject foreground dry-land objects hit by wave offset
    let clip = vec4<f32>(refr_uv.x * 2.0 - 1.0, 1.0 - refr_uv.y * 2.0, bg_depth, 1.0);
    let view_bg = frame.projection_inverse * clip;
    let bg_pos = (frame.view_inverse * vec4<f32>(view_bg.xyz / max(view_bg.w, 1e-5), 0.0)).xyz;
    let raw_diff = length(bg_pos) - dist;

    var water_depth = clamp(raw_diff, 0.0, 32.0);
    var seabed_world = world_pos.xz;
    if raw_diff < -0.05 || bg_depth <= 0.0 {
        let center_texel = vec2<i32>(clamp(input.screen * res, vec2<f32>(0.0), res - 1.0));
        bg_color = textureLoad(opaque_color, center_texel, 0).rgb;
        water_depth = 1.4;
    } else {
        seabed_world = (bg_pos + frame.camera_position).xz;
    }

    // Dynamic underwater caustics dancing on the shallow seabed
    let caustics = water_caustics(seabed_world, water_depth, day, tw, shadow_vis.r);
    bg_color += bg_color * caustics;

    // Physical Beer-Lambert wavelength-selective absorption
    // Red light is absorbed rapidly (0.28), green moderately (0.10), blue persists deepest (0.04)
    let ext_coef = mix(vec3<f32>(0.34, 0.12, 0.05), vec3<f32>(0.18, 0.06, 0.02), water_clarity);
    let absorption = exp(-water_depth * ext_coef);

    // Natural Emerald-Blue palette with subtle vanilla water texture detail
    let tex_detail = clamp(luminance(input.albedo.rgb) * 1.15, 0.82, 1.16);
    let biome_tint = mix(vec3<f32>(0.07, 0.34, 0.42), input.tint.rgb * 0.78, 0.32);
    let shallow_col = biome_tint * mix(vec3<f32>(0.22, 0.34, 0.48) * night_scale, vec3<f32>(0.26, 0.64, 0.72), day) * tex_detail;
    let deep_col = vec3<f32>(0.02, 0.09, 0.18) * mix(night_scale, 0.88, day) * tex_detail;

    let water_body = mix(deep_col, shallow_col, clamp(absorption.g, 0.0, 1.0));

    // Blend refracted seabed with depth absorption
    let has_refr = luminance(bg_color) > 0.0005;
    let seabed_tint = mix(vec3<f32>(1.0), vec3<f32>(0.72, 0.90, 0.96), clamp(water_depth * 0.18, 0.12, 0.75));
    let refr_mix = clamp(absorption * water_clarity, vec3<f32>(0.06), vec3<f32>(0.90));
    let refracted = select(water_body, mix(water_body, bg_color * seabed_tint, refr_mix), has_refr);

    // Colored block & handheld torch light on water
    let blk_light = compute_block_and_hand_light(input, day) * 0.65;

    var final_water = mix(refracted + blk_light, sky_refl, fresnel) + sun_glitter;

    // Shoreline foam: soft white surf rippling along contact lines with terrain
    if has_refr && water_depth < 0.28 {
        let shore_factor = 1.0 - water_depth / 0.28;
        let foam_noise = noise2d(world_pos.xz * 3.6 + vec2<f32>(frame.time * 0.45, -frame.time * 0.35));
        let wave_pulse = sin(frame.time * 2.2 - water_depth * 16.0) * 0.5 + 0.5;
        let foam = smoothstep(0.42, 0.88, shore_factor * 0.75 + wave_pulse * 0.25 + foam_noise * 0.20);
        let foam_col = mix(vec3<f32>(0.85, 0.92, 0.96), vec3<f32>(1.05, 0.92, 0.75), tw * 0.5);
        final_water = mix(final_water, foam_col * (0.65 + 0.35 * day), foam * 0.68);
    }

    // Soft shoreline blend so shallow water edges transition smoothly into wet sand/stone
    if has_refr && water_depth < 0.35 {
        let shore_fade = smoothstep(0.0, 0.35, water_depth);
        final_water = mix(bg_color * 0.92, final_water, 0.35 + 0.65 * shore_fade);
    }

    // Apply atmospheric fog to water surface
    let fog_f = compute_fog_factor(dist, input.light.y, fog_strength);
    if fog_f > 0.0 {
        let fog_c = atmospheric_fog_color(-view_dir, sun_warmth, night_darkness);
        final_water = mix(final_water, fog_c, fog_f);
    }

    let base_alpha = select(mix(0.72, 0.92, fresnel), mix(0.55, 0.90, max(fresnel, 1.0 - absorption.g * 0.55)), has_refr);
    return Surface(vec4<f32>(max(final_water, vec3<f32>(0.0)), base_alpha));
}
