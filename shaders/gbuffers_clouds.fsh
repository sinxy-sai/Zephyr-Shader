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

void main() {
    outVelocity = vec4(vWaveVelocity, 0.0, 1.0);
    // The cloud deck is generated analytically in the deferred pass; pushing the
    // depth to the far plane makes these fragments read as sky.
    gl_FragDepth = 1.0;
    discard;
}
