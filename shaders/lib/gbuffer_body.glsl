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

// G-buffer channel contract (M13):
//   colortex0.rgb = linear albedo, colortex0.a = REAL alpha
//   colortex1.rg  = lightmap, colortex1.b = roughness, colortex1.a = MAT_* id
//   colortex2.rgb = encoded view normal, colortex2.a = thin-surface flag
// colortex0.a must carry the true alpha: Iris blends gbuffers_water with
// SRC_ALPHA / ONE_MINUS_SRC_ALPHA, so storing matId (2.0) there pinned the
// blend factor at 1 and made stained glass either vanish (the centre of a
// glass texture is alpha~0 and was alpha-tested away) or cover the background.
// matId therefore lives in colortex1.a's previously unused slot.
void writeSolid(vec4 c, vec2 lm, float matId, float roughness, vec3 n) {
    if (c.a < 0.10) discard;
    outAlbedo = vec4(zephyr_srgbToLinear(c.rgb), 1.0);
    outData   = vec4(clamp(lm, 0.0, 1.0), clamp(roughness, 0.03, 1.0), matId);
    outNormal = vec4(zephyr_encodeNormal(n), 0.0);
}

void writeTranslucent(vec4 c, vec2 lm, float matId, float roughness, vec3 n) {
    // No alpha test: glass / weather textures have large low-alpha regions.
    // Discarding them was the reason coloured glass rendered as "invisible".
    outAlbedo = vec4(zephyr_srgbToLinear(c.rgb), clamp(c.a, 0.0, 1.0));
    outData   = vec4(clamp(lm, 0.0, 1.0), clamp(roughness, 0.03, 1.0), matId);
    outNormal = vec4(zephyr_encodeNormal(n), 0.0);
}

// gbuffers_water only: keep a floor under the alpha so stained glass keeps a
// visible tint even where the vanilla texture is completely transparent.
void writeBlended(vec4 c, vec2 lm, float matId, float roughness, vec3 n,
                  float minAlpha) {
    // Cap below 1.0: colortex0.a doubles as the glass mask, and 1.0 means
    // "opaque / no glass" to the final pass.
    outAlbedo = vec4(zephyr_srgbToLinear(c.rgb),
                     clamp(max(c.a, minAlpha), 0.0, 0.95));
    outData   = vec4(clamp(lm, 0.0, 1.0), clamp(roughness, 0.03, 1.0), matId);
    outNormal = vec4(zephyr_encodeNormal(n), 0.0);
}

void writeEmissive(vec4 c, float strength) {
    if (c.a < 0.02) discard;
    outAlbedo = vec4(zephyr_srgbToLinear(c.rgb) * strength, 1.0);
    outData   = vec4(1.0, 1.0, 0.5, MAT_EMISSIVE);
    outNormal = vec4(0.5, 0.5, 1.0, 0.0);
}
