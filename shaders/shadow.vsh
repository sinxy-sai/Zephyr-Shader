#version 330 compatibility

#include "/lib/settings.glsl"

uniform float frameTimeCounter;
uniform float frameTime;
uniform float rainStrength;
uniform vec3 cameraPosition;
uniform mat4 shadowModelViewInverse;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

#define ZEPHYR_VIEW_INVERSE shadowModelViewInverse

out vec2 texCoord;
out vec4 vertexColor;
flat out float zShadowBlock;

void main() {
    vec3 zPosition = gl_Vertex.xyz;
    // M20: the same vertex one frame earlier, used only for the TAA velocity.
    vec3 zPositionPrev = zPosition;
#if WAVE_ENABLED
    float zBlock = mc_Entity.x;
    if (zBlock >= 10000.0 && zBlock < 10005.0) {
#if WAVE_DEBUG_LIFT
        zPosition.y += 1.0;
        zPositionPrev = zPosition;
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
        float timeScale = mix(1.0, WAVE_FAR_TIME_SCALE,
                              smoothstep(WAVE_SLOW_START, WAVE_SLOW_END, camDist));
        float t     = frameTimeCounter * WAVE_SPEED * timeScale;
        // frameTime can be 0 in Iris gbuffer programs; never let tPrev == t.
        float dt = frameTime > 1e-5 ? min(frameTime, 0.10) : WAVE_FRAME_DT;
        float tPrev = (frameTimeCounter - dt) * WAVE_SPEED * timeScale;
        // Optional amplitude fade, defaulted far outside the visible world.
        float distFade = 1.0 - smoothstep(WAVE_FADE_START, WAVE_FADE_END, camDist);
        // M20: clear-sky amplitude is 1.5x the M19 value; rain adds a further
        // WAVE_RAIN_BOOST * rainStrength on top of that.
        float baseAmp = WAVE_AMPLITUDE * (1.0 + WAVE_RAIN_BOOST * rainStrength)
                      * distFade;
        float topMask = max(step(gl_MultiTexCoord0.t, mc_midTexCoord.t),
                            step(0.26, fract(wPos.y + 0.21)));
        float mask = zBlock >= 10003.0 ? 0.55 : topMask;
        // M20: evaluate the SAME wave at t and t-1. Their clip-space difference
        // is the animated part of the motion vector, so composite2 can fetch
        // the history at the leaf's previous position instead of stacking
        // several instants of foliage.
        vec2 wCur  = vec2(sin(wPos.x * 0.75 + wPos.z * 0.42 + t * 1.30),
                          sin(wPos.z * 1.10 - wPos.x * 0.28 + t * 0.85));
        vec2 wPrev = vec2(sin(wPos.x * 0.75 + wPos.z * 0.42 + tPrev * 1.30),
                          sin(wPos.z * 1.10 - wPos.x * 0.28 + tPrev * 0.85));
        float gCur  = 0.55 + 0.45 * sin(t     * 0.31 + wPos.x * 0.07 + wPos.z * 0.05);
        float gPrev = 0.55 + 0.45 * sin(tPrev * 0.31 + wPos.x * 0.07 + wPos.z * 0.05);
        zPosition.xz     += wCur  * (baseAmp * gCur)  * mask;
        zPositionPrev.xz += wPrev * (baseAmp * gPrev) * mask;
#endif
    }
#endif
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * vec4(zPosition, 1.0);
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vertexColor = gl_Color;
    zShadowBlock = mc_Entity.x;
}
