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
        // M22: WAVE_AMPLITUDE is the clear-sky base (user-tuned 0.08 = 3.2x
        // the M19 value of 0.025); rain scales it by (1 + boost * rainStrength).
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
    // M20: pure waving velocity in UV space. Both instants use the SAME camera
    // matrix, so camera motion stays the job of depth reprojection and the
    // projection jitter cancels out of the difference.
    vec4 zClipCur  = gl_ProjectionMatrix * gl_ModelViewMatrix
                   * vec4(zPosition, 1.0);
    vec4 zClipPrev = gl_ProjectionMatrix * gl_ModelViewMatrix
                   * vec4(zPositionPrev, 1.0);
    float zWc = abs(zClipCur.w)  < 1e-5 ? 1e-5 : zClipCur.w;
    float zWp = abs(zClipPrev.w) < 1e-5 ? 1e-5 : zClipPrev.w;
    vWaveVelocity = (zClipCur.xy / zWc - zClipPrev.xy / zWp) * 0.5;
    gl_Position = zClipCur;
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
