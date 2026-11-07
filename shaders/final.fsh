#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

in vec2 texCoord;

uniform sampler2D colortex5;
uniform sampler2D colortex3;
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    vec3 hdr = max(texture(colortex5, texCoord).rgb, vec3(0.0));

#if DEBUG_VIEW == 1
    outColor = vec4(zephyr_linearToSrgb(clamp(texture(colortex0, texCoord).rgb, 0.0, 1.0)), 1.0);
    return;
#elif DEBUG_VIEW == 2
    outColor = vec4(texture(colortex2, texCoord).rgb, 1.0);
    return;
#elif DEBUG_VIEW == 3
    float d = texture(depthtex0, texCoord).r;
    outColor = vec4(vec3(clamp(zephyr_linearDepth(d) / 256.0, 0.0, 1.0)), 1.0);
    return;
#elif DEBUG_VIEW == 4
    outColor = vec4(vec3(texture(colortex0, texCoord).a * 0.25), 1.0);
    return;
#elif DEBUG_VIEW == 5
    outColor = vec4(zephyr_linearToSrgb(clamp(texture(colortex1, texCoord).rgb, 0.0, 1.0)), 1.0);
    return;
#elif DEBUG_VIEW == 7
    // Probe R = sunAngle, G = world-space sunPosition.y, B = shadowLightPosition.y.
    vec3 dbgSun = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    vec3 dbgLight = normalize(mat3(gbufferModelViewInverse) * normalize(shadowLightPosition));
    outColor = vec4(clamp(vec3(sunAngle, 0.5 + 0.5 * dbgSun.y,
                               0.5 + 0.5 * dbgLight.y), 0.0, 1.0), 1.0);
    return;
#endif

#if DEBUG_FINAL
    outColor = vec4(clamp(hdr, 0.0, 1.0), 1.0);
    return;
#endif

    float averageLuma = max(zephyr_luma(textureLod(colortex3, vec2(0.5), 12.0).rgb), 1e-4);
    float autoEv = clamp(log2(EXPOSURE_TARGET / averageLuma), -2.0, 2.0);
    // Eye adaptation must not cancel the storm darkening: during rain the
    // auto-EV lift is bounded so the overcast never reads as daylight again.
    float storm = clamp(rainStrength, 0.0, 1.0);
    autoEv = mix(autoEv, clamp(autoEv, -2.0, 0.55), storm * 0.45);
    float sunY = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition)).y;
    float nightFactor = 1.0 - zephyr_dayAmount(sunY);
    float rainEv = mix(RAIN_DAY_EV, RAIN_NIGHT_EV, nightFactor);
    float ev = EXPOSURE_EV + autoEv * EXPOSURE_ADAPT_SPEED
             + storm * rainEv;

    vec3 graded = hdr * exp2(ev) * TONEMAP_EXPOSURE_BIAS;
    float l = zephyr_luma(graded);
    graded = mix(vec3(l), graded, GRADE_SATURATION);
    float gradeContrast = GRADE_CONTRAST * (1.0 + storm * RAIN_GRADE_CONTRAST);
    graded = max((graded - 0.18) * gradeContrast + 0.18, vec3(0.0));

    vec3 mapped = zephyr_linearToSrgb(zephyr_aces(graded));
    float dither = (zephyr_hash12(gl_FragCoord.xy + float(frameCounter) * 0.71) - 0.5) / 255.0;
    outColor = vec4(clamp(mapped + dither, 0.0, 1.0), 1.0);
}
