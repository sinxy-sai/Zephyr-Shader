#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

/* RENDERTARGETS: 0,1,2,9 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outNormal;
layout(location = 3) out vec4 outVelocity;

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
    writeSolid(c, vLightCoord, MAT_HAND, 0.5, vNormal);
    // M22: a held light source (torch, lantern) glows itself as well as
    // lighting the scene. Additive and modest so bloom/AgX keep it readable.
    float held = max(float(heldBlockLightValue), float(heldBlockLightValue2));
    outAlbedo.rgb += zephyr_srgbToLinear(c.rgb)
                   * clamp(held / 15.0, 0.0, 1.0) * HAND_EMISSIVE_GAIN;
}
