#version 330 compatibility

#include "/lib/config.glsl"
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

in vec2 texCoord;

uniform sampler2D colortex4;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 outColor;

void main() {
    vec3 color = max(texture(colortex4, texCoord).rgb, vec3(0.0));

    vec3 bloom = vec3(0.0);
    for (int i = 0; i < 4; ++i) {
        float lod = 3.0 + float(i) * 1.5 * BLOOM_RADIUS;
        vec3 sampleColor = textureLod(colortex3, texCoord, lod).rgb;
        bloom += max(sampleColor - vec3(BLOOM_THRESHOLD), vec3(0.0));
    }
    color += bloom * (BLOOM_STRENGTH * 0.25);

#if VL_ENABLED
    vec3 sunDirWorld = normalize(mat3(gbufferModelViewInverse) * normalize(sunPosition));
    float dayAmount = smoothstep(-0.16, 0.14, sunDirWorld.y);

    vec4 sunClip = gbufferProjection * vec4(normalize(sunPosition), 0.0);
    float w = abs(sunClip.w) < 1e-5 ? 1e-5 : sunClip.w;
    vec2 sunNdc = sunClip.xy / w;
    float onScreen = step(abs(sunNdc.x), 1.4) * step(abs(sunNdc.y), 1.4)
                   * step(0.0, -normalize(sunPosition).z);

    vec4 viewClip = gbufferProjectionInverse * vec4(texCoord * 2.0 - 1.0, 1.0, 1.0);
    float vw = abs(viewClip.w) < 1e-5 ? 1e-5 : viewClip.w;
    vec3 rd = normalize(mat3(gbufferModelViewInverse) * normalize(viewClip.xyz / vw));
    float phase = pow(max(dot(rd, sunDirWorld), 0.0), 6.0);

    vec2 sunUv = sunNdc * 0.5 + 0.5;
    vec2 stepUv = (sunUv - texCoord) / float(VL_STEPS);
    vec2 uv = texCoord;
    float weight = 1.0;
    float shafts = 0.0;
    for (int i = 0; i < VL_STEPS; ++i) {
        uv += stepUv;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
        float d = texture(depthtex0, uv).r;
        shafts += step(0.9999, d) * weight;
        weight *= VL_DECAY;
    }
    shafts /= float(VL_STEPS);

    vec3 shaftColor = vec3(1.00, 0.78, 0.48) * shafts * VL_INTENSITY
                    * phase * dayAmount * onScreen;
    color += shaftColor;
#endif

    outColor = vec4(clamp(color, 0.0, 65504.0), 1.0);
}
