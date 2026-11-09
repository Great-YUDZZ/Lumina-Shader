// Post Pass 1 (Quarter Resolution, scale = 0.25, output = "rays"):
// Hybrid Crepuscular Godrays + Volumetric Shadow Shafts at 1/16th pixel count:
// 1. Screen-space radial sun shafts & warm sun glare (fanning out through gaps in leaves, clouds, and hills).
// 2. Shadow-map volumetric light shafts (near-camera quadratic steps so beams under forest/jungle canopies show clearly).

override godrays: bool = true;
override godray_strength: f32 = 0.75;
override sun_warmth: f32 = 0.65;

fn post(input: PostInput) -> vec4<f32> {
    if !godrays || godray_strength <= 0.001 || frame.dimension != 0 || frame.eye_in != 0u {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let day = daylight();
    let outdoor = smoothstep(0.10, 0.55, frame.eye_light_smooth.y);
    let weather_clear = 1.0 - frame.rain * 0.85;
    let ray_active = day * outdoor * weather_clear * godray_strength;

    if ray_active <= 0.005 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let l = frame.light_direction;
    let tw = twilight();
    let shaft_col = direct_light_color(sun_warmth) * mix(0.85, 1.25, tw);
    let is_sky = input.depth <= 0.00001;

    // Interleaved gradient noise with temporal golden-ratio offset
    let ign = fract(52.9829189 * fract(dot(input.pixel, vec2<f32>(0.06711056, 0.00583715))));
    let jitter = fract(ign + f32(frame.frame_index % 64u) * 0.61803398);

    var total_rays = vec3<f32>(0.0);

    // --- Part 1: Screen-Space Radial Crepuscular Sun Shafts & Soft Sun Glare ---
    let forward = -frame.view_inverse[2].xyz;
    let look_sun = smoothstep(0.05, 0.85, dot(forward, l));
    let sun_clip = frame.projection * (frame.view * vec4<f32>(l, 0.0));
    if look_sun > 0.0 && sun_clip.w > 0.0 {
        let sun_uv = vec2<f32>(sun_clip.x / sun_clip.w * 0.5 + 0.5, 0.5 - sun_clip.y / sun_clip.w * 0.5);
        let aspect = frame.resolution.x / frame.resolution.y;
        let to_sun = (sun_uv - input.uv) * vec2<f32>(aspect, 1.0);
        let sun_dist = length(to_sun);

        // Radial march toward the sun on screen (12 steps): bright sky gaps between leaves/branches
        // cast long golden crepuscular rays across the canopy and foreground.
        let march_delta = (sun_uv - input.uv) / 12.0 * min(1.0, 0.95 / max(sun_dist, 0.001));
        var sample_uv = input.uv + march_delta * jitter;
        var open_sky_sum = 0.0;
        var decay = 1.0;

        for (var i = 0; i < 12; i++) {
            sample_uv += march_delta;
            let in_screen = all(sample_uv >= vec2<f32>(0.001)) && all(sample_uv <= vec2<f32>(0.999));
            let is_open_sky = in_screen && depth_at(sample_uv) == 0.0;
            let d_sun = length((sample_uv - sun_uv) * vec2<f32>(aspect, 1.0));
            let sun_prox = 0.35 + 0.65 * exp(-d_sun * 3.2);
            open_sky_sum += select(0.0, decay * sun_prox, is_open_sky);
            decay *= 0.94;
        }

        let radial_falloff = 1.0 - smoothstep(0.0, 1.15, sun_dist);
        // Over terrain/leaves (`!is_sky`) shafts show at full strength; over open sky they stay subtle so sky doesn't wash out.
        let sky_suppress = select(1.0, 0.22, is_sky);
        let radial_shafts = (open_sky_sum / 12.0) * radial_falloff * sky_suppress * 0.72;

        // Warm sun glare/halo when the sun disc itself peeks through gaps in leaves or clouds
        let sun_on_screen = all(sun_uv >= vec2<f32>(0.0)) && all(sun_uv <= vec2<f32>(1.0));
        let sun_visible = select(0.0, 1.0, sun_on_screen && depth_at(sun_uv) == 0.0);
        let glare = (exp(-sun_dist * sun_dist * 45.0) * 0.45 + exp(-sun_dist * 4.5) * 0.16) * sun_visible;

        total_rays += shaft_col * (radial_shafts + glare) * look_sun;
    }

    // --- Part 2: Shadow-Map Volumetric Canopy Shafts (3D Air Scattering) ---
    if frame.has_shadow != 0u {
        let sample_depth = select(input.depth, 0.002, is_sky);
        let world_vec = view_position(input.uv, sample_depth);
        let ray_dist = length(world_vec);
        let ray_dir = world_vec / max(ray_dist, 1e-4);

        let cos_theta = max(dot(ray_dir, l), 0.0);
        let phase = 0.28 + 0.72 * pow(cos_theta, 2.2);

        // Quadratic distribution (`u * u * max_trace`) concentrates samples within 2..36 blocks of
        // the camera, right where sunbeams slice through forest and jungle canopies.
        let max_trace = min(ray_dist, min(frame.shadow_distance * 0.85, 40.0));
        if max_trace > 1.5 {
            var accum_lit = 0.0;
            var total_w = 0.0;
            var crossings = 0.0;
            var prev_lit = -1.0;

            for (var i = 0; i < 6; i++) {
                let u = (f32(i) + jitter) / 6.0;
                let t = max_trace * (0.06 + 0.94 * u * u);
                let w = 0.35 + u;
                let sp = shadow_position(ray_dir * t);

                let in_bounds = sp.x > 0.01 && sp.x < 0.99 && sp.y > 0.01 && sp.y < 0.99 && sp.z < 0.999;
                let lit = select(1.0, textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy, sp.z), in_bounds);
                accum_lit += lit * w;
                total_w += w;
                crossings += select(abs(lit - prev_lit), 0.0, prev_lit < 0.0);
                prev_lit = lit;
            }

            let lit_share = accum_lit / max(total_w, 1e-3);
            // Boosts shafts that cross from light into shadow (dappled beams under trees)
            let contrast_boost = 0.35 + 0.65 * clamp(crossings * 0.75, 0.0, 1.0);
            let dist_weight = smoothstep(2.0, 16.0, max_trace);
            let vol_sky_atten = select(1.0, 0.18, is_sky);
            let vol_scatter = lit_share * contrast_boost * phase * dist_weight * vol_sky_atten * 0.38;

            total_rays += shaft_col * vol_scatter;
        }
    }

    return vec4<f32>(total_rays * ray_active, 1.0);
}
