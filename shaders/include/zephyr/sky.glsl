#if !defined INCLUDE_ZEPHYR_SKY
#define INCLUDE_ZEPHYR_SKY

#include "/include/zephyr/math.glsl"

float zephyr_hash12(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

float zephyr_value_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = zephyr_hash12(i);
	float b = zephyr_hash12(i + vec2(1.0, 0.0));
	float c = zephyr_hash12(i + vec2(0.0, 1.0));
	float d = zephyr_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float zephyr_fbm(vec2 p) {
	float sum = 0.0, amp = 0.5;
	for (int i = 0; i < 4; ++i) { sum += amp * zephyr_value_noise(p); p = p * 2.03 + vec2(17.3, 9.1); amp *= 0.5; }
	return sum;
}

// Own sky radiance: gradient + ozone + sun glow/disk + stars + cloud deck.
vec3 zephyr_sky_radiance(vec3 dir, vec3 sun_dir, float rain) {
	float elev = sun_dir.y;
	float day  = smoothstep(-0.12, 0.20, elev);
	float gold = exp(-pow((elev - 0.04) / 0.12, 2.0));
	float twil = exp(-pow((elev + 0.10) / 0.13, 2.0));

	float up = clamp(dir.y, 0.0, 1.0);
	float horizon_mix = pow(1.0 - up, 3.0);

	vec3 zenith  = mix(vec3(0.005, 0.008, 0.020), vec3(0.070, 0.200, 0.520), day);
	vec3 horizon = mix(vec3(0.030, 0.040, 0.065), vec3(0.580, 0.690, 0.840), day);
	vec3 sky = mix(zenith, horizon, horizon_mix);
	sky *= mix(vec3(1.0), vec3(0.92, 0.97, 1.10), up * up * 0.6);

	vec3 sun_flat = normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 1e-5);
	vec3 dir_flat = normalize(vec3(dir.x, 0.0, dir.z) + 1e-5);
	float sun_side = clamp(dot(dir_flat, sun_flat) * 0.5 + 0.5, 0.0, 1.0);
	sky = mix(sky, vec3(0.62, 0.28, 0.22), (1.0 - up) * twil * sun_side * 0.75);

	float cosang = max(dot(dir, sun_dir), 0.0);
	sky += vec3(1.00, 0.56, 0.26) * pow(cosang, 2.5) * gold * 0.45;
	sky += vec3(1.00, 0.66, 0.34) * pow(cosang, 12.0) * gold * 1.10;
	sky += vec3(9.0, 8.2, 7.0) * smoothstep(0.0105, 0.0060, acos(clamp(cosang, -1.0, 1.0))) * day;

	// clouds
	if (dir.y > 0.02 && SKY_CLOUD_AMOUNT > 0.01) {
		vec2 cp = dir.xz / (dir.y + 0.18) * 1.6;
		float clouds = smoothstep(0.55 - 0.30 * SKY_CLOUD_AMOUNT, 0.80, zephyr_fbm(cp));
		vec3 lit = mix(vec3(0.10), vec3(1.00, 0.94, 0.88), day);
		lit = mix(lit, vec3(1.05, 0.55, 0.34), gold * 0.65);
		lit = mix(lit, vec3(0.30, 0.26, 0.34), twil * 0.55);
		sky = mix(sky, lit, clouds * mix(0.5, 0.85, rain));
	}

	// stars
	float night = 1.0 - smoothstep(-0.16, 0.05, elev);
	if (night > 0.01 && dir.y > 0.0) {
		vec2 sp = dir.xz / max(dir.y, 0.15) * 60.0;
		float star = step(0.9975, zephyr_hash12(floor(sp)));
		sky += vec3(0.85, 0.90, 1.05) * star * night * 2.0;
	}

	// rain: grey overcast
	vec3 grey = vec3(zephyr_luminance(sky)) * vec3(0.88, 0.94, 1.04);
	sky = mix(sky, grey, clamp(rain, 0.0, 1.0) * 0.75);

	return max(sky, vec3(0.0));
}

#endif
