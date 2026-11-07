#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

in vec2 texCoord;

uniform sampler2D colortex3;
uniform sampler2D colortex0;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 outColor;

vec3 zephyr_worldRay(vec2 uv) {
    vec4 clip = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    float w = abs(clip.w) < 1e-5 ? 1e-5 : clip.w;
    return normalize(mat3(gbufferModelViewInverse) * normalize(clip.xyz / w));
}

// Height-resolved cloud density: a 2D weather map plus a vertical profile that
// gives the layer a flat base and a rounded, eroding top.
float zephyr_cloudDensity(vec3 p) {
    vec2 uv = p.xz * 0.0032
            + vec2(frameTimeCounter * 0.0060, frameTimeCounter * 0.0022);
    float base = zephyr_fbm(uv);
    float h = clamp((p.y - CLOUD_ALTITUDE) / CLOUD_THICKNESS, 0.0, 1.0);
    float shape = smoothstep(0.0, 0.22, h) * (1.0 - smoothstep(0.58, 1.0, h));
    // Storms thicken and lower the cloud deck.
    float storm = clamp(rainStrength, 0.0, 1.0);
    float cover = smoothstep(CLOUD_COVERAGE - storm * 0.20,
                             CLOUD_COVERAGE + 0.13 - storm * 0.10, base);
    return cover * shape * CLOUD_DENSITY;
}

// Beer-Lambert transmittance towards the sun; this is the cloud self-shadow.
float zephyr_cloudSunTransmittance(vec3 p, vec3 L) {
    float optical = 0.0;
    for (int i = 1; i <= CLOUD_SUN_STEPS; ++i) {
        optical += zephyr_cloudDensity(p + L * (float(i) * CLOUD_THICKNESS * 0.45));
    }
    return exp(-optical * 1.50);
}

void main() {
    float depth = texture(depthtex0, texCoord).r;
    float dist = depth < 0.9999 ? zephyr_linearDepth(depth) : 1.0e6;
    vec3 color = max(texture(colortex3, texCoord).rgb, vec3(0.0));

    vec3 rd = zephyr_worldRay(texCoord);
    vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    float dayAmount = zephyr_dayAmount(sunDirWorld.y);
    float rain = clamp(rainStrength, 0.0, 1.0);
    float mu = max(dot(rd, sunDirWorld), 0.0);

#if SSR_ENABLED
    // Screen-space reflections for water. This runs here (not in deferred)
    // because deferred writes colortex3 and cannot sample it back (A3 contract).
    float matId = texture(colortex0, texCoord).a;
    if (matId > 0.5 && matId < 1.5 && depth < 0.9999) {
        vec4 vClip = gbufferProjectionInverse * vec4(texCoord * 2.0 - 1.0,
                                                     depth * 2.0 - 1.0, 1.0);
        float vw = abs(vClip.w) < 1e-5 ? 1e-5 : vClip.w;
        vec3 viewPos = vClip.xyz / vw;
        vec3 V = normalize(-viewPos);

        vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz + cameraPosition;
        float tw = frameTimeCounter;
        float wx = sin(worldPos.x * 0.85 + tw * 1.25) * cos(worldPos.z * 0.62 - tw * 0.85);
        float wz = sin(worldPos.z * 1.05 - tw * 1.45) * cos(worldPos.x * 0.55 + tw * 0.75);
        vec3 N = normalize(mat3(gbufferModelView)
                         * normalize(vec3(wx * WAVE_AMPLITUDE, 1.0, wz * WAVE_AMPLITUDE)));
        vec3 R = normalize(reflect(-V, N));

        float march = SSR_STEP_LENGTH;
        vec3 p = viewPos + N * 0.06;
        vec2 hitUv = vec2(-1.0);
        for (int i = 0; i < SSR_STEPS; ++i) {
            p += R * march;
            march *= 1.10;
            vec4 cp = gbufferProjection * vec4(p, 1.0);
            if (abs(cp.w) < 1e-5) break;
            vec2 uv = cp.xy / cp.w * 0.5 + 0.5;
            if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
            float d = texture(depthtex0, uv).r;
            if (d >= 0.9999) continue;
            float diff = (-p.z) - zephyr_linearDepth(d);
            if (diff > 0.0 && diff < SSR_THICKNESS) {
                hitUv = uv;
                break;
            }
        }
        if (hitUv.x >= 0.0) {
            float fres = WATER_F0 + (1.0 - WATER_F0)
                       * pow(clamp(1.0 - max(dot(V, N), 0.0), 0.0, 1.0), 5.0);
            float edge = smoothstep(0.0, 0.06, hitUv.x)
                       * (1.0 - smoothstep(0.94, 1.0, hitUv.x))
                       * smoothstep(0.0, 0.06, hitUv.y)
                       * (1.0 - smoothstep(0.94, 1.0, hitUv.y));
            vec3 refl = max(texture(colortex3, hitUv).rgb, vec3(0.0));
            color = mix(color, refl, clamp(fres * 2.0 + 0.45, 0.0, 0.90)
                                    * SSR_STRENGTH * edge * (1.0 + rain * 0.30));
        }
    }
#endif

#if CLOUD_ENABLED
    if (rd.y > 0.01) {
        float t0 = max((CLOUD_ALTITUDE - cameraPosition.y) / rd.y, 0.0);
        float t1 = min((CLOUD_ALTITUDE + CLOUD_THICKNESS - cameraPosition.y) / rd.y,
                       min(dist, 9000.0));
        if (t1 > t0) {
            float stepLen = (t1 - t0) / float(CLOUD_STEPS);
            vec3 L = normalize(vec3(sunDirWorld.x, max(sunDirWorld.y, 0.10), sunDirWorld.z));
            float warmC = zephyr_warmMix(sunDirWorld.y);
            vec3 cloudAmbient = mix(vec3(0.10, 0.13, 0.20), vec3(0.58, 0.66, 0.80), dayAmount)
                              * mix(1.0, 0.55, rain);
            vec3 sunColor = mix(vec3(1.45, 0.58, 0.24), vec3(1.20, 1.12, 0.98), warmC);
            float phaseC = 0.55 + 0.45 * pow(mu, 4.0);
            float silver = pow(mu, 16.0);

            float T = 1.0;
            vec3 scattered = vec3(0.0);
            for (int i = 0; i < CLOUD_STEPS; ++i) {
                vec3 p = cameraPosition + rd * (t0 + (float(i) + 0.5) * stepLen);
                float d = zephyr_cloudDensity(p);
                if (d < 0.002) continue;
                float h = clamp((p.y - CLOUD_ALTITUDE) / CLOUD_THICKNESS, 0.0, 1.0);
                float sunT = zephyr_cloudSunTransmittance(p, L);
                vec3 lit = cloudAmbient * (0.28 + 0.72 * h)
                         + sunColor * sunT * phaseC * dayAmount * 1.15
                         + sunColor * silver * sunT * dayAmount * 0.55;
                float a = 1.0 - exp(-d * stepLen * CLOUD_EXTINCTION);
                scattered += T * a * lit;
                T *= 1.0 - a;
                if (T < 0.02) break;
            }
            vec3 clouded = color * T + scattered;
            color = mix(color, clouded, smoothstep(0.01, 0.12, rd.y));
        }
    }
#endif

    if (depth < 0.9999) {
        vec3 worldPos = cameraPosition + rd * dist;
        float sigma = FOG_DENSITY * exp(-max(worldPos.y - 64.0, 0.0) * FOG_HEIGHT_FALLOFF);
        sigma *= 1.0 + rain * 1.4;
        float T = exp(-clamp(sigma * dist, 0.0, 40.0));

        vec3 fogRay = normalize(vec3(rd.x, max(rd.y, 0.02), rd.z));
        vec3 fogColor = zephyr_atmosphere(fogRay, sunDirWorld, dayAmount, rain);
        fogColor *= 0.80 + FOG_INSCATTER_BOOST * pow(mu, 4.0) * dayAmount;

        color = color * T + fogColor * (1.0 - T);
    }

    outColor = vec4(clamp(color, 0.0, 65504.0), 1.0);
}
