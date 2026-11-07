#version 330 compatibility

// M12: shadowcolor0 stores the transmitted colour of translucent casters.
// Iris clears it to white (full transmission); opaque casters write black and
// the deferred stage only reads the colour where shadowtex1 confirms that no
// opaque geometry blocked the light. Complementary / BSL / photon / Solas all
// follow this convention. No shadowcolor0Format or clear-colour directive is
// needed - none of the reference packs declare one.
uniform sampler2D gtexture;

in vec2 texCoord;
in vec4 vertexColor;
flat in float zShadowBlock;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outShadowColor;

void main() {
    vec4 c = texture(gtexture, texCoord) * vertexColor;
    if (c.a < 0.10) discard;

    bool translucentCaster = (zShadowBlock >= 11000.0 && zShadowBlock < 11010.0);
    // Zephyr uses the SOFT form T = s0 + tint * s1 * (1 - s0), which also
    // reads shadowcolor0 in PCF penumbrae where s1 is fractional. Writing
    // black for opaque casters (Complementary / BSL / photon, which instead
    // hard-gate on `shadow1 > 0.9999`) made those penumbrae go almost black
    // and crushed every sunlit shadow. White keeps opaque penumbrae neutral;
    // only translucent casters tint the transmitted light.
    // Stored sRGB-encoded for 8-bit precision; deferred decodes it.
    outShadowColor = translucentCaster
                   ? vec4(clamp(c.rgb, 0.0, 1.0), 1.0)
                   : vec4(1.0);
}
