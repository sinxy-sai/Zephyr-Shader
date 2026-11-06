#version 120
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform vec3 sunPosition;
varying vec2 zephyrTexCoord;
/* DRAWBUFFERS:0 */

vec3 zephyr_grade(vec3 color) {
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luminance), color, 0.94);
    color = (color - 0.5) * 1.04 + 0.5;
    color = color / (1.0 + max(color - 0.78, 0.0) * 0.45);
    color += vec3(0.004, 0.006, 0.008);
    return clamp(color, 0.0, 1.0);
}

vec3 zephyr_sky(vec3 color, vec2 uv) {
    float horizon = smoothstep(0.25, 0.72, uv.y);
    vec3 horizonColor = vec3(0.60, 0.68, 0.74);
    vec3 zenithColor = vec3(0.25, 0.39, 0.58);
    vec3 gradient = mix(horizonColor, zenithColor, horizon);
    float haze = 1.0 - smoothstep(0.72, 1.0, uv.y);
    gradient += vec3(0.035, 0.028, 0.018) * haze;
    return mix(color, gradient, 0.78);
}

vec3 zephyr_direct_light(vec3 color, vec3 encodedNormal) {
    vec3 normal = normalize(encodedNormal * 2.0 - 1.0);
    float sunLength = dot(sunPosition, sunPosition);
    vec3 fallbackSun = normalize(vec3(-0.25, 0.82, 0.35));
    vec3 lightDirection = sunLength > 0.001 ? normalize(sunPosition) : fallbackSun;
    float ndotl = max(dot(normal, lightDirection), 0.0);
    float light = 0.68 + ndotl * 0.42;
    return color * light;
}

void main() {
    vec4 scene = texture2D(colortex0, zephyrTexCoord);
    float depth = texture2D(depthtex0, zephyrTexCoord).r;
    vec3 color = zephyr_grade(scene.rgb);
    if (depth > 0.9995) {
        color = zephyr_sky(color, zephyrTexCoord);
    } else {
        color = zephyr_direct_light(color, texture2D(colortex1, zephyrTexCoord).rgb);
    }
    gl_FragData[0] = vec4(color, scene.a);
}
