/*
  Zephyr | water: own wave normal model (P3 of the Photon replacement plan)
  Contract (host must declare): none (all inputs are parameters)
  Interface:
    vec3 zephyr_water_normal(vec3 world_pos, vec3 flat_normal, vec2 coord,
                             float rain, float time)
  Units: world_pos/coord in blocks, time seconds, rain 0..1;
         return = world-space normal (unnormalised on purpose, caller normalizes).
  Toggle: ZEPHYR_OWN_WATER
*/
#ifndef INCLUDE_ZEPHYR_WATER
#define INCLUDE_ZEPHYR_WATER

float zephyr_wave(vec2 p, vec2 dir, float wavelength, float speed, float time) {
	const float g = 9.8;
	float k = 6.2831853 / wavelength;
	float w = sqrt(g * k);
	return sin(w * time - k * dot(dir, p));
}

// Three directional waves + fine chop. Amplitude falls with the wavelength, so
// large swells dominate and small chop adds detail.
vec2 zephyr_water_gradient(vec2 coord, float rain, float time) {
	float t = time * mix(0.55, 1.0, rain);

	vec2 grad = vec2(0.0);

	grad += vec2(0.85, 0.35) * zephyr_wave(coord, normalize(vec2(0.85, 0.35)), 9.0, 1.0, t) * 0.055;
	grad += vec2(-0.55, 0.80) * zephyr_wave(coord, normalize(vec2(-0.55, 0.80)), 4.6, 1.25, t) * 0.035;
	grad += vec2(0.20, -0.95) * zephyr_wave(coord, normalize(vec2(0.20, -0.95)), 2.1, 1.5, t) * 0.022;
	grad += vec2(0.60, 0.60) * zephyr_wave(coord * 3.1, normalize(vec2(0.60, 0.60)), 0.75, 1.9, t) * 0.010;

	return grad;
}

vec3 zephyr_water_normal(vec3 world_pos, vec3 flat_normal, vec2 coord, float rain, float time) {
	vec2 grad = zephyr_water_gradient(coord, rain, time);

	// Rain impact rings on top of the waves (ring height field -> gradient)
#ifdef ZEPHYR_WATER_RINGS
	grad += zephyr_water_rain_rings(coord, time, rain) * 0.35 * ZEPHYR_WATER_RINGS;
#endif

	float influence = mix(0.55, 1.0, rain) * WATER_WAVE_STRENGTH;
	influence *= smoothstep(0.0, 0.2, abs(flat_normal.y));

	vec3 n = vec3(-grad.x, 1.0, -grad.y) * influence;
	n = normalize(vec3(n.x, 1.0, n.z));

	return normalize(mix(flat_normal, n, 0.75));
}

#endif // INCLUDE_ZEPHYR_WATER
