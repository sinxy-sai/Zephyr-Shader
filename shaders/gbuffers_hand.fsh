#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

/* RENDERTARGETS: 0,1,2,8,9 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outNormal;
layout(location = 3) out vec4 outGlass;
layout(location = 4) out vec4 outVelocity;

in vec2 vWaveVelocity;

#include "/lib/gbuffer_body.glsl"

uniform sampler2D gtexture;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vNormal;

void main() {
    outVelocity = vec4(vWaveVelocity, 0.0, 1.0);
    vec4 c = texture(gtexture, vTexCoord) * vColor;
    // M23: MC routes held stained glass through EITHER gbuffers_hand OR
    // gbuffers_hand_water depending on the item. White stained glass lands
    // HERE, where writeSolid's alpha test discarded its whole transparent
    // centre - that is why it was invisible even after the hand_water fix.
    // Handle any low-alpha held item with the same glass path.
    if (c.a < 0.95) {
        float glassA = clamp(max(c.a, HAND_GLASS_MIN_ALPHA), 0.0, 0.95);
        writeTranslucent(c, vLightCoord, MAT_TRANSLUCENT, 0.18, vNormal);
        float chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
        float lowChroma = 1.0 - smoothstep(0.04, 0.25, chroma);
        float absorb = mix(GLASS_MIN_ABSORB, GLASS_WHITE_ABSORB, lowChroma);
        outGlass = vec4(zephyr_srgbToLinear(c.rgb) * (1.0 - absorb), glassA);
    } else {
        writeSolid(c, vLightCoord, MAT_HAND, 0.5, vNormal);
        // M22/M23: a held light source (torch, lantern) glows itself as well
        // as lighting the scene. HDR gain so the bloom pass can halo it.
        float held = max(float(heldBlockLightValue), float(heldBlockLightValue2));
        outAlbedo.rgb += zephyr_srgbToLinear(c.rgb)
                       * clamp(held / 15.0, 0.0, 1.0) * HAND_EMISSIVE_GAIN;
    }
}
