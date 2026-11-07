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

in vec4 vTexCoordAM;

uniform sampler2D gtexture;

in vec2 vTexCoord;
in vec2 vLightCoord;
in vec4 vColor;
in vec3 vNormal;

void main() {
    vec2 zUv = zephyr_parallaxUV(gtexture, vTexCoord, vNormal, vTexCoordAM);
    vec4 c = texture(gtexture, zUv) * vColor;
    writeSolid(c, vLightCoord, MAT_SOLID, 0.55, zephyr_parallaxNormal(gtexture, zUv, vNormal));
}
