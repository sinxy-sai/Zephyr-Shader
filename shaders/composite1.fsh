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
        float lod = 2.0 + fi * 1.5 * BLOOM_RADIUS;
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
    // Rain makes emissive signage and lamps bloom into the wet haze.
    color += bloom * BLOOM_STRENGTH
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

    float jitter = zephyr_hash12(gl_FragCoord.xy + float(frameCounter) * 0.71);
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
            vis = step(sCoord.z - 0.0012, texture(shadowtex0, sCoord.xy).r);
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
