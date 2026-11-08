#version 330 compatibility

#include "/lib/settings.glsl"

uniform float frameTimeCounter;
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
#if WAVE_ENABLED
    float zBlock = mc_Entity.x;
    if (zBlock >= 10000.0 && zBlock < 10005.0) {
#if WAVE_DEBUG_LIFT
        zPosition.y += 1.0;
#else
        vec3 wPos = (ZEPHYR_VIEW_INVERSE * gl_ModelViewMatrix
                    * vec4(zPosition, 1.0)).xyz + cameraPosition;
        float t = frameTimeCounter * WAVE_SPEED;
        float s1 = sin(wPos.x * 0.75 + wPos.z * 0.42 + t * 1.30);
        float s2 = sin(wPos.z * 1.10 - wPos.x * 0.28 + t * 0.85);
        float gust = 0.55 + 0.45 * sin(t * 0.31 + wPos.x * 0.07 + wPos.z * 0.05);
        // Far foliage cannot show sub-pixel waving anyway, but its per-vertex
        // motion makes distant tree crowns shimmer under TAA's sub-pixel
        // jitter (measured: disabling waving cut far frame RMSE 4.94 -> 2.96).
        // Fade the amplitude with camera distance; both passes compute the
        // same WORLD position, so gbuffers and shadow stay in sync.
        float camDist = length(wPos - cameraPosition);
        float distFade = 1.0 - smoothstep(WAVE_FADE_START, WAVE_FADE_END, camDist);
        float amp = WAVE_AMPLITUDE * (1.0 + 0.7 * rainStrength) * gust * distFade;
        float topMask = max(step(gl_MultiTexCoord0.t, mc_midTexCoord.t),
                            step(0.26, fract(wPos.y + 0.21)));
        float mask = zBlock >= 10003.0 ? 0.55 : topMask;
        zPosition.xz += vec2(s1, s2) * amp * mask;
#endif
    }
#endif
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * vec4(zPosition, 1.0);
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vertexColor = gl_Color;
    zShadowBlock = mc_Entity.x;
}
