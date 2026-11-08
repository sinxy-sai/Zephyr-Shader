#version 330 compatibility

#include "/lib/settings.glsl"

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;
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

void main() {
    vec3 zPosition = gl_Vertex.xyz;
#if WAVE_ENABLED
    float zBlock = mc_Entity.x;
    if (zBlock >= 10000.0 && zBlock < 10005.0) {
#if WAVE_DEBUG_LIFT
        zPosition.y += 1.0;
#else
        vec3 wPos = (ZEPHYR_VIEW_INVERSE * gl_ModelViewMatrix
                    * vec4(zPosition, 1.0)).xyz + cameraPosition;
        // Both passes compute the same WORLD position so the phase stays in sync.
        float camDist = length(wPos - cameraPosition);
        // M19: distant foliage is sub-pixel, so a full-speed wave reads as
        // per-frame flicker rather than motion. Slow the TIME frequency with
        // distance instead of removing the wave: neighbouring frames then
        // move less than a pixel and TAA can accumulate, while leaves still
        // visibly sway. All five reference packs wave at every distance;
        // unlike M18 we never fade the amplitude to zero.
        float t = frameTimeCounter * WAVE_SPEED
                * mix(1.0, WAVE_FAR_TIME_SCALE,
                      smoothstep(WAVE_SLOW_START, WAVE_SLOW_END, camDist));
        float s1 = sin(wPos.x * 0.75 + wPos.z * 0.42 + t * 1.30);
        float s2 = sin(wPos.z * 1.10 - wPos.x * 0.28 + t * 0.85);
        float gust = 0.55 + 0.45 * sin(t * 0.31 + wPos.x * 0.07 + wPos.z * 0.05);
        // Optional amplitude fade, defaulted far outside the visible world.
        float distFade = 1.0 - smoothstep(WAVE_FADE_START, WAVE_FADE_END, camDist);
        float amp = WAVE_AMPLITUDE * (1.0 + 0.7 * rainStrength) * gust * distFade;
        float topMask = max(step(gl_MultiTexCoord0.t, mc_midTexCoord.t),
                            step(0.26, fract(wPos.y + 0.21)));
        float mask = zBlock >= 10003.0 ? 0.55 : topMask;
        zPosition.xz += vec2(s1, s2) * amp * mask;
#endif
    }
#endif
    gl_Position  = gl_ProjectionMatrix * gl_ModelViewMatrix
                 * vec4(zPosition, 1.0);
    gl_Position.xy += zephyr_taaJitterNDC(frameCounter, viewWidth, viewHeight)
                      * gl_Position.w;
    vTexCoord    = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 zMid    = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
    vec2 zDelta  = vTexCoord - zMid;
    vTexCoordAM  = vec4(min(vTexCoord, zMid - zDelta), abs(zDelta) * 2.0);
    zBlockId     = mc_Entity.x;
    vLightCoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vColor       = gl_Color;
    vNormal      = normalize(gl_NormalMatrix * gl_Normal);
}
