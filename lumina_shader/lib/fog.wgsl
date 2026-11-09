// Atmospheric fog helper shared across sky, material, and weather stages.
// Rules from design:
// - Morning / sunset / rain: soft warm or moody atmospheric fog
// - Night: very subtle dark blue distance fog so far chunks don't look flat
// - Noon (clear day): zero fog
// - Inside caves (low sky light): zero fog so glowing ores stay crisp

override fog_strength: f32 = 0.55;

fn atmospheric_fog_color(view_dir: vec3<f32>, warmth: f32, night_dark: f32) -> vec3<f32> {
    if frame.dimension != 0 {
        return frame.fog_color;
    }
    let day = daylight();
    let tw = twilight();
    let night = night_factor();

    let sun_align = max(dot(view_dir, frame.sun_direction), 0.0);
    let day_fog = mix(vec3<f32>(0.68, 0.80, 0.95), vec3<f32>(0.88, 0.82, 0.72), warmth * 0.5);
    let twilight_base = mix(vec3<f32>(0.78, 0.52, 0.38), vec3<f32>(1.05, 0.56, 0.26), warmth);
    let twilight_fog = mix(twilight_base * 0.75, twilight_base * 1.15, pow(sun_align, 2.0));

    let night_scale = mix(0.38, 0.10, night_dark);
    let night_fog = vec3<f32>(0.06, 0.10, 0.18) * night_scale;

    var col = mix(day_fog, twilight_fog, tw);
    col = mix(col, night_fog, night);

    let rain_fog = mix(vec3<f32>(0.08, 0.10, 0.14) * night_scale, vec3<f32>(0.48, 0.53, 0.58), day);
    return mix(col, rain_fog, frame.rain * 0.88);
}

// Computes how much atmospheric fog (0..1) applies at `dist` blocks with `sky_light` (0..1).
fn compute_fog_factor(dist: f32, sky_light: f32, strength_opt: f32) -> f32 {
    if frame.eye_in == 1u {
        // Underwater fog
        return clamp(dist / 28.0, 0.0, 0.88);
    }
    if frame.eye_in == 2u {
        return clamp(dist / 6.0, 0.0, 0.95);
    }
    if frame.dimension != 0 {
        let van = clamp((dist - frame.fog_start) / max(frame.fog_end - frame.fog_start, 1.0), 0.0, 1.0);
        return van * 0.65;
    }

    // Cave suppression: zero fog underground where sky_light is low
    let outdoor = smoothstep(0.15, 0.55, max(sky_light, frame.eye_light_smooth.y));
    if outdoor <= 0.001 || strength_opt <= 0.001 {
        return 0.0;
    }

    // Active during sunrise/sunset (twilight), rain/thunder, and very subtly at night.
    // Explicitly 0 during clear midday.
    let tw = twilight();
    let rain_w = max(frame.rain, frame.thunder);
    let night_w = night_factor() * 0.22;
    let time_weight = clamp(max(tw * 0.75, rain_w * 0.95) + night_w * (1.0 - rain_w), 0.0, 1.0);
    let noon_suppress = 1.0 - midday() * (1.0 - rain_w);

    let fog_active = time_weight * noon_suppress * outdoor * strength_opt;
    if fog_active <= 0.001 {
        return 0.0;
    }

    let render_d = max(frame.render_distance, 64.0);
    let start_d = render_d * mix(0.22, 0.08, rain_w);
    let end_d = render_d * mix(1.05, 0.78, rain_w);
    let curve = smoothstep(start_d, end_d, dist);
    return clamp(curve * fog_active * 0.72, 0.0, 0.82);
}
