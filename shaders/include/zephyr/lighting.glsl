#if !defined INCLUDE_ZEPHYR_LIGHTING
#define INCLUDE_ZEPHYR_LIGHTING

#include "/include/zephyr/math.glsl"

uniform sampler2D lightmap;

uniform vec3 sunPosition;
uniform mat4 gbufferModelViewInverse;

// Sun colour by elevation (own ramp)
vec3 zephyr_sun_color(float elev) {
	float day  = smoothstep(-0.10, 0.25, elev);
	float gold = exp(-pow((elev - 0.05) / 0.12, 2.0));
	float twil = exp(-pow((elev + 0.10) / 0.13, 2.0));

	vec3 night  = vec3(0.10, 0.14, 0.26);
	vec3 noon   = vec3(1.00, 0.96, 0.90);
	vec3 warm   = vec3(1.00, 0.58, 0.28);
	vec3 violet = vec3(0.70, 0.52, 0.86);

	vec3 c = mix(night, noon, day);
	c = mix(c, warm, gold * 0.9);
	c = mix(c, violet, twil * 0.45);
	return c;
}

vec3 zephyr_ambient_color(float elev) {
	float day  = smoothstep(-0.12, 0.30, elev);
	float twil = exp(-pow((elev + 0.09) / 0.13, 2.0));
	vec3 night = vec3(0.020, 0.030, 0.070);
	vec3 dayc  = vec3(0.42, 0.55, 0.85);
	vec3 dusk  = vec3(0.48, 0.28, 0.40);
	vec3 c = mix(night, dayc, day);
	return mix(c, dusk, twil * 0.55);
}

// Simple forward lighting for the first self-developed version:
// lightmap-based sky/block light + sun Lambert. No shadow map yet (S2+).
vec3 zephyr_light(vec3 albedo, vec3 normal_world, vec2 lightmap_coord) {
	float blocklight = clamp(lightmap_coord.x, 0.0, 1.0);
	float skylight   = clamp(lightmap_coord.y, 0.0, 1.0);

	vec3 sun_dir = normalize(mat3(gbufferModelViewInverse) * sunPosition);
	float elev = sun_dir.y;
	vec3 sun_color = zephyr_sun_color(elev);
	vec3 ambient = zephyr_ambient_color(elev) * AMBIENT_INTENSITY;

	float ndotl = max(dot(normal_world, sun_dir), 0.0);
	vec3 light = ambient * (0.35 + 0.65 * skylight)
	           + sun_color * SUN_INTENSITY * ndotl * skylight
	           + vec3(1.00, 0.72, 0.45) * BLOCKLIGHT_INTENSITY * blocklight;

	return albedo * light;
}

#endif
