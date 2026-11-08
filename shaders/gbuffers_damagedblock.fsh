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
    if (c.a < 0.02) discard;
    outAlbedo = vec4(zephyr_srgbToLinear(c.rgb), clamp(c.a, 0.0, 1.0));
    outData   = vec4(max(vLightCoord, vec2(0.05)), 0.4, MAT_TRANSLUCENT);
    outNormal = vec4(zephyr_encodeNormal(vNormal), 1.0);
}
