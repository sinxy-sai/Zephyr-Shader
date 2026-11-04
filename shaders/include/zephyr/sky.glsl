/*
  Zephyr | sky: own radiance model (P2 of the Photon replacement plan)
  Contract (host must declare): none (all inputs are parameters)
  Interface:
    vec3 zephyr_sky_radiance(vec3 dir, vec3 sun_dir, float rain)
  Units: dir/sun_dir = world space unit vectors; rain = 0..1;
         return value = linear HDR radiance (comparable to Photon's sky scale).
  Toggle: ZEPHYR_OWN_SKY (settings.glsl)
*/
#ifndef INCLUDE_ZEPHYR_SKY
#define INCLUDE_ZEPHYR_SKY

float zephyr_hash11(float n) { return fract(sin(n) * 43758.5453123); }

float zephyr_hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float zephyr_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = zephyr_hash12(i);
	float b = zephyr_hash12(i + vec2(1.0, 0.0));
	float c = zephyr_hash12(i + vec2(0.0, 1.0));
	float d = zephyr_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float zephyr_fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; ++i) {
		sum += amp * zephyr_value_noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return sum;
}

// Own sky: vertical gradient + sun glow/disk + stars + procedural cloud deck.
vec3 zephyr_sky_radiance(vec3 dir, vec3 sun_dir, float rain) {
	float elev = sun_dir.y;
	float day  = smoothstep(-0.12, 0.18, elev);
	float gold = exp(-pow((elev - 0.04) / 0.12, 2.0));
	float twil = exp(-pow((elev + 0.10) / 0.13, 2.0));

	float up = clamp(dir.y, 0.0, 1.0);
	float horizon_mix = pow(1.0 - up, 3.0);

	// Day / night base gradient
	vec3 zenith  = mix(vec3(0.006, 0.010, 0.024), vec3(0.085, 0.230, 0.560), day);
	vec3 horizon = mix(vec3(0.040, 0.048, 0.075), vec3(0.620, 0.720, 0.860), day);

	vec3 sky = mix(zenith, horizon, horizon_mix);

	// Ozone: deeper blue toward the zenith
	sky *= mix(vec3(1.0), vec3(0.92, 0.97, 1.10), up * up * 0.6);

	// Twilight warm band along the sun side of the horizon
	float sun_side = clamp(dot(normalize(vec3(dir.x, 0.0, dir.z) + 1e-5),
	                           normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 1e-5)) * 0.5 + 0.5, 0.0, 1.0);
	sky = mix(sky, vec3(0.62, 0.28, 0.22), (1.0 - up) * twil * sun_side * 0.75);

	// Sun glow + disk
	float cosang = max(dot(dir, sun_dir), 0.0);
	sky += vec3(1.00, 0.56, 0.26) * pow(cosang, 2.5) * gold * 0.45;
	sky += vec3(1.00, 0.66, 0.34) * pow(cosang, 12.0) * gold * 1.10;
	sky += vec3(9.00, 8.20, 7.00) * smoothstep(0.0105, 0.0060, acos(clamp(cosang, -1.0, 1.0))) * day;

	// Stars (only above the horizon, only at night)
	float night = 1.0 - smoothstep(-0.16, 0.05, elev);
	if (night > 0.01 && dir.y > 0.0) {
		vec2 sp = dir.xz / max(dir.y, 0.15) * 60.0;
		vec2 cell = floor(sp);
		float h = zephyr_hash12(cell);
		float star = step(0.997, h) * (0.4 + 0.6 * zephyr_hash11(h * 91.7));
		sky += vec3(0.85, 0.90, 1.05) * star * night * 2.2;
	}

	// Procedural cloud deck (cheap fbm, projected onto a plane)
	float cloud_alt = 0.18;
	if (dir.y > 0.02) {
		vec2 cp = dir.xz / (dir.y + cloud_alt) * 1.6 + vec2(0.06, 0.02) * (1.0 + 0.4 * sin(1.0));
		float clouds = smoothstep(0.42, 0.78, zephyr_fbm(cp));
		vec3 cloud_lit = vec3(1.00, 0.92, 0.86) * mix(0.12, 1.00, day);
		cloud_lit = mix(cloud_lit, vec3(1.05, 0.55, 0.34), gold * 0.65);
		cloud_lit = mix(cloud_lit, vec3(0.30, 0.26, 0.34), twil * 0.55);
		cloud_lit *= mix(0.40, 1.0, clamp(cosang * 0.8 + 0.2, 0.0, 1.0));
		sky = mix(sky, cloud_lit, clouds * mix(0.55, 0.9, rain));
	}

	// Rain: desaturate toward a grey overcast
	vec3 grey = vec3(dot(sky, vec3(0.2126, 0.7152, 0.0722))) * vec3(0.88, 0.94, 1.04);
	sky = mix(sky, grey, clamp(rain, 0.0, 1.0) * 0.75);

	return max(sky, vec3(0.0));
}

#endif // INCLUDE_ZEPHYR_SKY
