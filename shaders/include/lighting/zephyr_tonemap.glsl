#ifndef ZEPHYR_TONEMAP_GLSL
#define ZEPHYR_TONEMAP_GLSL

vec3 zephyr_filmic(vec3 color) {
    color *= exp2(ZEPHYR_EXPOSURE);
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

vec3 zephyr_output(vec3 color) {
    color = zephyr_filmic(max(color, vec3(0.0)));
    return pow(color, vec3(1.0 / 2.2));
}

#endif
