// Atmospheric fog helper shared across sky, material, and weather stages.
// - Morning / sunset: rich Golden Hour warm amber atmospheric haze
// - Rain: cozy, peaceful slate-blue lo-fi mist
// - Night: soft moonlit blue distance fog
// - Noon (clear day) & caves: zero fog

override fog_strength: f32 = 0.55;

fn atmospheric_fog_color(view_dir: vec3<f32>, warmth: f32, night_dark: f32) -> vec3<f32> {
    if frame.dimension != 0 {
        return frame.fog_color;
    }
    let day = daylight();
    let tw = twilight();
    let night = night_factor();

    let sun_align = max(dot(view_dir, frame.sun_direction), 0.0);
    let day_fog = mix(vec3<f32>(0.62, 0.74, 0.88), vec3<f32>(0.82, 0.76, 0.66), warmth * 0.5);
    let twilight_base = mix(vec3<f32>(0.86, 0.50, 0.32), vec3<f32>(1.14, 0.54, 0.22), warmth);
    let twilight_fog = mix(twilight_base * 0.76, twilight_base * 1.16, pow(sun_align, 1.8));

    let night_scale = mix(0.55, 0.24, night_dark);
    let night_fog = vec3<f32>(0.08, 0.14, 0.24) * night_scale;

    var col = mix(day_fog, twilight_fog, tw);
    col = mix(col, night_fog, night);

    // Cozy Lo-Fi Slate-Blue rain mist
    let rain_day = mix(vec3<f32>(0.35, 0.43, 0.53), vec3<f32>(0.46, 0.44, 0.48), tw * warmth * 0.55);
    let rain_fog = mix(vec3<f32>(0.08, 0.13, 0.20) * night_scale, rain_day, day);
    return mix(col, rain_fog, frame.rain * 0.88);
}

// Computes how much atmospheric fog (0..1) applies at `dist` blocks with `sky_light` (0..1).
fn compute_fog_factor(dist: f32, sky_light: f32, strength_opt: f32) -> f32 {
    if frame.eye_in == 1u {
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

    let tw = twilight();
    let rain_w = max(frame.rain, frame.thunder);
    let night_w = night_factor() * 0.22;
    let time_weight = clamp(max(tw * 0.78, rain_w * 0.92) + night_w * (1.0 - rain_w), 0.0, 1.0);
    let noon_suppress = 1.0 - midday() * (1.0 - rain_w);

    let fog_active = time_weight * noon_suppress * outdoor * strength_opt;
    if fog_active <= 0.001 {
        return 0.0;
    }

    let render_d = max(frame.render_distance, 64.0);
    let start_d = render_d * mix(0.20, 0.10, rain_w);
    let end_d = render_d * mix(1.02, 0.80, rain_w);
    let curve = smoothstep(start_d, end_d, dist);
    return clamp(curve * fog_active * 0.72, 0.0, 0.80);
}
