// Weather stage: tints rain and snow streaks to match the Warm Cinematic palette,
// realistic dark nights, warm torch light, and distance fog.

override sun_warmth: f32 = 0.65;
override night_darkness: f32 = 0.75;
override block_light_strength: f32 = 1.15;

fn weather(input: WeatherInput) -> vec4<f32> {
    let day = daylight();
    let tw = twilight();
    let night_scale = mix(0.38, 0.07, night_darkness);

    let sky_day = mix(vec3<f32>(0.55, 0.62, 0.70), vec3<f32>(0.78, 0.62, 0.50), tw * sun_warmth);
    let sky_night = vec3<f32>(0.08, 0.12, 0.20) * night_scale;
    let sky_lit = mix(sky_night, sky_day, day) * pow(input.light.y, 1.35);

    let torch_col = vec3<f32>(1.15, 0.75, 0.38) * pow(input.light.x, 1.65) * block_light_strength;
    var streak_rgb = input.color.rgb * (sky_lit + torch_col + vec3<f32>(0.03));

    let dist = length(input.position);
    let view_dir = normalize(input.position);
    let fog_f = compute_fog_factor(dist, input.light.y, fog_strength);
    if fog_f > 0.0 {
        let fog_c = atmospheric_fog_color(view_dir, sun_warmth, night_darkness);
        streak_rgb = mix(streak_rgb, fog_c, fog_f);
    }

    let opacity_scale = select(0.62, 0.82, input.snow) * (1.0 - smoothstep(18.0, 42.0, dist));
    return vec4<f32>(streak_rgb, input.color.a * opacity_scale);
}
