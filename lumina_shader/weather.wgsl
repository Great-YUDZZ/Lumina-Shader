// Weather stage: calm, soft lo-fi slate-blue rain streaks and crisp snow streaks
// with warm golden lantern/torch catchlights and smooth distance fade.

override sun_warmth: f32 = 0.65;
override night_darkness: f32 = 0.75;
override block_light_strength: f32 = 1.15;

fn weather(input: WeatherInput) -> vec4<f32> {
    let day = daylight();
    let tw = twilight();
    let night_scale = mix(0.55, 0.24, night_darkness);

    let sky_day = mix(vec3<f32>(0.44, 0.53, 0.64), vec3<f32>(0.68, 0.56, 0.48), tw * sun_warmth);
    let sky_night = vec3<f32>(0.10, 0.16, 0.26) * night_scale;
    let sky_lit = mix(sky_night, sky_day, day) * pow(input.light.y, 1.25);

    let torch_col = vec3<f32>(1.20, 0.78, 0.36) * pow(input.light.x, 1.55) * block_light_strength;
    var streak_rgb = input.color.rgb * (sky_lit + torch_col + vec3<f32>(0.035));

    let dist = length(input.position);
    let view_dir = normalize(input.position);
    let fog_f = compute_fog_factor(dist, input.light.y, fog_strength);
    if fog_f > 0.0 {
        let fog_c = atmospheric_fog_color(view_dir, sun_warmth, night_darkness);
        streak_rgb = mix(streak_rgb, fog_c, fog_f);
    }

    // Gentle, unobtrusive rain streaks (0.34 opacity) for a peaceful, chill rainy mood
    let opacity_scale = select(0.34, 0.78, input.snow) * (1.0 - smoothstep(14.0, 36.0, dist));
    return vec4<f32>(streak_rgb, input.color.a * opacity_scale);
}
