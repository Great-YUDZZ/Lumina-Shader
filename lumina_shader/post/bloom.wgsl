// Post Pass 3 (Quarter Resolution, scale = 0.25, output = "bloom_b"):
// Spreads `bloom_a` across a 13-tap dual-ring filter at 1/16th pixel count.

fn post(input: PostInput) -> vec4<f32> {
    let texel = 1.0 / vec2<f32>(textureDimensions(bloom_a));
    var sum = textureSampleLevel(bloom_a, linear_sampler, input.uv, 0.0).rgb * 0.20;

    for (var i = 0; i < 6; i++) {
        let a = f32(i) * 1.0471976;
        let inner = vec2<f32>(cos(a), sin(a));
        let outer = vec2<f32>(cos(a + 0.5235988), sin(a + 0.5235988));
        sum += textureSampleLevel(bloom_a, linear_sampler, input.uv + inner * 1.5 * texel, 0.0).rgb * 0.08;
        sum += textureSampleLevel(bloom_a, linear_sampler, input.uv + outer * 4.0 * texel, 0.0).rgb * 0.0533;
    }

    return vec4<f32>(sum, 1.0);
}
