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
float zephyr_shadowBilinear(vec2 uv, float compareDepth, float texel) {
    vec2 pos = uv / texel - 0.5;
    vec2 f = fract(pos);
    vec2 base = (floor(pos) + 0.5) * texel;
    float s0 = step(compareDepth, texture(shadowtex0, base).r);
    float s1 = step(compareDepth, texture(shadowtex0, base + vec2(0.0, texel)).r);
    float s2 = step(compareDepth, texture(shadowtex0, base + vec2(texel, 0.0)).r);
    float s3 = step(compareDepth, texture(shadowtex0, base + vec2(texel, texel)).r);
    return mix(mix(s0, s1, f.y), mix(s2, s3, f.y), f.x);
}

float zephyr_shadowVisibility(vec3 viewPos, vec3 viewNormal, vec3 lightDirView) {
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
        return 1.0;
    }

    float texel = 1.0 / float(max(textureSize(shadowtex0, 0).x, 1));
    float compareDepth = shadowCoord.z - SHADOW_BIAS * slope;
    float radius = texel * SHADOW_SOFTNESS;

    // Vogel disk with a per-frame rotation; the existing TAA resolves the
    // remaining sample noise into a smooth penumbra.
    float dither = zephyr_hash12(gl_FragCoord.xy + float(frameCounter) * 0.71);
    float sum = 0.0;
    for (int i = 0; i < SHADOW_PCF_SAMPLES; ++i) {
        float fi = float(i);
        float ang = fi * 2.3999632 + dither * 6.2831853;
        float r = sqrt((fi + 0.5) / float(SHADOW_PCF_SAMPLES));
        vec2 offset = vec2(cos(ang), sin(ang)) * r * radius;
        sum += zephyr_shadowBilinear(shadowCoord.xy + offset, compareDepth, texel);
    }
    float visibility = sum / float(SHADOW_PCF_SAMPLES);

    // Fade at the shadow-map border instead of a hard lit/unlit seam.
    vec2 edge = abs(shadowCoord.xy * 2.0 - 1.0);
    float fade = 1.0 - smoothstep(SHADOW_EDGE_FADE, 1.0, max(edge.x, edge.y));
    return mix(1.0, visibility, fade);
#else
    return 1.0;
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
    float matId = albedoData.a;
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
        float vis = zephyr_shadowVisibility(debugViewPos, viewNormal, lightDirView);
        outColor = vec4(vec3(vis), 1.0);
    } else {
        outColor = vec4(0.0, 0.0, 0.0, 1.0);
    }
    return;
#endif

    vec3 color;

    if (depth >= 0.9999) {
        color = zephyr_atmosphere(zephyr_worldRay(texCoord), sunDirWorld, dayAmount, rain);
    } else {
        vec3 viewPos = zephyr_viewPos(texCoord, depth);
        vec3 V = normalize(-viewPos);
        vec3 N = viewNormal;
        vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
        vec3 Nw = normalize(mat3(gbufferModelViewInverse) * viewNormal);
        float isWater = (matId > 0.5 && matId < 1.5) ? 1.0 : 0.0;
        float puddle = zephyr_puddleMask(worldPos, Nw, skyLight, rain) * (1.0 - isWater);

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

        float visibility = zephyr_shadowVisibility(viewPos, N, L);

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
        vec3 specular = zephyr_D_GGX(NoH, a) * zephyr_G_Smith(NoV, NoL, a)
                      * zephyr_F_Schlick(f0, VoH) / max(4.0 * NoV * NoL, 1e-4);
        vec3 diffuse = albedo * (1.0 - f0) / ZEPHYR_PI;
        vec3 direct = (diffuse + specular) * sunRadiance * NoL * visibility;

        vec3 indirect = albedo * (skyAmbient * (0.30 + 0.70 * skyLight) + blockRadiance);

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

        if (normalData.a > 0.5) {
            float back = max(dot(-N, L), 0.0);
            indirect += albedo * sunRadiance * pow(back, 1.5)
                      * FOLIAGE_TRANSLUCENCY * visibility;
        }

        if (matId > 0.5 && matId < 1.5) {
            float t = weatherTime;
            // Rain roughens the surface with small ripples and lifts reflection.
            float waveAmp = WAVE_AMPLITUDE * (1.0 + rain * 0.90);
            float wx = sin(worldPos.x * 0.85 + t * 1.25) * cos(worldPos.z * 0.62 - t * 0.85);
            float wz = sin(worldPos.z * 1.05 - t * 1.45) * cos(worldPos.x * 0.55 + t * 0.75);
            vec3 waveN = normalize(mat3(gbufferModelView) * vec3(wx * waveAmp, 1.0, wz * waveAmp));
            float fresnel = WATER_F0 + (1.0 - WATER_F0)
                          * pow(clamp(1.0 - max(dot(V, waveN), 0.0), 0.0, 1.0), 5.0);
            fresnel = clamp(fresnel + rain * 0.12, 0.0, 1.0);
            vec3 worldRay = normalize(mat3(gbufferModelViewInverse) * (-V));
            vec3 reflectDir = reflect(worldRay, normalize(vec3(wx, 1.0, wz) * waveAmp + vec3(0.0, 1.0, 0.0)));
            vec3 reflection = zephyr_atmosphere(reflectDir, sunDirWorld, dayAmount, rain);
            vec3 underwater = albedo * vec3(0.06, 0.26, 0.32) * (skyAmbient + blockRadiance)
                            * WATER_ABSORPTION * 4.0;
            color = mix(underwater, reflection, clamp(fresnel, 0.0, 1.0));
            color += direct * 0.20;
        } else {
#if AO_ENABLED
            // Fixed spatial jitter (see zephyr_ssao) already removes temporal
            // shimmer without a history buffer or ghosting risk.
            float ao = zephyr_ssao(texCoord, viewPos, N);
            color = direct * mix(1.0, ao, 0.35) + indirect * ao;
#else
            color = direct + indirect;
#endif
        }

        if (matId > 3.5) {
            color = albedo;
        }
    }

    outColor = vec4(clamp(color, 0.0, 65504.0), 1.0);
}
