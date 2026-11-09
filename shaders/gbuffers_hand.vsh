#version 330 compatibility

#include "/lib/settings.glsl"

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;
uniform float frameTime;
uniform float rainStrength;
uniform vec3 cameraPosition;

uniform mat4 gbufferModelViewInverse;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

#define ZEPHYR_VIEW_INVERSE gbufferModelViewInverse

out vec2 vTexCoord;
out vec2 vLightCoord;
out vec4 vColor;
out vec3 vNormal;
out vec4 vTexCoordAM;
flat out float zBlockId;
out vec2 vWaveVelocity;   // M20: UV-space velocity of the waving part

void main() {
    vec4 zClipCur = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
    gl_Position = zClipCur;
    gl_Position.xy += zephyr_taaJitterNDC(frameCounter, viewWidth, viewHeight)
                      * gl_Position.w;
    vWaveVelocity = vec2(0.0);
    vTexCoord    = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 zMid    = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
    vec2 zDelta  = vTexCoord - zMid;
    vTexCoordAM  = vec4(min(vTexCoord, zMid - zDelta), abs(zDelta) * 2.0);
    zBlockId     = mc_Entity.x;
    vLightCoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor       = gl_Color;
    vNormal      = normalize(gl_NormalMatrix * gl_Normal);
}
