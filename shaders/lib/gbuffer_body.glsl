// Zephyr Z1 G-buffer write helpers.
// Included AFTER the layout(location=...) outputs are declared.

// Lightweight parallax for vanilla texture packs: albedo luminance is the
// pseudo height map, so no extra textures are needed. Two cues are combined:
// a small UV shift for real parallax and screen-space height derivatives for
// the shading normal. Only applied to terrain-ish solid programs (see
// PARALLAX_PROGRAMS in gen_gbuffers.py).
//
// tile.xy / tile.zw are the lower bound and size of the current atlas tile,
// derived from mc_midTexCoord in the vertex stage (BSL / Complementary style).
// Clamping the shifted UV to that tile is what prevents the bright seams and
// texture tearing seen in the first M11 attempt. Set POM_DEPTH to 0 to fall
// back to the safe bump-only path.
vec2 zephyr_parallaxUV(sampler2D tex, vec2 uv, vec3 n, vec4 tile) {
#if POM_ENABLED
    if (POM_DEPTH > 0.0) {
        vec2 size = tile.zw;
        // Non-quad geometry can supply a degenerate midTexCoord; keep the UVs
        // untouched rather than clamping to a bogus rectangle.
        if (size.x > 1e-5 && size.y > 1e-5 && size.x < 0.5 && size.y < 0.5) {
            float height = zephyr_luma(texture(tex, uv).rgb);
            vec2 offset = n.xy * (height - 0.5) * POM_DEPTH;
            vec2 lo = tile.xy + 0.002;
            vec2 hi = tile.xy + size - 0.002;
            return clamp(uv + offset, min(lo, hi), max(lo, hi));
        }
    }
#endif
    return uv;
}

// UV-space finite differences, not dFdx/dFdy: screen-space derivatives shrink
// with distance and change with render resolution, so the relief used to fade
// out on far surfaces and shimmer when the camera moved. One atlas texel is a
// fixed, resolution-independent step and never leaves the current tile.
vec3 zephyr_parallaxNormal(sampler2D tex, vec2 uv, vec3 n) {
#if POM_ENABLED
    vec2 texel = 1.0 / vec2(max(textureSize(tex, 0), ivec2(1)));
    float h  = zephyr_luma(texture(tex, uv).rgb);
    float hx = zephyr_luma(texture(tex, uv + vec2(texel.x, 0.0)).rgb);
    float hy = zephyr_luma(texture(tex, uv + vec2(0.0, texel.y)).rgb);
    vec2 grad = vec2(h - hx, h - hy);
    return normalize(n + vec3(grad.x, grad.y, 0.0) * POM_BUMP);
#else
    return n;
#endif
}

void writeSolid(vec4 c, vec2 lm, float matId, float roughness, vec3 n) {
    if (c.a < 0.10) discard;
    outAlbedo = vec4(zephyr_srgbToLinear(c.rgb), matId);
    outData   = vec4(clamp(lm, 0.0, 1.0), clamp(roughness, 0.03, 1.0), 0.0);
    outNormal = vec4(zephyr_encodeNormal(n), 0.0);
}

void writeTranslucent(vec4 c, vec2 lm, float matId, float roughness, vec3 n) {
    if (c.a < 0.02) discard;
    outAlbedo = vec4(zephyr_srgbToLinear(c.rgb), matId);
    outData   = vec4(clamp(lm, 0.0, 1.0), clamp(roughness, 0.03, 1.0), 0.0);
    outNormal = vec4(zephyr_encodeNormal(n), 0.0);
}

void writeEmissive(vec4 c, float strength) {
    if (c.a < 0.02) discard;
    outAlbedo = vec4(zephyr_srgbToLinear(c.rgb) * strength, MAT_EMISSIVE);
    outData   = vec4(1.0, 1.0, 0.5, 0.0);
    outNormal = vec4(0.5, 0.5, 1.0, 0.0);
}
