// Zephyr Z1 G-buffer write helpers.
// Included AFTER the layout(location=...) outputs are declared.

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
