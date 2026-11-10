// Material stage: combines terrain albedo, directional sunlight/moonlight with distortion-aware PCF
// shadows, rich Golden Hour ambient, balanced Moonlit & Aurora night visibility, cozy rain wetness,
// colored block & handheld torch lights, emissive blocks, glowing ores, and crystal water.

fn material(input: MaterialInput) -> Surface {
    let dist = length(input.position);

    // Distance-adaptive alpha cutoff: prevents distant foliage and cutout blocks (leaves, vines, ferns)
    // from disintegrating into noisy speckled holes due to mipmap texture averaging.
    let alpha_cutoff = clamp(0.50 - smoothstep(12.0, 72.0, dist) * 0.28, 0.22, 0.50);
    if !input.translucent && input.albedo.a < alpha_cutoff {
        return Surface(vec4<f32>(0.0));
    }

    let n = input.normal;
    let l = frame.light_direction;
    let facing = dot(n, l);

    // Water surfaces take the dedicated vanilla-specular water path
    if input.fluid == 1u {
        var water_sh = vec3<f32>(1.0);
        if frame.rain < 0.80 && dot(input.position, input.position) < 1296.0 {
            water_sh = sample_shadow_fast(input.position, vec3<f32>(0.0, 1.0, 0.0));
        }
        let world_p = input.position + frame.camera_position;
        let cloud_sh = sample_cloud_shadow(world_p, input.light.y);
        water_sh *= cloud_sh;
        return shade_water(input, water_sh);
    }

    // Lava glows cleanly by itself
    if input.fluid == 2u {
        let lava_col = input.albedo.rgb * input.tint.rgb * (1.12 + emissive_boost * 0.45);
        return Surface(vec4<f32>(lava_col, input.albedo.a));
    }

    let view_dir = input.position / max(dist, 1e-4);

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
    let night_scale = mix(0.76, 0.42, night_darkness);
    let fog_f = compute_fog_factor(dist, input.light.y, fog_strength);

    // Keep biome tint and ambient occlusion from input.tint, removing vanilla's static face shade
    let clean_tint = input.tint.rgb / vanilla_face_shade(n);
    let base_albedo = input.albedo.rgb * clean_tint;

    // Ambient sky light:
    // - Noon: calm cool sky shadow contrast
    // - Morning / Afternoon (Golden Hour): warm golden-amber & lavender-dusk bounce
    // - Night: synchronized with vanilla's entity lightmap so mobs never glow in the dark and terrain stays readable
    // - Rain: dark overcast slate-blue ambient
    let cool_shadow = mix(vec3<f32>(0.88, 0.92, 0.98), vec3<f32>(0.74, 0.86, 1.05), shadow_tint);
    let noon_sky_ambient = mix(frame.sky_color, cool_shadow, 0.52) * SKY_INTENSITY;
    let golden_ambient = mix(vec3<f32>(0.64, 0.50, 0.46), vec3<f32>(0.86, 0.56, 0.36), sun_warmth) * SKY_INTENSITY * 1.15;
    let day_sky_ambient = mix(noon_sky_ambient, golden_ambient, tw * 0.80);

    let night_sky_ambient = vec3<f32>(0.14, 0.21, 0.32) * night_scale;
    var sky_ambient_col = mix(night_sky_ambient, day_sky_ambient, day);

    let rain_ambient = mix(vec3<f32>(0.08, 0.13, 0.20) * night_scale, vec3<f32>(0.19, 0.24, 0.31), day);
    sky_ambient_col = mix(sky_ambient_col, rain_ambient, frame.rain * 0.88);

    let sky_facing = 0.82 + 0.18 * n.y;
    let cave_min = mix(0.024, 0.052, frame.brightness) * mix(1.15, 0.65, night_darkness);
    let sky_light_sq = input.light.y * input.light.y;
    // Synchronize outdoor night terrain baseline with vanilla's entity lightmap (`input.lightmap`)
    // so outdoor terrain and mobs share the exact same luminance without needing `set_surface`.
    let night_outdoor_lift = input.lightmap * (1.0 - day) * smoothstep(0.08, 0.80, input.light.y) * mix(0.84, 0.58, night_darkness);
    let sky_term = sky_ambient_col * sky_light_sq * sky_facing + night_outdoor_lift + vec3<f32>(cave_min);

    // Directional sun / moon lighting with PCF shadow map and foliage subsurface scattering
    // Early-out shadow PCF when heavily fogged (`fog_f > 0.82`) or in heavy overcast rain (`frame.rain > 0.82`)
    let rain_sun_atten = 1.0 - frame.rain * 0.88;
    let is_foliage = input.material == 10u || input.material == 11u;
    var ndl = max(facing, 0.0) * smoothstep(0.0, 0.18, facing);
    let to_eye = -view_dir;
    let through = pow(max(dot(to_eye, -l), 0.0), 4.0);
    var foliage_tint = vec3<f32>(1.0);
    if is_foliage {
        ndl = ndl * 0.85 + through * 0.42;
        foliage_tint = mix(vec3<f32>(1.0), vec3<f32>(0.88, 1.0, 0.56), through);
    }

    var direct_term = vec3<f32>(0.0);
    if ndl > 0.005 && input.light.y > 0.05 && rain_sun_atten > 0.02 && fog_f < 0.84 {
        var shadow_vis = vec3<f32>(1.0);
        if is_foliage {
            shadow_vis = sample_shadow_fast(input.position, n);
        } else {
            shadow_vis = sample_shadow(input.position, n, max(facing, 0.15));
        }
        let outdoor_mask = smoothstep(0.05, 0.45, input.light.y);
        let day_sun_power = SUN_INTENSITY * (1.0 + tw * 0.30 * sun_warmth) * rain_sun_atten;
        let direct_col = direct_light_color(sun_warmth) * foliage_tint * mix(0.36 * night_scale, day_sun_power, day);
        let world_p = input.position + frame.camera_position;
        let cloud_sh = sample_cloud_shadow(world_p, input.light.y);
        direct_term = direct_col * ndl * shadow_vis * outdoor_mask * cloud_sh;
    }

    // Colored block light & smooth per-pixel handheld/offhand torch light (skip if buried in thick far fog)
    var block_term = vec3<f32>(0.0);
    if fog_f < 0.88 {
        block_term = compute_block_and_hand_light(input, day);
    }

    var total_light = sky_term + direct_term + block_term;
    if frame.night_vision > 0.0 {
        total_light = max(total_light, vec3<f32>(0.65, 0.72, 0.68) * frame.night_vision);
    }

    var color = base_albedo * total_light;

    // Cozy Lo-Fi rain surface wetness (only within visible range before heavy fog)
    if dist < 56.0 && fog_f < 0.82 {
        color = apply_wetness(color, input);
    }

    // Emissive blocks (torches, lanterns, glowstone, froglights)
    let is_tagged_emissive = input.material == 30u;
    let em_level = max(input.emission, select(0.0, 0.95, is_tagged_emissive));
    if em_level > 0.01 {
        let em_color = input.albedo.rgb * input.tint.rgb * em_level * (1.05 + emissive_boost * 0.55);
        color = max(color, em_color);
    }

    // Glowing ore mineral veins in darkness (excludes coal; stone/deepslate stays unlit)
    if dist < 48.0 {
        color += compute_ore_glow(input);
    }

    // Time-of-day & rain atmospheric fog
    if fog_f > 0.0 {
        let fog_c = atmospheric_fog_color(view_dir, sun_warmth, night_darkness);
        color = mix(color, fog_c, fog_f);
    }

    return Surface(vec4<f32>(max(color, vec3<f32>(0.0)), input.albedo.a * input.tint.a));
}
