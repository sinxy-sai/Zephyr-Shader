#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

in vec2 texCoord;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

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

float zephyr_shadowVisibility(vec3 viewPos, vec3 viewNormal, vec3 lightDirView) {
#if SHADOW_ENABLED
    vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec4 shadowClip = shadowProjection * shadowModelView * vec4(worldPos, 1.0);
    float w = abs(shadowClip.w) < 1e-5 ? 1e-5 : shadowClip.w;
    vec3 shadowCoord = shadowClip.xyz / w * 0.5 + 0.5;

    if (shadowCoord.x < 0.0 || shadowCoord.x > 1.0 ||
        shadowCoord.y < 0.0 || shadowCoord.y > 1.0 ||
        shadowCoord.z > 1.0 || shadowCoord.z < 0.0) {
        return 1.0;
    }

    float NoL = clamp(dot(viewNormal, lightDirView), 0.0, 1.0);
    float bias = SHADOW_BIAS * (1.0 + 3.0 * (1.0 - NoL));
    vec2 texel = 1.0 / vec2(max(textureSize(shadowtex0, 0), ivec2(1)));
    vec2 radius = texel * SHADOW_SOFTNESS;

    float sum = 0.0;
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            vec2 offset = vec2(float(x), float(y)) * radius;
            float closest = texture(shadowtex0, shadowCoord.xy + offset).r;
            sum += step(shadowCoord.z - bias, closest);
        }
    }
    return clamp(sum / 9.0, 0.0, 1.0);
#else
    return 1.0;
#endif
}

#if AO_ENABLED
// Lightweight contact AO: a few hemisphere samples projected back to the depth
// buffer. Only indirect light is fully occluded; direct light keeps a fraction.
float zephyr_ssao(vec2 uv, vec3 viewPos, vec3 N) {
    float noise = zephyr_hash12(gl_FragCoord.xy + float(frameCounter) * 0.37);
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
        vec3 blockRadiance = vec3(1.00, 0.58, 0.26) * pow(blockLight, 2.0) * 1.8;

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
