// Material stage: combines terrain albedo, directional sunlight with distortion-aware PCF shadows,
// cool sky shadows, colored block lights, emissive blocks, glowing ores, rain wetness,
// crystal water, and time-of-day atmospheric fog.

fn material(input: MaterialInput) -> Surface {
    // Early-out for transparent cutout texels (leaves, vines, grass, ferns, flowers) BEFORE
    // running shadow PCF or 3D block light lookups: Horizon's `horizon_material_solid` calls
    // `material()` before checking `if color.a < 0.5 { discard; }`.
    if !input.translucent && input.albedo.a < 0.5 {
        return Surface(vec4<f32>(0.0));
    }

    let n = input.normal;
    let l = frame.light_direction;
    let facing = dot(n, l);

    // Water surfaces take the dedicated crystal water path
    if input.fluid == 1u {
        let water_sh = sample_shadow_fast(input.position, vec3<f32>(0.0, 1.0, 0.0));
        return shade_water(input, water_sh);
    }

    // Lava glows cleanly by itself
    if input.fluid == 2u {
        let lava_col = input.albedo.rgb * input.tint.rgb * (1.12 + emissive_boost * 0.45);
        return Surface(vec4<f32>(lava_col, input.albedo.a));
    }

    let dist = length(input.position);
    let view_dir = normalize(input.position);

    if frame.dimension != 0 {
        let base_albedo = input.albedo.rgb * input.tint.rgb;
        let blk = compute_block_and_hand_light(input, 0.0);
        let dim_lit = base_albedo * (input.lightmap * 0.75 + blk * 0.75);

        let em_strength = max(input.emission, select(0.0, 0.9, input.material == 30u));
        let em_glow = base_albedo * em_strength * (1.1 + emissive_boost * 0.5);
        let ore = compute_ore_glow(input);

        var dim_color = max(dim_lit, em_glow) + ore;
        let fog_f = compute_fog_factor(dist, input.light.y, fog_strength);
        dim_color = mix(dim_color, frame.fog_color, fog_f);
        return Surface(vec4<f32>(dim_color, input.albedo.a * input.tint.a));
    }

    let day = daylight();
    let tw = twilight();
    let night_scale = mix(0.38, 0.055, night_darkness);

    // Keep biome tint and ambient occlusion from input.tint, removing vanilla's static face shade
    let clean_tint = input.tint.rgb / vanilla_face_shade(n);
    let base_albedo = input.albedo.rgb * clean_tint;

    // Ambient sky light with Cool Shadow Tint contrast
    let cool_shadow = mix(vec3<f32>(0.88, 0.92, 0.98), vec3<f32>(0.74, 0.86, 1.05), shadow_tint);
    let day_sky_ambient = mix(frame.sky_color, cool_shadow, 0.55) * SKY_INTENSITY;
    let night_sky_ambient = vec3<f32>(0.05, 0.08, 0.15) * night_scale;
    var sky_ambient_col = mix(night_sky_ambient, day_sky_ambient, day);
    sky_ambient_col = mix(sky_ambient_col, vec3<f32>(luminance(sky_ambient_col)), frame.rain * 0.55);

    let sky_facing = 0.82 + 0.18 * n.y;
    let cave_min = mix(0.015, 0.042, frame.brightness) * mix(1.2, 0.45, night_darkness);
    let sky_light_sq = input.light.y * input.light.y;
    let sky_term = sky_ambient_col * sky_light_sq * sky_facing + vec3<f32>(cave_min);

    // Directional sun / moon lighting with PCF shadow map and foliage subsurface scattering
    let is_foliage = input.material == 10u || input.material == 11u;
    var ndl = max(facing, 0.0) * smoothstep(0.0, 0.18, facing);
    let to_eye = -view_dir;
    let through = pow(max(dot(to_eye, -l), 0.0), 4.0);
    var foliage_tint = vec3<f32>(1.0);
    if is_foliage {
        ndl = ndl * 0.85 + through * 0.42;
        foliage_tint = mix(vec3<f32>(1.0), vec3<f32>(0.86, 1.0, 0.58), through);
    }

    var direct_term = vec3<f32>(0.0);
    if ndl > 0.005 && input.light.y > 0.05 {
        var shadow_vis = vec3<f32>(1.0);
        if is_foliage {
            shadow_vis = sample_shadow_fast(input.position, n);
        } else {
            shadow_vis = sample_shadow(input.position, n, max(facing, 0.15));
        }
        let outdoor_mask = smoothstep(0.05, 0.45, input.light.y);
        let direct_col = direct_light_color(sun_warmth) * foliage_tint * mix(0.20 * night_scale, SUN_INTENSITY, day);
        direct_term = direct_col * ndl * shadow_vis * outdoor_mask;
    }

    // Colored block light & smooth per-pixel handheld/offhand torch light
    let block_term = compute_block_and_hand_light(input, day);

    var total_light = sky_term + direct_term + block_term;
    if frame.night_vision > 0.0 {
        total_light = max(total_light, vec3<f32>(0.65, 0.72, 0.68) * frame.night_vision);
    }

    var color = base_albedo * total_light;

    // Rain surface wetness
    color = apply_wetness(color, input);

    // Emissive blocks (torches, lanterns, glowstone, froglights)
    let is_tagged_emissive = input.material == 30u;
    let em_level = max(input.emission, select(0.0, 0.95, is_tagged_emissive));
    if em_level > 0.01 {
        let em_color = input.albedo.rgb * input.tint.rgb * em_level * (1.05 + emissive_boost * 0.55);
        color = max(color, em_color);
    }

    // Glowing ore mineral veins in darkness (excludes coal; stone/deepslate stays unlit)
    color += compute_ore_glow(input);

    // Time-of-day atmospheric fog (morning, sunset, rain; subtle at night; zero at noon and inside caves)
    let fog_f = compute_fog_factor(dist, input.light.y, fog_strength);
    if fog_f > 0.0 {
        let fog_c = atmospheric_fog_color(view_dir, sun_warmth, night_darkness);
        color = mix(color, fog_c, fog_f);
    }

    return Surface(vec4<f32>(max(color, vec3<f32>(0.0)), input.albedo.a * input.tint.a));
}
