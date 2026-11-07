#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outNormal;

#include "/lib/gbuffer_body.glsl"

uniform sampler2D gtexture;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vNormal;

void main() {
    vec4 c = texture(gtexture, vTexCoord) * vColor;
    if (c.a < 0.02) discard;
    outAlbedo = vec4(zephyr_srgbToLinear(c.rgb), MAT_TRANSLUCENT);
    outData   = vec4(max(vLightCoord, vec2(0.05)), 1.0, 0.4);
    outNormal = vec4(zephyr_encodeNormal(vNormal), 1.0);
}
