// Post Pass 1 (Quarter Resolution, scale = 0.25, output = "rays"):
// Screen-Space Radial Crepuscular Godrays (from Horizon Shader v2 Golden Lite):
// Radial sun shafts & warm sun glare fanning out through gaps in 3D clouds, leaves, and hills.
// Uses open-sky depth mask (depth <= 0.00001) so clouds, trees, and terrain naturally split shafts.
// Early-outs immediately when looking away from the sun, during rain, or in caves (zero shadow-map reads).

override godrays: bool = true;
override godray_strength: f32 = 0.75;
override godray_samples: i32 = 16;
override sun_warmth: f32 = 0.65;

fn post(input: PostInput) -> vec4<f32> {
    if !godrays || godray_strength <= 0.001 || frame.dimension != 0 || frame.eye_in != 0u || frame.rain > 0.80 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let l = frame.light_direction;
    let forward = -frame.view_inverse[2].xyz;
    let look_sun = smoothstep(0.02, 0.45, dot(forward, l));
    let sun_clip = frame.projection * (frame.view * vec4<f32>(l, 0.0));
    if look_sun <= 0.001 || sun_clip.w <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let day = daylight();
    let outdoor = smoothstep(0.10, 0.55, frame.eye_light_smooth.y);
    let clear = 1.0 - frame.rain * 0.92;

    let ray_amount = day * outdoor * clear * godray_strength * look_sun;
    if ray_amount <= 0.005 {
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
    if sun_dist > 1.35 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let steps = clamp(godray_samples, 8, 24);
    let march = (sun_uv - input.uv) / f32(steps) * min(1.0, 1.12 / max(sun_dist, 0.001));
    var uv = input.uv + march * jitter;
    var open_sum = 0.0;
    var occluded = 0.0;
    var decay = 1.0;

    for (var i = 0; i < 24; i++) {
        if i >= steps {
            break;
        }
        uv += march;
        let inside = all(uv >= vec2<f32>(0.001)) && all(uv <= vec2<f32>(0.999));
        let open = inside && depth_at(uv) <= 0.00001;
        let d_sun = length((uv - sun_uv) * vec2<f32>(aspect, 1.0));
        let prox = 0.34 + 0.66 * exp(-d_sun * 2.6);
        open_sum += select(0.0, decay * prox, open);
        occluded += select(1.0, 0.0, open);
        decay *= 0.94;
    }

    let count_f = f32(steps);
    let falloff = 1.0 - smoothstep(0.0, 1.45, sun_dist);
    let sky_w = select(1.0, 0.88, is_sky);
    let contrast = 1.0 + 0.35 * sin(clamp(occluded / count_f, 0.0, 1.0) * 3.14159);
    let shafts = (open_sum / count_f) * falloff * sky_w * contrast * 1.00;

    let on_screen = all(sun_uv >= vec2<f32>(0.0)) && all(sun_uv <= vec2<f32>(1.0));
    let sun_vis = select(0.0, 1.0, on_screen && depth_at(sun_uv) <= 0.00001);
    let glare = (exp(-sun_dist * sun_dist * 45.0) * 0.42 + exp(-sun_dist * 4.5) * 0.14) * sun_vis;

    return vec4<f32>(shaft_col * (shafts + glare) * ray_amount, 1.0);
}
