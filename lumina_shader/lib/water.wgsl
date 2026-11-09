// Natural Emerald-Blue Glassy Water (Complementary/BSL style):
// Smooth glassy wave normals, foreground-safe underwater refraction via opaque_color,
// emerald-blue depth absorption, soft shoreline transition, and sky/Aurora reflection.

override water_clarity: f32 = 0.75;
override water_specular: f32 = 0.7;
override aurora_strength: f32 = 0.85;

// Perturbs the water surface normal with smooth, glassy procedural ripples.
fn water_wave_normal(world_pos: vec3<f32>, base_normal: vec3<f32>) -> vec3<f32> {
    let t = frame.time;
    let p = world_pos.xz;

    let w1 = sin(p.x * 1.55 + p.y * 0.85 + t * 1.85) * 0.024;
    let w2 = cos(p.x * 0.75 - p.y * 1.65 + t * 1.45) * 0.020;
    let w3 = (noise2d(p * 1.15 + vec2<f32>(t * 0.55, -t * 0.40)) - 0.5) * 0.026;

    let dx = w1 + w3;
    let dz = w2 - w3;

    if abs(base_normal.y) > 0.5 {
        return normalize(vec3<f32>(dx, 1.0, dz));
    }
    return normalize(base_normal + vec3<f32>(dx * 0.4, 0.0, dz * 0.4));
}

fn shade_water(input: MaterialInput, shadow_vis: vec3<f32>) -> Surface {
    let world_pos = input.position + frame.camera_position;
    let wave_n = water_wave_normal(world_pos, input.normal);
    let view_dir = normalize(-input.position);
    let dist = length(input.position);

    let day = daylight();
    let tw = twilight();
    let night = night_factor();
    let night_scale = mix(0.68, 0.34, night_darkness);

    // Sample background depth & color behind the water surface for refraction
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
    if raw_diff < -0.05 || bg_depth <= 0.0 {
        let center_texel = vec2<i32>(clamp(input.screen * res, vec2<f32>(0.0), res - 1.0));
        bg_color = textureLoad(opaque_color, center_texel, 0).rgb;
        water_depth = 1.4;
    }

    // Natural Emerald-Blue Glassy palette with subtle vanilla water texture detail
    let tex_detail = clamp(luminance(input.albedo.rgb) * 1.15, 0.82, 1.16);
    let biome_tint = mix(vec3<f32>(0.07, 0.32, 0.40), input.tint.rgb * 0.78, 0.32);
    let shallow_col = biome_tint * mix(vec3<f32>(0.22, 0.34, 0.48) * night_scale, vec3<f32>(0.26, 0.62, 0.70), day) * tex_detail;
    let deep_col = vec3<f32>(0.02, 0.10, 0.17) * mix(night_scale, 0.88, day) * tex_detail;

    let absorption = exp(-water_depth * mix(0.32, 0.11, water_clarity));
    let water_body = mix(deep_col, shallow_col, absorption);

    // Blend refracted seabed with depth-based emerald-blue absorption
    let has_refr = luminance(bg_color) > 0.0005;
    let seabed_tint = mix(vec3<f32>(1.0), vec3<f32>(0.66, 0.88, 0.94), clamp(water_depth * 0.20, 0.15, 0.78));
    let refr_mix = clamp(absorption * water_clarity, 0.08, 0.88);
    let refracted = select(water_body, mix(water_body, bg_color * seabed_tint, refr_mix), has_refr);

    // Glassy Schlick Fresnel reflection (capped at 0.72 so water stays translucent and emerald-blue)
    let ndotv = max(dot(wave_n, view_dir), 0.0);
    let fresnel = clamp(0.02 + 0.70 * pow(1.0 - ndotv, 4.5), 0.0, 0.72);

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

    // Colored block & handheld torch light on water
    let blk_light = compute_block_and_hand_light(input, day) * 0.65;

    // Crisp sun & moon glittering specular highlight
    let half_vec = normalize(view_dir + frame.light_direction);
    let ndoth = max(dot(wave_n, half_vec), 0.0);
    let spec_tight = pow(ndoth, 160.0) * 1.85;
    let spec_wide = pow(ndoth, 32.0) * 0.24;
    let sun_glitter = (spec_tight + spec_wide) * direct_light_color(sun_warmth) * shadow_vis * water_specular * (1.0 - frame.rain * 0.85);

    var final_water = mix(refracted + blk_light, sky_refl, fresnel) + sun_glitter;

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

    let base_alpha = select(mix(0.72, 0.92, fresnel), mix(0.55, 0.90, max(fresnel, 1.0 - absorption * 0.55)), has_refr);
    return Surface(vec4<f32>(max(final_water, vec3<f32>(0.0)), base_alpha));
}
