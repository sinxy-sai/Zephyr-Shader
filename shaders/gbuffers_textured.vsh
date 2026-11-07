#version 330 compatibility

#include "/lib/settings.glsl"

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

out vec2 vTexCoord;
out vec2 vLightCoord;
out vec4 vColor;
out vec3 vNormal;

void main() {
    gl_Position  = ftransform();
    gl_Position.xy += zephyr_taaJitterNDC(frameCounter, viewWidth, viewHeight)
                      * gl_Position.w;
    vTexCoord    = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLightCoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor       = gl_Color;
    vNormal      = normalize(gl_NormalMatrix * gl_Normal);
}
