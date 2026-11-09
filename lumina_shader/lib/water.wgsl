// Crystal clear water shading: wave normals, underwater refraction via opaque_color,
// depth absorption, Schlick Fresnel sky & Aurora Borealis reflection, and glittering sun specular.

override water_clarity: f32 = 0.75;
override water_specular: f32 = 0.7;
override aurora_strength: f32 = 0.85;

// Perturbs the water surface normal with multi-layered procedural waves.
fn water_wave_normal(world_pos: vec3<f32>, base_normal: vec3<f32>) -> vec3<f32> {
    let t = frame.time;
    let p = world_pos.xz;

    let w1 = sin(p.x * 1.7 + p.y * 0.9 + t * 2.1) * 0.035;
    let w2 = cos(p.x * 0.8 - p.y * 1.9 + t * 1.6) * 0.030;
    let w3 = (noise2d(p * 1.35 + vec2<f32>(t * 0.65, -t * 0.45)) - 0.5) * 0.045;

    let dx = w1 + w3;
    let dz = w2 - w3;

    if abs(base_normal.y) > 0.5 {
        return normalize(vec3<f32>(dx, 1.0, dz));
    }
    return normalize(base_normal + vec3<f32>(dx * 0.5, 0.0, dz * 0.5));
}

fn shade_water(input: MaterialInput, shadow_vis: vec3<f32>) -> Surface {
    let world_pos = input.position + frame.camera_position;
    let wave_n = water_wave_normal(world_pos, input.normal);
    let view_dir = normalize(-input.position);
    let dist = length(input.position);

    let day = daylight();
    let tw = twilight();
    let night = night_factor();
    let night_scale = mix(0.58, 0.24, night_darkness);

    // Sample background depth & color behind the water surface for crystal refraction
    let res = frame.resolution;
    let wave_offset = wave_n.xz * (2.5 / max(dist, 1.5));
    let refr_uv = clamp(input.screen + wave_offset * vec2<f32>(0.012, 0.018), vec2<f32>(0.001), vec2<f32>(0.999));
    let texel = vec2<i32>(clamp(refr_uv * res, vec2<f32>(0.0), res - 1.0));

    let bg_depth = textureLoad(opaque_depth, texel, 0);
    let bg_color = textureLoad(opaque_color, texel, 0).rgb;

    // Approximate water column thickness from view ray and reversed depth
    let clip = vec4<f32>(input.screen.x * 2.0 - 1.0, 1.0 - input.screen.y * 2.0, bg_depth, 1.0);
    let view_bg = frame.projection_inverse * clip;
    let bg_pos = (frame.view_inverse * vec4<f32>(view_bg.xyz / max(view_bg.w, 1e-5), 0.0)).xyz;
    let water_depth = clamp(length(bg_pos) - dist, 0.0, 32.0);

    // Deep vs shallow turquoise-emerald water palette
    let biome_tint = mix(vec3<f32>(0.12, 0.56, 0.66), input.tint.rgb * 1.10, 0.45);
    let shallow_col = biome_tint * mix(vec3<f32>(0.20, 0.30, 0.42) * night_scale, vec3<f32>(0.36, 0.72, 0.76), day);
    let deep_col = vec3<f32>(0.03, 0.16, 0.26) * mix(night_scale, 0.88, day);

    let absorption = exp(-water_depth * mix(0.28, 0.09, water_clarity));
    let water_body = mix(deep_col, shallow_col, absorption);

    // Blend refracted floor with water absorption
    let has_refr = luminance(bg_color) > 0.0005;
    let refracted = select(water_body, mix(water_body, bg_color * mix(vec3<f32>(1.0), vec3<f32>(0.72, 0.94, 0.98), 0.5), absorption * water_clarity), has_refr);

    // Sky & Aurora reflection using Schlick Fresnel
    let ndotv = max(dot(wave_n, view_dir), 0.0);
    let fresnel = clamp(0.03 + 0.92 * pow(1.0 - ndotv, 4.2), 0.0, 0.92);

    let refl_dir = reflect(-view_dir, wave_n);
    let refl_up = clamp(refl_dir.y, 0.0, 1.0);
    let sky_zenith = mix(vec3<f32>(0.04, 0.08, 0.16) * night_scale, mix(vec3<f32>(0.22, 0.44, 0.78), vec3<f32>(0.20, 0.22, 0.44), tw * 0.75), day);
    let sky_horiz = mix(
        vec3<f32>(0.08, 0.15, 0.26) * night_scale,
        mix(vec3<f32>(0.62, 0.74, 0.88), vec3<f32>(1.12, 0.52, 0.20), tw),
        day
    );
    let clear_refl = mix(sky_horiz, sky_zenith, pow(refl_up, 0.6)) + aurora_borealis(vec3<f32>(refl_dir.x, max(refl_dir.y, 0.12), refl_dir.z), night, aurora_strength) * 0.68;
    let rain_refl = mix(vec3<f32>(0.08, 0.13, 0.20) * night_scale, vec3<f32>(0.34, 0.42, 0.52), day);
    let sky_refl = mix(clear_refl, rain_refl, frame.rain * 0.82);

    // Colored block & handheld torch light on water
    let blk_light = compute_block_and_hand_light(input, day) * 0.68;

    // Sun & moon glittering specular highlight
    let half_vec = normalize(view_dir + frame.light_direction);
    let ndoth = max(dot(wave_n, half_vec), 0.0);
    let spec_tight = pow(ndoth, 140.0) * 1.95;
    let spec_wide = pow(ndoth, 28.0) * 0.30;
    let sun_glitter = (spec_tight + spec_wide) * direct_light_color(sun_warmth) * shadow_vis * water_specular * (1.0 - frame.rain * 0.85);

    var final_water = mix(refracted + blk_light, sky_refl, fresnel) + sun_glitter;

    // Apply atmospheric fog to water surface
    let fog_f = compute_fog_factor(dist, input.light.y, fog_strength);
    if fog_f > 0.0 {
        let fog_c = atmospheric_fog_color(-view_dir, sun_warmth, night_darkness);
        final_water = mix(final_water, fog_c, fog_f);
    }

    let base_alpha = select(mix(0.68, 0.92, fresnel), mix(0.42, 0.86, max(fresnel, 1.0 - absorption * 0.65)), has_refr);
    return Surface(vec4<f32>(max(final_water, vec3<f32>(0.0)), base_alpha));
}
