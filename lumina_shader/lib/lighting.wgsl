// Terrain lighting, distortion-aware PCF shadows, colored block light, ore glow in darkness,
// and rain surface wetness.

override shadows: bool = true;
override sun_warmth: f32 = 0.65;
override shadow_tint: f32 = 0.45;
override block_light_strength: f32 = 1.15;
override handlight_strength: f32 = 1.25;
override night_darkness: f32 = 0.75;
override ore_glow: f32 = 0.85;
override emissive_boost: f32 = 0.6;
override wetness_enabled: bool = true;

// Balanced noon intensities so white snow stays clean under 1.0 without clipping or blooming.
const SUN_INTENSITY: f32 = 0.58;
const SKY_INTENSITY: f32 = 0.48;

// Computes the ground size (in blocks) covered by one shadow texel at camera-relative `p`,
// accounting for `frame.shadow_distortion`.
fn shadow_texel(p: vec3<f32>) -> f32 {
    let k = frame.shadow_distortion;
    let r = length((frame.shadow_view_proj * vec4<f32>(p, 1.0)).xy);
    let d = r * k + 1.0 - k;
    return frame.shadow_center_texel * d * d;
}

// Fast 1-tap hardware bilinear 2x2 PCF shadow lookup for foliage and distant blocks (>20m).
// Horizon's `shadow_sampler` uses FilterMode::Linear + CompareFunction::LessEqual, so a single
// hardware sample already interpolates 4 depth texels in 1 instruction.
fn sample_shadow_fast(p: vec3<f32>, offset_dir: vec3<f32>) -> vec3<f32> {
    if !shadows || frame.has_shadow == 0u {
        return vec3<f32>(1.0);
    }

    let dist = length(p);
    if dist > frame.shadow_distance {
        return vec3<f32>(1.0);
    }

    let ground = shadow_texel(p);
    let s = shadow_position(p + offset_dir * ground * 2.0);
    if any(s.xy <= vec2<f32>(0.002)) || any(s.xy >= vec2<f32>(0.998)) {
        return vec3<f32>(1.0);
    }

    let m = frame.shadow_view_proj;
    let zscale = length(vec3<f32>(m[0].z, m[1].z, m[2].z));
    let z = s.z - zscale * ground * 1.8;

    let lit = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, z);
    let fade = smoothstep(0.85, 1.0, dist / frame.shadow_distance);
    return vec3<f32>(mix(lit, 1.0, fade));
}

// Distortion-aware & slope-biased PCF shadow lookup:
// Uses 2-tap diagonal hardware bilinear PCF (8 effective depth comparisons) within 20 blocks
// and 1-tap hardware bilinear PCF beyond 20 blocks to keep 60 FPS in dense biomes.
fn sample_shadow(p: vec3<f32>, offset_dir: vec3<f32>, ndl: f32) -> vec3<f32> {
    if !shadows || frame.has_shadow == 0u {
        return vec3<f32>(1.0);
    }

    let dist = length(p);
    if dist > frame.shadow_distance {
        return vec3<f32>(1.0);
    }

    let ground = shadow_texel(p);
    let c = clamp(ndl, 0.06, 1.0);
    let slope = min(sqrt(1.0 - c * c) / c, 10.0);
    let s = shadow_position(p + offset_dir * ground * (1.5 + min(slope, 3.5)));
    if any(s.xy <= vec2<f32>(0.002)) || any(s.xy >= vec2<f32>(0.998)) {
        return vec3<f32>(1.0);
    }

    let m = frame.shadow_view_proj;
    let zscale = length(vec3<f32>(m[0].z, m[1].z, m[2].z));
    let z = s.z - zscale * ground * (1.2 + 2.2 * slope);

    var lit = 0.0;
    if dist < 20.0 {
        let texel = 0.75 / max(frame.shadow_resolution, 1024.0);
        let a = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy + vec2<f32>(-texel, -texel), z);
        let b = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy + vec2<f32>(texel, texel), z);
        lit = (a + b) * 0.5;
    } else {
        lit = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, z);
    }

    let fade = smoothstep(0.85, 1.0, dist / frame.shadow_distance);
    return vec3<f32>(mix(lit, 1.0, fade));
}

// Removes vanilla's baked directional face shade from `input.tint` where our sun/sky shader
// already computes directional lighting per face.
fn vanilla_face_shade(n: vec3<f32>) -> f32 {
    let a = abs(n);
    if a.y > 0.99 {
        return select(0.5, 1.0, n.y > 0.0);
    }
    if a.z > 0.99 {
        return 0.8;
    }
    if a.x > 0.99 {
        return 0.6;
    }
    return 1.0;
}

// Detects ONLY the mineral veins on ore sprites (excluding stone/deepslate/netherrack)
// and boosts their glow in dark caves.
fn compute_ore_glow(input: MaterialInput) -> vec3<f32> {
    if ore_glow <= 0.001 || input.material < 21u || input.material > 24u {
        return vec3<f32>(0.0);
    }

    let c = input.albedo.rgb;
    let max_c = max(c.r, max(c.g, c.b));
    let min_c = min(c.r, min(c.g, c.b));
    let chroma = max_c - min_c;
    let luma = luminance(c);

    var mask = 0.0;
    var glow_tint = c;

    if input.material == 21u {
        let chroma_mask = smoothstep(0.11, 0.22, chroma);
        let bright_spec = smoothstep(0.58, 0.75, luma) * smoothstep(0.04, 0.10, chroma);
        mask = max(chroma_mask, bright_spec);
        glow_tint = mix(c, c / max(max_c, 0.01), 0.55) * 1.25;
    } else if input.material == 22u {
        let warm_diff = c.r - c.b;
        mask = smoothstep(0.055, 0.12, warm_diff) * smoothstep(0.36, 0.50, luma);
        glow_tint = vec3<f32>(1.05, 0.78, 0.56);
    } else if input.material == 23u {
        let gold_mask = smoothstep(0.42, 0.58, c.g) * smoothstep(0.16, 0.28, c.g - c.b);
        let quartz_mask = smoothstep(0.50, 0.68, luma) * smoothstep(0.38, 0.52, c.b);
        mask = max(gold_mask, quartz_mask);
        glow_tint = select(vec3<f32>(0.95, 0.92, 0.88), vec3<f32>(1.15, 0.82, 0.28), gold_mask > quartz_mask);
    } else if input.material == 24u {
        mask = smoothstep(0.35, 0.48, luma) * smoothstep(0.03, 0.09, c.r - c.b);
        glow_tint = vec3<f32>(1.10, 0.62, 0.36);
    }

    if mask <= 0.01 {
        return vec3<f32>(0.0);
    }

    let ambient_level = max(input.light.y * daylight(), input.light.x * 0.65);
    let dark_factor = mix(0.28, 1.35, 1.0 - ambient_level);
    let pulse = 0.94 + 0.06 * sin(frame.time * 2.2 + (input.position.x + input.position.z) * 0.5);

    return glow_tint * mask * ore_glow * dark_factor * pulse;
}

// Rain surface wetness: darkens porous outdoor surfaces and adds a glossy specular highlight.
fn apply_wetness(base_color: vec3<f32>, input: MaterialInput) -> vec3<f32> {
    if !wetness_enabled || frame.wetness <= 0.005 || input.fluid != 0u {
        return base_color;
    }

    let sky_exposure = smoothstep(0.55, 0.92, input.light.y);
    let up_facing = smoothstep(-0.1, 0.65, input.normal.y);
    let wet = frame.wetness * sky_exposure * (0.35 + 0.65 * up_facing);
    if wet <= 0.01 {
        return base_color;
    }

    var color = base_color * mix(1.0, 0.78, wet);

    let view_dir = normalize(-input.position);
    let ndotv = max(dot(input.normal, view_dir), 0.0);
    let fresnel = 0.04 + 0.96 * pow(1.0 - ndotv, 4.0);

    let sky_sheen = mix(vec3<f32>(0.08, 0.11, 0.18), vec3<f32>(0.45, 0.52, 0.62), daylight());
    let half_vec = normalize(view_dir + frame.light_direction);
    let spec_angle = max(dot(input.normal, half_vec), 0.0);
    let sun_spec = pow(spec_angle, 48.0) * direct_light_color(sun_warmth) * 0.35;

    color += (sky_sheen * fresnel * 0.26 + sun_spec * up_facing) * wet;
    return color;
}

// Computes placed block lighting and per-pixel handheld/dropped dynamic lighting (main hand,
// left hand / offhand, and dropped items) with zero extra texture reads when unlit.
fn compute_block_and_hand_light(input: MaterialInput, day: f32) -> vec3<f32> {
    let dyn_peak = max(input.colored_light.r, max(input.colored_light.g, input.colored_light.b));
    if input.light.x <= 0.005 && dyn_peak <= 0.005 {
        return vec3<f32>(0.0);
    }

    let daylit_suppress = 1.0 - input.light.y * day * 0.65;
    let flicker = 1.0 + (sin(frame.time * 6.8) * 0.55 + sin(frame.time * 15.3) * 0.45) * 0.045;

    var placed_alpha = 0.0;
    var blk_tint = vec3<f32>(1.05, 0.68, 0.35);
    if input.light.x > 0.005 {
        let blk_sample = block_light_color(input.position);
        placed_alpha = min(blk_sample.a, 1.0);
        blk_tint = mix(blk_tint, blk_sample.rgb, placed_alpha);
    }

    var block_term = vec3<f32>(0.0);

    // Per-pixel dynamic light from held items (right hand / left hand) or dropped light items
    if dyn_peak > 0.005 && handlight_strength > 0.001 {
        let dyn_hue = input.colored_light / max(dyn_peak, 0.001) * 1.22;
        // When no placed light block is in the 3D grid, tint vertex block light with the held item's true color
        blk_tint = mix(dyn_hue, blk_tint, placed_alpha);

        let to_hand = normalize(vec3<f32>(0.0, -0.25, 0.0) - input.position);
        let hand_ndl = 0.65 + 0.35 * max(dot(input.normal, to_hand), 0.0);
        let smooth_radial = smoothstep(0.0, 1.0, pow(clamp(dyn_peak, 0.0, 1.0), 0.65));
        block_term += dyn_hue * smooth_radial * hand_ndl * flicker * handlight_strength * daylit_suppress * 0.62;
    }

    if input.light.x > 0.005 {
        // Blend vertex block light with per-pixel radial distance when lit purely by a held item
        let per_pixel_level = clamp(pow(dyn_peak, 0.55), 0.0, 1.0);
        let effective_level = mix(mix(input.light.x, per_pixel_level, 0.65 * step(0.005, dyn_peak)), input.light.x, placed_alpha);
        let blk_factor = pow(effective_level, 1.80) * block_light_strength * daylit_suppress;
        let active_flicker = mix(flicker, 1.0, placed_alpha * 0.65);
        block_term += blk_tint * blk_factor * active_flicker * 0.78;
    }

    return block_term;
}
