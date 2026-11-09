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
    // M24: M23 tried to detect held glass with "c.a < 0.95" HERE. That is
    // wrong for cutout items (torch, tools): their fully transparent quad
    // texels (c.a == 0) were tagged as glass in colortex8, so composite.fsh
    // painted a large rectangular frosted panel trailing from the held torch.
    // Held glass is rendered by gbuffers_hand_water; keep writeSolid's alpha
    // test here (it discards exactly those transparent texels).
    writeSolid(c, vLightCoord, MAT_HAND, 0.5, vNormal);
    // M22/M23: a held light source (torch, lantern) glows itself as well
    // as lighting the scene. HDR gain so the bloom pass can halo it.
    float held = max(float(heldBlockLightValue), float(heldBlockLightValue2));
    outAlbedo.rgb += zephyr_srgbToLinear(c.rgb)
                   * clamp(held / 15.0, 0.0, 1.0) * HAND_EMISSIVE_GAIN;
}
