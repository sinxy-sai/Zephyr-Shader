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

in vec4 vColor;
in vec3 vNormal;

void main() {
    outAlbedo = vec4(zephyr_srgbToLinear(vColor.rgb), MAT_SOLID);
    outData   = vec4(1.0, 1.0, 1.0, 0.6);
    outNormal = vec4(zephyr_encodeNormal(vNormal), 1.0);
}
