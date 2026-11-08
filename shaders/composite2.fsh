#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

in vec2 texCoord;

uniform sampler2D colortex5;   // current frame linear HDR (composite1 output)
uniform sampler2D colortex6;   // TAA history; same pass reads AND writes it
uniform sampler2D colortex9;   // M20: animated-geometry velocity (RG16F)
uniform sampler2D depthtex0;

// Iris gives a feedback attachment an implicit ping-pong pair, so reading and
// writing colortex6 here in the same pass yields the PREVIOUS frame. This is
// how BSL / Complementary / Solas do TAA; no flip. directive is needed.
/* RENDERTARGETS: 7,6 */
layout(location = 0) out vec4 outColor;    // -> colortex7, consumed by final
layout(location = 1) out vec4 outHistory;  // -> colortex6, history for next frame

// Camera-relative scene space: (gbufferModelViewInverse * viewPos).xyz is
// relative to the camera, so compensate camera motion between the two frames.
vec2 zephyr_reprojectTAA(vec2 uv, float depth) {
    // M19: do NOT inject the projection jitter here. gbuffers add jitter to
    // gl_Position in shader space, but gbufferPreviousProjection is Iris'
    // UN-jittered matrix. Removing jitter on the way in without adding the
    // previous frame's jitter back made prevUv = uv - jitter(frame) for a
    // static camera: the history was resampled at a different sub-pixel
    // offset every frame and could never converge -> persistent distant
    // shimmer. Complementary / EuphoriaPatches / BSL reproject straight from
    // texCoord (their TAAJitter(-0.5) is only for view-space reconstruction
    // in the gbuffer FS, never in the TAA resolve). With a static camera the
    // inverse/forward projection round trip is exact and prevUv == texCoord.
    vec4 view = gbufferProjectionInverse
              * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    float w = abs(view.w) < 1e-5 ? 1e-5 : view.w;
    vec3 scenePos = (gbufferModelViewInverse * vec4(view.xyz / w, 1.0)).xyz;
    vec3 cameraOffset = cameraPosition - previousCameraPosition;
    vec4 prev = gbufferPreviousProjection * gbufferPreviousModelView
              * vec4(scenePos + cameraOffset, 1.0);
    if (prev.w <= 0.0) return vec2(-1.0);
    return prev.xy / prev.w * 0.5 + 0.5;
}

// M19: YCoCg keeps luminance and chroma separate while clipping the history.
// In plain RGB a waving cutout leaf gets clamped channel-by-channel and leaves
// rainbow speckle around every silhouette; BSL / photon / iterationT all do
// their neighbourhood clamp in YCoCg (often with variance clipping).
vec3 zephyr_rgb2ycocg(vec3 c) {
    return vec3( 0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
                 0.5  * c.r             - 0.5  * c.b,
                -0.25 * c.r + 0.5 * c.g - 0.25 * c.b);
}
vec3 zephyr_ycocg2rgb(vec3 c) {
    float t = c.x - c.z;
    return max(vec3(t + c.y, c.x + c.z, t - c.y), vec3(0.0));
}

// Clip the history sample into the 3x3 neighbourhood AABB. Prevents ghosts at
// disocclusions. Called in YCoCg space (see zephyr_rgb2ycocg).
vec3 zephyr_clipAABB(vec3 q, vec3 aabbMin, vec3 aabbMax) {
    vec3 centre = 0.5 * (aabbMax + aabbMin);
    vec3 extent = 0.5 * (aabbMax - aabbMin) + 1e-5;
    vec3 offset = q - centre;
    vec3 unit = abs(offset / extent);
    float scale = max(max(unit.x, unit.y), unit.z);
    return scale > 1.0 ? centre + offset / scale : q;
}

void main() {
    vec3 current = max(texture(colortex5, texCoord).rgb, vec3(0.0));
    float depth = texture(depthtex0, texCoord).r;
    float linearDepth = zephyr_linearDepth(depth);
    vec3 result = current;
    vec3 debugHistory = vec3(0.0);

// Debug views must not be blended with a history of the normal frame.
#if TAA_ENABLED && DEBUG_VIEW == 0
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    vec3 aabbMin = zephyr_rgb2ycocg(current);
    vec3 aabbMax = aabbMin;
    float closestDepth = depth;

    for (int y = -TAA_NEIGHBOUR_CLAMP; y <= TAA_NEIGHBOUR_CLAMP; ++y) {
        for (int x = -TAA_NEIGHBOUR_CLAMP; x <= TAA_NEIGHBOUR_CLAMP; ++x) {
            if (x == 0 && y == 0) continue;
            vec2 nuv = clamp(texCoord + vec2(float(x), float(y)) * texel,
                             vec2(0.0), vec2(1.0));
            vec3 c = zephyr_rgb2ycocg(
                max(texture(colortex5, nuv).rgb, vec3(0.0)));
            aabbMin = min(aabbMin, c);
            aabbMax = max(aabbMax, c);
            // Non-linear depth: smaller = nearer. Use the nearest neighbour's
            // velocity so thin foreground objects do not smear.
            closestDepth = min(closestDepth, texture(depthtex0, nuv).r);
        }
    }

    // M19: plain inverse is correct - jitter is a shader-side gl_Position
    // offset and Iris' gbufferPreviousProjection never carries it (see above).
    // M20: depth reprojection only covers CAMERA motion. Animated
    // geometry (waving foliage) also moved between the two frames;
    // subtract its velocity so history is fetched where the leaf was.
    vec2 prevUv = zephyr_reprojectTAA(texCoord, closestDepth);
#if TAA_WAVE_VELOCITY
    prevUv -= texture(colortex9, texCoord).xy;
#endif
    if (prevUv.x > 0.0 && prevUv.x < 1.0 && prevUv.y > 0.0 && prevUv.y < 1.0) {
        vec4 history = texture(colortex6, prevUv);
        debugHistory = history.rgb;
        vec3 historyColor = max(history.rgb, vec3(0.0));
#if TAA_NEIGHBOUR_CLAMP
        historyColor = zephyr_ycocg2rgb(zephyr_clipAABB(
            zephyr_rgb2ycocg(historyColor), aabbMin, aabbMax));
#endif
        float velocityPx = length(prevUv - texCoord) * max(viewWidth, viewHeight);
        float velocityWeight = exp2(-velocityPx * TAA_VELOCITY_REJECT);
        // history.a is the depth at the previous frame's stored pixel. On a
        // disocclusion (leaf edge against sky) it can be far away; an
        // unclamped exp2 would drive blend to TAA_MIN_BLEND on exactly the
        // high-contrast edges that need history most. Give it a floor.
        float depthWeight = max(0.35,
            exp2(-abs(linearDepth - history.a) * TAA_DEPTH_REJECT));
        // M18: distant high-contrast edges are exactly where sub-pixel jitter
        // shimmers. They also have very little screen-space parallax, so a
        // much stronger history weight is safe there (no visible ghosting),
        // while near geometry keeps the original, more responsive blend.
        float farBoost = smoothstep(TAA_FAR_START, TAA_FAR_END, linearDepth);
        float staticBlend = mix(TAA_BLEND, TAA_FAR_BLEND, farBoost);
        float blend = clamp(staticBlend * velocityWeight * depthWeight,
                            TAA_MIN_BLEND, staticBlend);
        result = mix(current, historyColor, blend);
    }
#endif

#if TAA_DEBUG_HISTORY
    outColor = vec4(max(debugHistory, vec3(0.0)), 1.0);
#else
    outColor = vec4(result, 1.0);
#endif
    outHistory = vec4(result, linearDepth);
}
