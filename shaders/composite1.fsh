#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

in vec2 texCoord;

uniform sampler2D colortex4;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;

/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 outColor;

void main() {
    vec3 color = max(texture(colortex4, texCoord).rgb, vec3(0.0));

    // Soft-knee threshold + decreasing mip weights: bright cores stay tight
    // while the surrounding haze spreads, instead of a hard cut at threshold.
    vec3 bloom = vec3(0.0);
    float weightSum = 0.0;
    float knee = BLOOM_THRESHOLD * BLOOM_KNEE;
    for (int i = 0; i < BLOOM_TAPS; ++i) {
        float fi = float(i);
        // M23: start at lod 0. Previously the first tap was lod 2 (a 4x4
        // average), which diluted small lamps / torches below the threshold
        // before they could ever bloom. Higher taps still supply the wide haze.
        float lod = fi * 1.5 * BLOOM_RADIUS;
        vec3 c = max(textureLod(colortex3, texCoord, lod).rgb, vec3(0.0));
        float b = max(zephyr_luma(c), 1e-4);
        float soft = clamp(b - BLOOM_THRESHOLD + knee, 0.0, 2.0 * knee);
        soft = soft * soft / (4.0 * knee + 1e-4);
        float contribution = max(soft, b - BLOOM_THRESHOLD) / b;
        float w = 1.0 / (1.0 + fi * 0.75);
        bloom += c * contribution * w;
        weightSum += w;
    }
    bloom /= max(weightSum, 1e-4);
    // M23: "every light source should bloom" means a LOW threshold, but the
    // sky is also bright in linear HDR - without a mask it turns the whole
    // frame into a white sheet (measured hi>200 3.5% -> 10.2%). Suppress the
    // additive bloom on sky pixels only; mip samples still spread a little
    // light around silhouettes, which is exactly the wanted halo.
    float depthRaw = texture(depthtex0, texCoord).r;
    float skyMask = smoothstep(0.9990, 0.99995, depthRaw);
    // Rain makes emissive signage and lamps bloom into the wet haze.
    color += bloom * BLOOM_STRENGTH * mix(1.0, BLOOM_SKY_ATTENUATION, skyMask)
           * (1.0 + clamp(rainStrength, 0.0, 1.0) * RAIN_BLOOM_BOOST);

#if VL_ENABLED
    vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    float dayAmount = zephyr_dayAmount(sunDirWorld.y);

    // World-space raymarch against the shadow map. Unlike a screen-space radial
    // blur this works even when the sun disc is outside the frame, and occluders
    // (foliage, buildings) carve real shafts out of the in-scattered light.
    float dRaw = texture(depthtex0, texCoord).r;
    float sceneDist = dRaw < 0.9999 ? zephyr_linearDepth(dRaw) : VL_MAX_DISTANCE;
    sceneDist = min(sceneDist, VL_MAX_DISTANCE);

    vec4 viewClip = gbufferProjectionInverse * vec4(texCoord * 2.0 - 1.0, 1.0, 1.0);
    float vw = abs(viewClip.w) < 1e-5 ? 1e-5 : viewClip.w;
    vec3 rd = normalize(mat3(gbufferModelViewInverse) * normalize(viewClip.xyz / vw));
    float muVL = max(dot(rd, sunDirWorld), 0.0);
    // No constant phase floor: away from the sun there must be no wash-out.
    float phase = pow(muVL, 2.0);

    // Spatially varying but TEMPORALLY FIXED raymarch offset. hash12 with a
    // frameCounter term (or any per-frame phase) re-rolls every step each
    // frame, so the shafts never converge and the bright far edges shimmer.
    // TAA's own sub-pixel projection jitter already supplies temporal
    // sampling; keeping this offset static lets the history actually
    // accumulate while the spatial hash hides the raymarch banding.
    float jitter = zephyr_hash12(gl_FragCoord.xy);
    float stepLen = sceneDist / float(VL_STEPS);
    float weight = 1.0;
    float shafts = 0.0;
    for (int i = 0; i < VL_STEPS; ++i) {
        vec3 relPos = rd * ((float(i) + jitter) * stepLen);
        vec4 sClip = shadowProjection * shadowModelView * vec4(relPos, 1.0);
        float sw = abs(sClip.w) < 1e-5 ? 1e-5 : sClip.w;
        vec3 sCoord = sClip.xyz / sw * 0.5 + 0.5;
        float vis = 0.0;
        if (sCoord.x > 0.0 && sCoord.x < 1.0 && sCoord.y > 0.0 && sCoord.y < 1.0 &&
            sCoord.z > 0.0 && sCoord.z < 1.0) {
            // Smooth comparison instead of a binary step: a hard 0/1 per
            // raymarch step produces banded light shafts for the same reason
            // a hard PCF produced banded shadows.
            float closest = texture(shadowtex0, sCoord.xy).r;
            vis = smoothstep(-VL_SHADOW_SOFTNESS, VL_SHADOW_SOFTNESS,
                             closest - (sCoord.z - 0.0012));
        }
        shafts += vis * weight;
        weight *= VL_DECAY;
    }
    shafts /= float(VL_STEPS);

    vec3 shaftColor = mix(vec3(1.00, 0.52, 0.22), vec3(1.00, 0.88, 0.68),
                          zephyr_warmMix(sunDirWorld.y));
    color += shaftColor * shafts * VL_INTENSITY * phase * dayAmount
           * (1.0 - clamp(rainStrength, 0.0, 1.0) * 0.85);
#endif

    outColor = vec4(clamp(color, 0.0, 65504.0), 1.0);
}
