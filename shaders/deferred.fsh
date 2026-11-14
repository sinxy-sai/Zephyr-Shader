#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

in vec2 texCoord;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
#if TEMPORAL_AO_ENABLED
uniform sampler2D colortex6;   // M7 history, only bound when the path is enabled
#endif
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;   // M12: transmitted colour of translucent casters
uniform sampler2D colortex8;      // M34: pane transmitted colour for glass SSS

// M7: change to "3,6" and re-add layout(location=1) out vec4 outHistory when
// the temporal path is enabled (see shaders.properties for the full checklist).
/* RENDERTARGETS: 3 */
layout(location = 0) out vec4 outColor;

vec3 zephyr_viewPos(vec2 uv, float depth) {
    vec4 clip = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    float w = abs(clip.w) < 1e-5 ? 1e-5 : clip.w;
    return clip.xyz / w;
}

vec3 zephyr_worldRay(vec2 uv) {
    vec4 clip = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    float w = abs(clip.w) < 1e-5 ? 1e-5 : clip.w;
    vec3 viewDir = normalize(clip.xyz / w);
    return normalize(mat3(gbufferModelViewInverse) * viewDir);
}

// Manual 2x2 bilinear PCF. A raw step() per tap only yields a handful of
// discrete grey levels, which reads as thick concentric bands in a close-up.
// Four comparisons plus bilinear weights give a continuous penumbra.
float zephyr_shadowBilinear(sampler2D shadowMap, vec2 uv, float compareDepth, float texel) {
    vec2 pos = uv / texel - 0.5;
    vec2 f = fract(pos);
    vec2 base = (floor(pos) + 0.5) * texel;
    float s0 = step(compareDepth, texture(shadowMap, base).r);
    float s1 = step(compareDepth, texture(shadowMap, base + vec2(0.0, texel)).r);
    float s2 = step(compareDepth, texture(shadowMap, base + vec2(texel, 0.0)).r);
    float s3 = step(compareDepth, texture(shadowMap, base + vec2(texel, texel)).r);
    return mix(mix(s0, s1, f.y), mix(s2, s3, f.y), f.x);
}

// M12: vec3 transmittance instead of a scalar visibility.
//   s0 = shadowtex0 (all casters), s1 = shadowtex1 (opaque only),
//   c  = shadowcolor0 (transmitted colour of the translucent caster).
// T = s0 + c * s1 * (1 - s0): 1 unoccluded, 0 behind opaque geometry,
// c behind glass / water. Complementary / BSL / iterationT use this form.
vec3 zephyr_shadowTransmittance(vec3 viewPos, vec3 viewNormal, vec3 lightDirView) {
#if SHADOW_ENABLED
    float NoL = clamp(dot(viewNormal, lightDirView), 0.0, 1.0);
    float slope = 1.0 + 2.0 * (1.0 - NoL);

    vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * viewNormal);
    // Normal offset kills acne without the peter-panning of a pure depth bias.
    vec3 lookupPos = worldPos + worldNormal * (SHADOW_NORMAL_OFFSET * slope);

    vec4 shadowClip = shadowProjection * shadowModelView * vec4(lookupPos, 1.0);
    float w = abs(shadowClip.w) < 1e-5 ? 1e-5 : shadowClip.w;
    vec3 shadowCoord = shadowClip.xyz / w * 0.5 + 0.5;

    if (shadowCoord.x < 0.0 || shadowCoord.x > 1.0 ||
        shadowCoord.y < 0.0 || shadowCoord.y > 1.0 ||
        shadowCoord.z > 1.0 || shadowCoord.z < 0.0) {
        return vec3(1.0);
    }

    float texel = 1.0 / float(max(textureSize(shadowtex0, 0).x, 1));
    float compareDepth = shadowCoord.z - SHADOW_BIAS * slope;
    float radius = texel * SHADOW_SOFTNESS;

    // Spatially fixed Vogel rotation. A frameCounter term re-rolls all six
    // shadow taps every frame - a per-frame noise source TAA never fully
    // converges on. AO and volumetric light already use fixed spatial jitter
    // for exactly this reason; TAA's own sub-pixel projection jitter supplies
    // the temporal sampling for the remaining penumbra noise.
    float dither = zephyr_hash12(gl_FragCoord.xy);
    // Both maps must use the exact same taps: subtracting a single-tap sample
    // from a 6-tap PCF result would make every penumbra edge look like a
    // translucent caster and silently soften all shadows.
    float sumAll = 0.0;
    float sumOpaque = 0.0;
    for (int i = 0; i < SHADOW_PCF_SAMPLES; ++i) {
        float fi = float(i);
        float ang = fi * 2.3999632 + dither * 6.2831853;
        float r = sqrt((fi + 0.5) / float(SHADOW_PCF_SAMPLES));
        vec2 sampleUv = shadowCoord.xy + vec2(cos(ang), sin(ang)) * r * radius;
        sumAll    += zephyr_shadowBilinear(shadowtex0, sampleUv, compareDepth, texel);
        sumOpaque += zephyr_shadowBilinear(shadowtex1, sampleUv, compareDepth, texel);
    }
    float s0 = sumAll / float(SHADOW_PCF_SAMPLES);
    float s1 = sumOpaque / float(SHADOW_PCF_SAMPLES);

    // shadowcolor0 is written sRGB-encoded by shadow.fsh for 8-bit precision.
    vec3 transmitted = zephyr_srgbToLinear(
        clamp(texture(shadowcolor0, shadowCoord.xy).rgb, 0.0, 1.0));
    // SHADOW_COLOR_STRENGTH = 0 restores M11: a flat grey lift of
    // TRANSLUCENT_SHADOW_LIFT with no colour. 1 is fully coloured.
    vec3 tint = mix(vec3(TRANSLUCENT_SHADOW_LIFT), transmitted,
                    SHADOW_COLOR_STRENGTH);
    vec3 transmittance = clamp(vec3(s0) + tint * s1 * (1.0 - s0), 0.0, 1.0);

    // Fade at the shadow-map border instead of a hard lit/unlit seam.
    vec2 edge = abs(shadowCoord.xy * 2.0 - 1.0);
    float fade = 1.0 - smoothstep(SHADOW_EDGE_FADE, 1.0, max(edge.x, edge.y));
    return mix(vec3(1.0), transmittance, fade);
#else
    return vec3(1.0);
#endif
}

#if AO_ENABLED
// Lightweight contact AO: a few hemisphere samples projected back to the depth
// buffer. Only indirect light is fully occluded; direct light keeps a fraction.
float zephyr_ssao(vec2 uv, vec3 viewPos, vec3 N) {
    // Fixed spatial jitter, not a per-frame one: temporal jitter was the only
    // source of AO shimmer, and the M7 history path did not reduce it reliably
    // on this Iris build. A stable pattern is cheaper and ghost-free.
    float noise = zephyr_hash12(gl_FragCoord.xy);
    float occlusion = 0.0;
    for (int i = 0; i < AO_SAMPLES; ++i) {
        float fi = float(i);
        float ang = fi * 2.3999632 + noise * 6.2831853;
        float rad = AO_RADIUS * (0.25 + 0.75 * sqrt((fi + 0.5) / float(AO_SAMPLES)));
        vec3 offset = vec3(cos(ang) * rad, sin(ang) * rad,
                           (noise - 0.5) * AO_RADIUS * 0.5);
        if (dot(offset, N) < 0.0) offset = -offset;
        vec3 s = viewPos + offset + N * 0.03;
        vec4 clip = gbufferProjection * vec4(s, 1.0);
        if (abs(clip.w) < 1e-5) continue;
        vec2 suv = clip.xy / clip.w * 0.5 + 0.5;
        if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) continue;
        float sd = texture(depthtex0, suv).r;
        if (sd >= 0.9999) continue;
        float diff = (-s.z) - zephyr_linearDepth(sd);
        occlusion += smoothstep(0.0, AO_RADIUS * 0.8, diff) * step(0.0, diff);
    }
    return clamp(1.0 - occlusion / float(AO_SAMPLES) * AO_STRENGTH, 0.35, 1.0);
}
#endif

// M7: reconstruct this pixel's position in the previous frame.
// gbufferModelViewInverse yields camera-relative "scene space", so the camera's
// own motion must be compensated with cameraPosition - previousCameraPosition.
vec2 zephyr_reproject(vec2 uv, float depth) {
    vec4 view = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    float w = abs(view.w) < 1e-5 ? 1e-5 : view.w;
    vec3 scenePos = (gbufferModelViewInverse * vec4(view.xyz / w, 1.0)).xyz;
    vec3 cameraOffset = cameraPosition - previousCameraPosition;
    vec4 prev = gbufferPreviousProjection * gbufferPreviousModelView
              * vec4(scenePos + cameraOffset, 1.0);
    if (prev.w <= 0.0) return vec2(-1.0);
    return prev.xy / prev.w * 0.5 + 0.5;
}

#if AO_ENABLED && TEMPORAL_AO_ENABLED
// M7 skeleton: temporally accumulated AO; returns (ao, age) so both can be
// stored in the history buffer. Ghosting is controlled by four independent
// rejections: screen bounds, depth disocclusion, camera velocity, and clamping
// history into the current frame's AO neighbourhood.
// Compiled out while TEMPORAL_AO_ENABLED=0 (see 06-eval.md M7 for why).
vec2 zephyr_temporalAO(vec2 uv, float depth, vec3 viewPos, vec3 N) {
    float ao = zephyr_ssao(uv, viewPos, N);
    float linearDepth = zephyr_linearDepth(depth);
    float age = 0.0;
    vec2 prevUv = zephyr_reproject(uv, depth);
    if (prevUv.x > 0.0 && prevUv.x < 1.0 && prevUv.y > 0.0 && prevUv.y < 1.0) {
        vec4 history = texture(colortex6, prevUv);
        float depthWeight = exp2(-abs(linearDepth - history.g) * TEMPORAL_AO_DEPTH_REJECT);
        float velocityPx = length(prevUv - uv) * max(viewWidth, viewHeight);
        float velocityWeight = exp2(-velocityPx * TEMPORAL_AO_VELOCITY);
        float histAge = clamp(history.b, 0.0, TEMPORAL_AO_MAX_AGE)
                      * depthWeight * velocityWeight;
        float histAO = clamp(history.r, ao - TEMPORAL_AO_CLAMP, ao + TEMPORAL_AO_CLAMP);
        ao = mix(ao, histAO, histAge / (histAge + 1.0));
        age = min(histAge + 1.0, TEMPORAL_AO_MAX_AGE);
    }
    return vec2(clamp(ao, 0.35, 1.0), age);
}
#endif

void main() {
    vec4 albedoData = texture(colortex0, texCoord);
    vec4 lightData = texture(colortex1, texCoord);
    vec4 normalData = texture(colortex2, texCoord);
    float depth = texture(depthtex0, texCoord).r;

    vec3 albedo = max(albedoData.rgb, vec3(0.0));
    float matId = lightData.a;
    vec3 viewNormal = zephyr_decodeNormal(normalData.rgb);
    float roughness = clamp(lightData.b, 0.03, 1.0);
    float blockLight = clamp(lightData.r, 0.0, 1.0);
    float skyLight = clamp(lightData.g, 0.0, 1.0);

    vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    vec3 lightDirView = normalize(shadowLightPosition);
    float dayAmount = zephyr_dayAmount(sunDirWorld.y);
    float rain = clamp(rainStrength, 0.0, 1.0);

#if DEBUG_VIEW == 6
    if (depth < 0.9999) {
        vec3 debugViewPos = zephyr_viewPos(texCoord, depth);
        outColor = vec4(zephyr_shadowTransmittance(debugViewPos, viewNormal,
                                                   lightDirView), 1.0);
    } else {
        outColor = vec4(0.0, 0.0, 0.0, 1.0);
    }
    return;
#endif
#if DEBUG_VIEW == 8
    // Raw depth difference between the two shadow maps. Any lit pixel means a
    // caster exists in shadowtex0 but not in shadowtex1 (translucent caster).
    if (depth < 0.9999) {
        vec3 dbgViewPos = zephyr_viewPos(texCoord, depth);
        vec3 dbgWorld = (gbufferModelViewInverse * vec4(dbgViewPos, 1.0)).xyz;
        vec4 dbgClip = shadowProjection * shadowModelView * vec4(dbgWorld, 1.0);
        vec3 dbgCoord = dbgClip.xyz / dbgClip.w * 0.5 + 0.5;
        if (dbgCoord.x < 0.0 || dbgCoord.x > 1.0 ||
            dbgCoord.y < 0.0 || dbgCoord.y > 1.0 ||
            dbgCoord.z < 0.0 || dbgCoord.z > 1.0) {
            outColor = vec4(0.0, 0.0, 0.0, 1.0);
        } else {
            float d0 = texture(shadowtex0, dbgCoord.xy).r;
            float d1 = texture(shadowtex1, dbgCoord.xy).r;
            outColor = vec4(vec3(clamp(abs(d1 - d0) * 60.0, 0.0, 1.0)), 1.0);
        }
    } else {
        outColor = vec4(0.0, 0.0, 0.0, 1.0);
    }
    return;
#endif

    vec3 color;

    if (depth >= 0.9999) {
        vec3 skyRay = zephyr_worldRay(texCoord);
        color = zephyr_atmosphere(skyRay, sunDirWorld, dayAmount, rain);
#if NIGHT_SKY_ENABLED
        // M28: stars / moon / night gradient belong to SKY pixels only.
        // Adding them inside zephyr_atmosphere would put stars into fog,
        // clouds and water reflections too.
        color += zephyr_nightSky(skyRay, sunDirWorld, dayAmount, rain);
#endif
    } else {
        vec3 viewPos = zephyr_viewPos(texCoord, depth);
        vec3 V = normalize(-viewPos);
        vec3 N = viewNormal;
        float isThin = (normalData.a > 0.5) ? 1.0 : 0.0;
        // M30: leaves are thin double-sided laminae. A back-facing texel must
        // be shaded from the side the viewer actually sees, otherwise the
        // inside of a canopy collapses to black.
        if (isThin > 0.5 && dot(N, V) < 0.0) N = -N;
        vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
        vec3 Nw = normalize(mat3(gbufferModelViewInverse) * N);
        float isWater = (matId > 0.5 && matId < 1.5) ? 1.0 : 0.0;
        // M22: MAT_HAND marks first-person geometry. Iris renders it with its
        // OWN modelview/projection, so worldPos / Nw reconstructed from the
        // scene matrices are not meaningful for it. Give it a dedicated path
        // instead of letting it inherit bogus shadows, puddles and SSAO.
        float isHand = (matId > 2.5 && matId < 3.5) ? 1.0 : 0.0;
        float puddle = zephyr_puddleMask(worldPos, Nw, skyLight, rain)
                     * (1.0 - isWater) * (1.0 - isHand);

        // Rain ripples slightly tilt the shading normal inside puddles.
        float weatherTime = frameTimeCounter;
        float ripple = sin(worldPos.x * 3.3 + weatherTime * 5.0)
                     * sin(worldPos.z * 2.9 - weatherTime * 4.1);
        N = normalize(N + vec3(ripple, 0.0, ripple * 0.7) * PUDDLE_RIPPLE * puddle);

        vec3 L = lightDirView;
        vec3 H = normalize(L + V);

        float NoL = max(dot(N, L), 0.0);
        float NoV = max(dot(N, V), 1e-4);
        float NoH = max(dot(N, H), 0.0);
        float VoH = max(dot(V, H), 0.0);

        vec3 shadowTrans = zephyr_shadowTransmittance(viewPos, N, L);
        // Moonlight casts soft, shallow shadows: a full-strength daylight
        // shadow at night reads as an unnatural black cutout.
        float nightAmount = 1.0 - dayAmount;
        shadowTrans = mix(vec3(1.0), shadowTrans,
                          mix(NIGHT_SHADOW_MIN, 1.0, dayAmount));
        // M22: held geometry has no valid shadow-space position; projecting it
        // into the scene shadowmap produced random dark patches. It is lit by
        // the sun term plus the dynamic held light instead.
        shadowTrans = mix(shadowTrans, vec3(1.0), isHand);

        float warm = zephyr_warmMix(sunDirWorld.y);
        vec3 sunNoon = vec3(1.15, 1.05, 0.92);
        vec3 sunWarm = vec3(1.45, 0.68, 0.30);
        vec3 skyNoon = vec3(0.44, 0.58, 0.82);
        vec3 skyWarm = vec3(0.52, 0.34, 0.28);
        vec3 sunRadiance = mix(vec3(0.09, 0.12, 0.22), mix(sunWarm, sunNoon, warm), dayAmount)
                         * LIGHT_SUN_INTENSITY;
        vec3 skyAmbient = mix(vec3(0.020, 0.030, 0.055), mix(skyWarm, skyNoon, warm), dayAmount)
                        * LIGHT_SKY_INTENSITY;
        // Overcast: direct sun collapses, ambient skylight turns cool and dim.
        sunRadiance *= mix(1.0, 0.45, rain);
        skyAmbient *= mix(1.0, 0.82, rain);
        skyAmbient = mix(skyAmbient, skyAmbient * vec3(0.72, 0.80, 1.00), rain * 0.70);
        // Storm nights: the overcast deck scatters moon/city light back down,
        // so outdoor surfaces keep their shape instead of crushing to black.
        float stormNight = rain * (1.0 - dayAmount);
        skyAmbient += vec3(0.62, 0.72, 1.00) * STORM_NIGHT_BOUNCE
                    * stormNight * LIGHT_SKY_INTENSITY;
        // Night sky glow / city bounce: an ambient floor so shadowed albedo
        // survives exposure and tonemapping instead of crushing to black.
        skyAmbient += vec3(0.62, 0.72, 1.00) * NIGHT_AMBIENT_FLOOR * nightAmount;
        vec3 blockRadiance = vec3(1.00, 0.58, 0.26) * pow(blockLight, 2.0) * 1.8
                           * (1.0 + rain * 0.45);

        // Wet surfaces: tighter GGX lobe and a higher F0 give the slick,
        // reflective look of rain-soaked pavement and leaves.
        float wet = rain * (1.0 - isWater);
        float wetRoughness = mix(roughness, roughness * 0.35, wet);
        wetRoughness = mix(wetRoughness, PUDDLE_ROUGHNESS, puddle);
        float a = max(wetRoughness * wetRoughness, 0.002);
        vec3 f0 = mix(vec3(0.04), vec3(0.075), wet);
        f0 = mix(f0, vec3(0.09), puddle);
        albedo *= 1.0 - 0.30 * puddle;
#if LEAF_SSS_ENABLED
        // M30: push leaf albedo toward a vivid but luminance-neutral green.
        // Keeping luma constant avoids an artificial brightness lift.
        if (isThin > 0.5 && matId < 0.5) {
            float leafLuma = zephyr_luma(albedo);
            vec3 vivid = albedo * vec3(1.0 - 0.20 * LEAF_VITALITY,
                                       1.0 + 0.16 * LEAF_VITALITY,
                                       1.0 - 0.22 * LEAF_VITALITY);
            albedo = vivid * (leafLuma / max(zephyr_luma(vivid), 1e-4));
        }
#endif
        vec3 specular = zephyr_D_GGX(NoH, a) * zephyr_G_Smith(NoV, NoL, a)
                      * zephyr_F_Schlick(f0, VoH) / max(4.0 * NoV * NoL, 1e-4);
        vec3 diffuse = albedo * (1.0 - f0) / ZEPHYR_PI;
        vec3 direct = (diffuse + specular) * sunRadiance * NoL * shadowTrans;
#if LEAF_SSS_ENABLED
        // M30: waxy cuticle highlight - a narrow lobe, not the broad GGX used
        // for wet pavement. This is what makes sunlit leaves look alive.
        if (isThin > 0.5 && matId < 0.5) {
            direct += sunRadiance * shadowTrans
                    * pow(NoH, LEAF_SPEC_POWER) * LEAF_SPECULAR
                    * (1.0 - rain * 0.40);
        }
#endif

        vec3 indirect = albedo * (skyAmbient * (0.30 + 0.70 * skyLight) + blockRadiance);

#if HAND_LIGHT_ENABLED
        // M22: dynamic held-item light. Iris exposes the held block-light level
        // (0..15) for both hands; the max acts as a warm point light just above
        // the camera (Complementary / BSL use the same uniform). Added here in
        // deferred so it flows through fog, bloom, TAA and the tonemapper.
        float heldLight = max(float(heldBlockLightValue),
                              float(heldBlockLightValue2));
        if (heldLight > 0.0) {
            vec3 toLight = cameraPosition
                         + vec3(0.0, HAND_LIGHT_HEIGHT, 0.0) - worldPos;
            // Held geometry's world position is unreliable (see isHand), so
            // give it a fixed near distance and use view-space normals.
            float d2 = mix(dot(toLight, toLight), 0.25, isHand);
            float r2 = HAND_LIGHT_RADIUS * HAND_LIGHT_RADIUS;
            float atten = 1.0 / (1.0 + d2 / r2);
            atten *= atten;
            float NoLh = isHand > 0.5
                       ? max(dot(viewNormal, V), 0.0)
                       : max(dot(Nw, normalize(toLight + vec3(0.0, 0.001, 0.0))), 0.0);
            vec3 heldRadiance = HAND_LIGHT_COLOR
                              * clamp(heldLight / 15.0, 0.0, 1.0)
                              * HAND_LIGHT_INTENSITY * atten
                              * (0.40 + 0.60 * NoLh);
            indirect += albedo * heldRadiance;
        }
#endif

#if LIGHTNING_ENABLED
        float bolt = zephyr_lightning();
        if (bolt > 0.001) {
            vec3 toBolt = worldPos - lightningBoltPosition.xyz;
            float atten = 1.0 / (1.0 + dot(toBolt, toBolt) * 0.00002);
            vec3 boltLight = vec3(0.70, 0.80, 1.00) * bolt
                           * LIGHTNING_INTENSITY * atten;
            indirect += albedo * boltLight * (0.20 + 0.80 * skyLight);
        }
#endif

#if LEAF_SSS_ENABLED
        if (isThin > 0.5 && matId < 0.5) {
            // M30: thin-leaf subsurface transmission.
            // VoL peaks when the viewer looks toward the light THROUGH the
            // leaf; wrapped back-lighting keeps the canopy from going black.
            float VoL = clamp(dot(-V, L) * 0.5 + 0.5, 0.0, 1.0);
            float forward = pow(VoL, LEAF_FORWARD_POWER);
            float back = max(dot(-N, L), 0.0);
            float wrapped = mix(back, 1.0, LEAF_WRAP);
            vec3 spectral = mix(vec3(1.0), LEAF_CHLOROPHYLL,
                                LEAF_SPECTRAL_MIX);
            vec3 transmitted = sunRadiance * spectral * shadowTrans
                             * (LEAF_TRANSMISSION * wrapped
                                + LEAF_FORWARD_GAIN * forward)
                             * (1.0 - rain * LEAF_RAIN_DAMPEN);
            indirect += albedo * transmitted;
        }
#else
        if (normalData.a > 0.5) {
            float back = max(dot(-N, L), 0.0);
            indirect += albedo * sunRadiance * pow(back, 1.5)
                      * FOLIAGE_TRANSLUCENCY * shadowTrans;
        }
#endif

#if GLASS_SSS_ENABLED
        // M34: backlit glass scatters light in ITS OWN colour. Low-chroma
        // panes only receive a faint neutral glow; the vivid green boost
        // above is now restricted to real foliage by matId + isFoliage.
        if (matId > 1.5 && matId < 2.5) {
            vec3 paneCol = max(texture(colortex8, texCoord).rgb,
                               vec3(0.0));
            float cMax = max(paneCol.r, max(paneCol.g, paneCol.b));
            float cMin = min(paneCol.r, min(paneCol.g, paneCol.b));
            float chroma = cMax - cMin;
            float tinted = smoothstep(GLASS_SSS_CHROMA_MIN,
                                      GLASS_SSS_CHROMA_MAX, chroma);
            vec3 tint = mix(vec3(1.0), paneCol / max(cMax, 1e-4),
                            tinted);
            float VoL = clamp(dot(-V, L) * 0.5 + 0.5, 0.0, 1.0);
            // A tight VoL lobe only lights up when looking straight at the
            // sun through a pane; keep a scatter floor so everyday viewing
            // angles still show a hint of transmitted colour (M34).
            float forward = 0.28 + 0.72 * pow(VoL, GLASS_SSS_POWER);
            float strength = mix(GLASS_SSS_NEUTRAL, 1.0, tinted);
            indirect += albedo * tint * sunRadiance * forward
                      * GLASS_SSS_STRENGTH * strength * shadowTrans
                      * (1.0 - rain * 0.35)
                      * (0.30 + 0.70 * dayAmount);
        }
#endif

        if (matId > 0.5 && matId < 1.5) {
            float t = weatherTime;
            // Rain roughens the surface with small ripples and lifts reflection.
            // M43: zephyr_waterWaveSlope() ALREADY multiplies
            // WATER_WAVE_STRENGTH. The extra * waveAmp (WAVE_AMPLITUDE=0.08)
            // compressed the normal back to ~2 degrees, so the surface behaved
            // like a flat mirror (waves A/B measured 0.90 vs noise 1.50).
            vec2 slope = zephyr_waterWaveSlope(worldPos, t)
                       * (1.0 + rain * 0.90);
#if WATER_WAVE_ENABLED
            vec3 waveNw = normalize(vec3(-slope.x, 1.0, -slope.y));
#else
            float wx = sin(worldPos.x * 0.85 + t * 1.25) * cos(worldPos.z * 0.62 - t * 0.85);
            float wz = sin(worldPos.z * 1.05 - t * 1.45) * cos(worldPos.x * 0.55 + t * 0.75);
            vec3 waveNw = normalize(vec3(wx, 1.0, wz));
            slope = vec2(wx, wz) * 0.0;
#endif
            vec3 waveN = normalize(mat3(gbufferModelView) * waveNw);
            float fresnel = WATER_F0 + (1.0 - WATER_F0)
                          * pow(clamp(1.0 - max(dot(V, waveN), 0.0), 0.0, 1.0), 5.0);
            fresnel = clamp(fresnel + rain * 0.12, 0.0, 1.0);
            vec3 worldRay = normalize(mat3(gbufferModelViewInverse) * (-V));
            // Old expression collapsed to ~vec3(0,1,0) and produced an almost
            // flat sky reflection; use the real world-space wave normal.
            vec3 reflectDir = reflect(worldRay, waveNw);
            vec3 reflection = zephyr_atmosphere(reflectDir, sunDirWorld, dayAmount, rain);
            // M35: water reflects the same analytic atmosphere as the fog.
            // A cool tint plus a facet term driven by the wave slope keeps
            // the surface distinguishable from the sky it reflects.
            reflection *= WATER_REFLECT_TINT;
            float facet = clamp(1.0 + (slope.x + slope.y)
                                * WATER_REFLECT_FACET * 8.0,
                                0.62, 1.40);
            reflection *= facet;
#if WATER_VOLUME_ENABLED
            // M49: seen from BELOW, the surface must not mirror the sky.
            // Beyond the critical angle a water/air interface is total
            // internal reflection, so it shows the water body itself. Without
            // this the sky reflected by zephyr_atmosphere() was visible from
            // underwater, which read as "the water has disappeared".
            if (isEyeInWater == 1) {
                vec3 underMirror = WATER_SCATTER_RGB
                                 * (skyAmbient + blockRadiance)
                                 * WATER_INSCATTER * 0.45;
                reflection = mix(reflection, underMirror, 0.92);
            }
#endif
#if WATER_VOLUME_ENABLED
            // M31: Beer-Lambert slant-path absorption. A grazing view travels
            // further through the water, so red is removed first and the body
            // turns cyan-green; a near-vertical view stays translucent.
            // Replaces the old flat albedo * vec3(0.06,0.26,0.32) tint.
            float cosView = clamp(dot(V, waveN), 0.0, 1.0);
            float opticalPath = WATER_SURFACE_PATH / max(cosView, 0.18);
            vec3 trans = exp(-WATER_ABSORB_RGB * opticalPath);
            vec3 ambientWater = skyAmbient + blockRadiance;
            vec3 body = WATER_SCATTER_RGB * (1.0 - trans)
                      * WATER_INSCATTER * WATER_BODY_SCATTER
                      + albedo * trans * WATER_BODY_ALBEDO;
            vec3 underwater = body * ambientWater * WATER_ABSORPTION * 4.0;
#if WATER_SSS_ENABLED
            // M35: subsurface scattering in the water body. Light that enters
            // the surface is scattered back out with the water's cyan-green
            // colour. The slant path makes grazing views glow, and the VoL
            // lobe adds the bright rim when looking toward the sun.
            float VoL = clamp(dot(-V, L) * 0.5 + 0.5, 0.0, 1.0);
            float sssPath = WATER_SSS_DEPTH / max(cosView, 0.18);
            vec3 sssTrans = exp(-WATER_ABSORB_RGB * sssPath);
            vec3 sssLight = WATER_SCATTER_RGB * (1.0 - sssTrans)
                          * (0.35 + 0.65 * pow(VoL, WATER_SSS_PHASE))
                          * WATER_SSS_STRENGTH * sunRadiance
                          * (0.35 + 0.65 * dayAmount)
                          * shadowTrans * (1.0 - rain * 0.40);
            underwater += sssLight;
#endif
#if WATER_PARTICLE_ENABLED
            // Motes a short distance below the surface stay visible when the
            // camera is above water, so the volume reads from the shore too.
            float surfaceMotes = 0.0;
            for (int i = 0; i < 3; ++i) {
                surfaceMotes += zephyr_waterMote(worldPos
                    + vec3(0.0, -0.30 - float(i) * 0.45, 0.0), worldRay);
            }
            // M33: at night the surface motes share the same faint
            // cyan-green bioluminescent tint as the underwater volume.
            float nightGlow = 1.0 - dayAmount;
            vec3 moteTint = mix(WATER_PARTICLE_COLOR,
                                WATER_PARTICLE_GLOW_COLOR,
                                nightGlow * WATER_PARTICLE_NIGHT_GLOW);
            underwater += moteTint * trans * surfaceMotes
                        * WATER_PARTICLE_BRIGHTNESS * 0.16
                        * (1.0 + nightGlow * WATER_PARTICLE_NIGHT_BOOST)
                        * (0.30 + 0.70 * dayAmount);
#endif
#else
            vec3 underwater = albedo * vec3(0.06, 0.26, 0.32) * (skyAmbient + blockRadiance)
                            * WATER_ABSORPTION * 4.0;
#endif
            // M49: seen from below, the surface colour must be the DARK body
            // tint. The above-water formula multiplies by WATER_ABSORPTION*4
            // and mixes in the water texture albedo, which evaluates to about
            // (79,133,199) - i.e. it looked exactly like the blue sky, so the
            // water appeared to "not exist" while underwater.
            if (isEyeInWater == 1) {
                underwater = WATER_SCATTER_RGB * (skyAmbient + blockRadiance)
                           * WATER_INSCATTER * 0.55;
            }
            color = mix(underwater, reflection, clamp(fresnel, 0.0, 1.0));
            color += direct * 0.20;
#if WATER_GLITTER_ENABLED
            // M35: narrow sun glitter. The non-periodic wave normal makes
            // these sparkles scatter across the surface instead of forming
            // a regular grid.
            float glit = pow(max(dot(waveN, H), 0.0),
                             WATER_GLITTER_POWER);
            // M54: seen from below, a sun glitter lobe computed with the
            // UPWARD wave normal is pure speckle on the interface. The
            // underwater composite now shades that interface entirely.
            color += sunRadiance * glit * WATER_GLITTER_STRENGTH
                   * shadowTrans * dayAmount * (1.0 - rain * 0.50)
                   * (isEyeInWater == 1 ? 0.0 : 1.0);
#endif
        } else {
#if AO_ENABLED
            // Fixed spatial jitter (see zephyr_ssao) already removes temporal
            // shimmer without a history buffer or ghosting risk.
            float ao = zephyr_ssao(texCoord, viewPos, N);
            // Contact AO still exists at night but must not double-darken
            // geometry that is already only lit by weak ambient light.
            ao = mix(ao, 1.0, nightAmount * NIGHT_AO_RELAX);
            // M22: SSAO samples a depth neighbourhood that is invalid for the
            // separately-projected first-person geometry.
            ao = mix(ao, 1.0, isHand);
            color = direct * mix(1.0, ao, 0.35) + indirect * ao;
#else
            color = direct + indirect;
#endif
        }

#if CAUSTICS_ENABLED
        // M33: caustics belong on SUBMERGED geometry, not on the water
        // surface itself. This path is the SUBMERGED CAMERA case only.
        // M61: the above-water case lives in composite.fsh's water body,
        // where worldPos is reconstructed from depthtex1 (the real seabed)
        // - see iterationT composite.fsh:158,326-327. Keeping it here too
        // would project a second pattern at WATER SURFACE depth and double
        // the brightness.
        if (isEyeInWater == 1
            && !(matId > 0.5 && matId < 1.5)
            && Nw.y > 0.25
            && length(viewPos) < 28.0) {
            // M62: same time source as the surface waves (M62 common.glsl).
            float caus = zephyr_caustics(worldPos, frameTimeCounter);
            // Underwater lightmap skylight is low by design, so a
            // skyLight-proportional gate would erase the pattern entirely.
            float sunVis = dayAmount * (0.55 + 0.45 * skyLight)
                         * (1.0 - rain * 0.45);
            float reach = 1.0 - smoothstep(14.0, 28.0, length(viewPos));
            color += albedo * sunRadiance * caus * CAUSTICS_STRENGTH
                   * sunVis * shadowTrans * reach;
        }
#endif

        // M27: cap emissive HDR. writeEmissive already multiplied the albedo
        // by EMISSIVE_BLOCK_GAIN; without a cap a placed sea lantern reached
        // ~7 in linear HDR and its bloom halo covered half the street.
        if (matId > 3.5) {
            color = min(albedo, vec3(EMISSIVE_HDR_CAP));
        }

        // M27: a held light emitter keeps its OWN texture colour (a held sea
        // lantern must be cyan-white like a placed one), instead of being
        // tinted by the point light it casts.
#if HAND_LIGHT_ENABLED
        if (isHand > 0.5 && heldLight > 0.0) {
            color = min(albedo * HAND_EMITTER_GAIN, vec3(EMISSIVE_HDR_CAP));
        }
#endif

        // M23/M27: promote light sources NOT covered by the block.12000 ID
        // table (custom map signage) into HDR. Emissive blocks and held
        // emitters are already boosted above - applying this to them too was
        // the double-boost behind the oversized halo.
        if (matId < 3.5 && isHand < 0.5) {
            color += albedo * pow(blockLight, EMISSIVE_LIGHTMAP_POW)
                   * EMISSIVE_LIGHTMAP_GAIN;
        }
    }

    // M15: glass tinting is done ONCE, in final.fsh before tonemapping, using
    // the colortex0.a glass mask. The old matId-based hue multiply here was
    // unreliable (colortex1.a is not trustworthy on translucent pixels) and
    // double-processed the colour, so it was removed.

    outColor = vec4(clamp(color, 0.0, 65504.0), 1.0);
}
