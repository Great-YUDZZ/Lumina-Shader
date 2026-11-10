// Sky stage: Warm Cinematic sky dome with rich Golden Hour, cozy slate-blue rain,
// procedural Aurora Borealis, and rotating night starfield.

override sun_warmth: f32 = 0.65;
override night_darkness: f32 = 0.75;
override aurora_strength: f32 = 0.85;

// Sharp procedural night stars that rotate with the celestial sphere.
fn night_stars(dir: vec3<f32>, night: f32) -> vec3<f32> {
    let visibility = night * (1.0 - frame.rain) * smoothstep(0.04, 0.25, dir.y);
    if visibility <= 0.01 {
        return vec3<f32>(0.0);
    }
    let angle = frame.day_time * 6.2831853;
    let ca = cos(angle);
    let sa = sin(angle);
    let rot_dir = vec3<f32>(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca, dir.z);

    let grid = floor(rot_dir * 240.0);
    let cell_center = (grid + 0.5) / 240.0;
    let dist = length(rot_dir - normalize(cell_center)) * 240.0;

    let seed = hash31(grid);
    if seed < 0.9935 {
        return vec3<f32>(0.0);
    }
    let twinkle = 0.75 + 0.25 * sin(frame.time * 2.6 + seed * 62.8);
    let spot = smoothstep(0.42, 0.05, dist);
    let star_brightness = smoothstep(0.9935, 0.9998, seed) * spot * twinkle;
    let star_tint = mix(vec3<f32>(0.75, 0.86, 1.0), vec3<f32>(1.0, 0.92, 0.78), fract(seed * 91.7));
    return star_tint * star_brightness * visibility * 1.35;
}

fn sky(input: SkyInput) -> vec4<f32> {
    let d = normalize(input.direction);
    if frame.dimension != 0 {
        return input.color;
    }

    let day = daylight();
    let tw = twilight();
    let night = night_factor();
    let night_scale = mix(0.58, 0.24, night_darkness);

    let up = clamp(d.y, 0.0, 1.0);
    let near_horizon = 1.0 - smoothstep(0.0, 0.48, abs(d.y));
    let sun_dot = max(dot(d, frame.sun_direction), 0.0);

    // Calm daytime sky
    let day_zenith = mix(vec3<f32>(0.20, 0.40, 0.78), vec3<f32>(0.24, 0.44, 0.76), sun_warmth * 0.4);
    let day_horizon = mix(vec3<f32>(0.62, 0.74, 0.88), vec3<f32>(0.78, 0.74, 0.68), sun_warmth * 0.45);

    // Rich Golden Hour sky (deep twilight blue-violet zenith, amber-orange-rose horizon)
    let tw_zenith = mix(vec3<f32>(0.15, 0.22, 0.44), vec3<f32>(0.22, 0.20, 0.42), sun_warmth * 0.6);
    let tw_horizon_base = mix(vec3<f32>(0.90, 0.46, 0.24), vec3<f32>(1.14, 0.48, 0.16), sun_warmth);
    let tw_horizon = mix(tw_horizon_base * 0.78, tw_horizon_base * 1.15, pow(sun_dot, 1.5));

    // Moonlit night sky
    let night_zenith = vec3<f32>(0.04, 0.08, 0.16) * night_scale;
    let night_horizon = vec3<f32>(0.08, 0.15, 0.26) * night_scale;

    var zenith_col = mix(day_zenith, tw_zenith, tw * 0.85);
    zenith_col = mix(zenith_col, night_zenith, night);

    var horizon_col = mix(day_horizon, tw_horizon, tw * (0.65 + 0.35 * sun_dot));
    horizon_col = mix(horizon_col, night_horizon, night);

    var sky_col = mix(horizon_col, zenith_col, pow(up, 0.58));

    // Golden Hour & daytime solar scattering halo (hidden during overcast rain)
    let halo = (pow(sun_dot, 7.0) * 0.36 + near_horizon * pow(sun_dot, 2.2) * 0.44) * (1.0 - smoothstep(0.15, 0.70, frame.rain));
    let warm_glow = mix(vec3<f32>(1.0, 0.72, 0.38), vec3<f32>(1.22, 0.52, 0.18), tw) * halo * mix(0.18, 0.96, tw) * day * sun_warmth;
    sky_col += warm_glow;

    // Realistic Sun Disc with limb darkening and corona
    let sun_dir = frame.sun_direction;
    if sun_dir.y > -0.10 {
        let along = dot(d, sun_dir);
        let radius = 0.038;
        let apart = acos(clamp(along, -1.0, 1.0));
        let disc = 1.0 - smoothstep(radius * 0.90, radius, apart);
        let rim = clamp(apart / radius, 0.0, 1.0);
        let limb = 1.0 - 0.40 * (1.0 - sqrt(max(1.0 - rim * rim, 0.0)));
        let disc_col = mix(vec3<f32>(2.6, 2.5, 2.3), vec3<f32>(3.2, 1.45, 0.35), tw) * limb;
        let corona = exp(-max(apart - radius, 0.0) * 80.0) * 0.65 + exp(-max(apart - radius, 0.0) * 16.0) * 0.22;
        let corona_col = mix(vec3<f32>(1.20, 1.05, 0.85), vec3<f32>(1.40, 0.65, 0.22), tw);
        let horizon_fade = smoothstep(-0.03, 0.03, d.y) * (1.0 - frame.rain * 0.85);
        sky_col += corona_col * corona * (1.0 - disc) * horizon_fade;
        sky_col = mix(sky_col, disc_col, disc * horizon_fade);
    }

    // Night stars & Aurora Borealis curtains
    sky_col += night_stars(d, night);
    sky_col += aurora_borealis(d, night, aurora_strength);

    // Dark Overcast Cozy Lo-Fi Slate-Blue rain sky (darker zenith, misty slate horizon)
    let thunder_darken = mix(1.0, 0.62, frame.thunder);
    let rain_zenith_day = vec3<f32>(0.10, 0.14, 0.20) * thunder_darken;
    let rain_horiz_day = mix(vec3<f32>(0.18, 0.23, 0.30), vec3<f32>(0.22, 0.22, 0.27), tw * sun_warmth * 0.5) * thunder_darken;
    let rain_day = mix(rain_horiz_day, rain_zenith_day, pow(up, 0.55));
    let rain_night = mix(vec3<f32>(0.05, 0.08, 0.13), vec3<f32>(0.03, 0.05, 0.09), pow(up, 0.55)) * night_scale;
    let rain_sky = mix(rain_night, rain_day, day);
    let rain_cover = smoothstep(0.0, 1.0, frame.rain) * 0.97;
    sky_col = mix(sky_col, rain_sky, rain_cover);

    // Blend smoothly at the very bottom so distant chunk edges melt into the horizon fog
    let horizon_blend = smoothstep(0.0, 0.15, d.y);
    let rain_bottom = mix(vec3<f32>(0.05, 0.08, 0.13) * night_scale, rain_horiz_day, day);
    let bottom_target = mix(horizon_col, rain_bottom, rain_cover);
    sky_col = mix(bottom_target, sky_col, horizon_blend);

    return vec4<f32>(clamp(sky_col, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
