#ifndef ZEPHYR_GBUFFER_GLSL
#define ZEPHYR_GBUFFER_GLSL

vec3 zephyr_encode_normal(vec3 normal) {
    return normal * 0.5 + 0.5;
}

vec4 zephyr_write_material(vec3 albedo, vec3 normal, float alpha) {
    return vec4(zephyr_encode_normal(normal), alpha);
}

#endif
