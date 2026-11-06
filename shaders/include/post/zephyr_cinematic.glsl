#ifndef ZEPHYR_POST_GLSL
#define ZEPHYR_POST_GLSL

vec3 zephyr_cinematic_grade(vec3 color) {
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    vec3 coolShadow = vec3(0.98, 1.00, 1.02);
    vec3 warmHighlight = vec3(1.02, 1.00, 0.96);
    float highlight = smoothstep(0.35, 0.9, luminance);
    return color * mix(coolShadow, warmHighlight, highlight);
}

#endif
