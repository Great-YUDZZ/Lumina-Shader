// Post Pass 1 (Quarter Resolution, scale = 0.25, output = "rays"):
// Fast Screen-Space Crepuscular Godrays at 1/16th pixel count:
// Radial sun shafts & warm sun glare fanning out through gaps in 3D clouds, leaves, and hills.
// Early-outs immediately when looking away from the sun or during heavy rain (zero shadow-map reads,
// zero first-person player shadow projection artifacts when flying over water).

override godrays: bool = true;
override godray_strength: f32 = 0.75;
override sun_warmth: f32 = 0.65;

fn post(input: PostInput) -> vec4<f32> {
    if !godrays || godray_strength <= 0.001 || frame.dimension != 0 || frame.eye_in != 0u || frame.rain > 0.80 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let l = frame.light_direction;
    let forward = -frame.view_inverse[2].xyz;
    let look_sun = smoothstep(0.02, 0.82, dot(forward, l));
    let sun_clip = frame.projection * (frame.view * vec4<f32>(l, 0.0));
    if look_sun <= 0.001 || sun_clip.w <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let day = daylight();
    let outdoor = smoothstep(0.10, 0.55, frame.eye_light_smooth.y);
    let weather_clear = 1.0 - frame.rain * 0.92;
    let ray_active = day * outdoor * weather_clear * godray_strength * look_sun;

    if ray_active <= 0.005 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let tw = twilight();
    let shaft_col = direct_light_color(sun_warmth) * mix(0.90, 1.32, tw);
    let is_sky = input.depth <= 0.00001;

    // Interleaved gradient noise with temporal golden-ratio offset
    let ign = fract(52.9829189 * fract(dot(input.pixel, vec2<f32>(0.06711056, 0.00583715))));
    let jitter = fract(ign + f32(frame.frame_index % 64u) * 0.61803398);

    let sun_uv = vec2<f32>(sun_clip.x / sun_clip.w * 0.5 + 0.5, 0.5 - sun_clip.y / sun_clip.w * 0.5);
    let aspect = frame.resolution.x / frame.resolution.y;
    let to_sun = (sun_uv - input.uv) * vec2<f32>(aspect, 1.0);
    let sun_dist = length(to_sun);
    if sun_dist > 1.25 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    // Radial march toward the sun on screen (12 steps): bright sky gaps between 3D clouds,
    // leaves, and hills cast long golden crepuscular rays across the sky and foreground,
    // while solid 3D clouds (`depth_at(sample_uv) > 0.0`) block the rays and cast cloud shadows.
    let march_delta = (sun_uv - input.uv) / 12.0 * min(1.0, 1.12 / max(sun_dist, 0.001));
    var sample_uv = input.uv + march_delta * jitter;
    var open_sky_sum = 0.0;
    var occluded_steps = 0.0;
    var decay = 1.0;

    for (var i = 0; i < 12; i++) {
        sample_uv += march_delta;
        let in_screen = all(sample_uv >= vec2<f32>(0.001)) && all(sample_uv <= vec2<f32>(0.999));
        let is_open_sky = in_screen && depth_at(sample_uv) == 0.0;
        let d_sun = length((sample_uv - sun_uv) * vec2<f32>(aspect, 1.0));
        let sun_prox = 0.34 + 0.66 * exp(-d_sun * 2.6);
        open_sky_sum += select(0.0, decay * sun_prox, is_open_sky);
        occluded_steps += select(1.0, 0.0, is_open_sky);
        decay *= 0.94;
    }

    let radial_falloff = 1.0 - smoothstep(0.0, 1.22, sun_dist);
    // Allow radial beams to shine across open sky gaps (`0.88`) so 3D clouds visibly split the sunbeams,
    // while boosting dappled contrast when rays cross cloud or leaf edges.
    let sky_beam_weight = select(1.0, 0.88, is_sky);
    let edge_contrast = 1.0 + 0.35 * sin(clamp(occluded_steps / 12.0, 0.0, 1.0) * 3.14159);
    let radial_shafts = (open_sky_sum / 12.0) * radial_falloff * sky_beam_weight * edge_contrast * 0.82;

    // Warm sun glare/halo when the sun disc itself peeks through gaps in leaves or 3D clouds
    let sun_on_screen = all(sun_uv >= vec2<f32>(0.0)) && all(sun_uv <= vec2<f32>(1.0));
    let sun_visible = select(0.0, 1.0, sun_on_screen && depth_at(sun_uv) == 0.0);
    let glare = (exp(-sun_dist * sun_dist * 45.0) * 0.42 + exp(-sun_dist * 4.5) * 0.14) * sun_visible;

    let total_rays = shaft_col * (radial_shafts + glare) * ray_active;
    return vec4<f32>(total_rays, 1.0);
}
