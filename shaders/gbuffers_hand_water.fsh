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
    // M22: held translucent items follow the PLACED-glass path: real-alpha
    // blend in colortex0 + a colortex8 layer, so composite.fsh applies the
    // subtractive tint / Fresnel BEFORE fog and TAA. MAT_TRANSLUCENT (not
    // MAT_HAND) keeps the covered background on the normal lighting branch;
    // a hand-specific branch here would carve a visible rectangle where the
    // glass is transparent.
    float glassA = clamp(max(c.a, HAND_GLASS_MIN_ALPHA), 0.0, 0.95);
    writeTranslucent(c, vLightCoord, MAT_TRANSLUCENT, 0.18, vNormal);
    outGlass = vec4(zephyr_srgbToLinear(c.rgb) * (1.0 - GLASS_MIN_ABSORB),
                    glassA);
}
