#if !defined INCLUDE_ZEPHYR_MATH
#define INCLUDE_ZEPHYR_MATH

const float zephyr_pi = 3.14159265359;
const float zephyr_tau = 6.28318530718;

float zephyr_saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  zephyr_saturate(vec3 x)  { return clamp(x, 0.0, 1.0); }

float zephyr_luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 zephyr_srgb_encode(vec3 c) {
	c = max(c, vec3(0.0));
	vec3 e = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
	return mix(e, c * 12.92, step(c, vec3(0.0031308)));
}

vec3 zephyr_dither_8bit(vec3 color, vec2 frag_coord) {
	ivec2 i = ivec2(mod(frag_coord, 4.0));
	const float bayer[16] = float[16](
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0
	);
	return color + ((bayer[i.x + 4 * i.y] + 0.5) / 16.0 - 0.5) * (1.0 / 255.0);
}

#endif
