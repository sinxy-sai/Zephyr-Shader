#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

in vec2 texCoord;

uniform sampler2D colortex3;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 4 */
layout(location = 0) out vec4 outColor;

vec3 zephyr_worldRay(vec2 uv) {
    vec4 clip = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    float w = abs(clip.w) < 1e-5 ? 1e-5 : clip.w;
    return normalize(mat3(gbufferModelViewInverse) * normalize(clip.xyz / w));
}

void main() {
    float depth = texture(depthtex0, texCoord).r;
    float dist = depth < 0.9999 ? zephyr_linearDepth(depth) : 1.0e6;
    vec3 color = max(texture(colortex3, texCoord).rgb, vec3(0.0));

    vec3 rd = zephyr_worldRay(texCoord);
    vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    float dayAmount = smoothstep(-0.16, 0.14, sunDirWorld.y);
    float rain = clamp(rainStrength, 0.0, 1.0);
    float mu = max(dot(rd, sunDirWorld), 0.0);

#if CLOUD_ENABLED
    if (rd.y > 0.01) {
        float t = (CLOUD_ALTITUDE - cameraPosition.y) / rd.y;
        if (t > 0.0 && t < 6000.0) {
            vec2 p = (cameraPosition.xz + rd.xz * t) * 0.0032
                   + vec2(frameTimeCounter * 0.0060, frameTimeCounter * 0.0022);
            float n = zephyr_fbm(p);
            float density = smoothstep(CLOUD_COVERAGE, CLOUD_COVERAGE + 0.13, n)
                          * CLOUD_DENSITY;
            float nSun = zephyr_fbm(p + normalize(sunDirWorld.xz + vec2(0.001)) * 0.010);
            float lit = clamp(0.60 + (n - nSun) * 3.5, 0.25, 1.0);

            vec3 cloudBase = mix(vec3(0.16, 0.20, 0.28), vec3(0.88, 0.92, 0.98), dayAmount);
            vec3 cloudColor = cloudBase * (0.35 + 0.95 * lit);
            cloudColor += vec3(1.00, 0.66, 0.30) * pow(mu, 8.0) * dayAmount * 0.85;

            float alpha = clamp(density, 0.0, 1.0) * smoothstep(0.0, 0.14, rd.y);
            if (t < dist) {
                color = mix(color, cloudColor, alpha);
            }
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
