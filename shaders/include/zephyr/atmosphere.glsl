#if !defined INCLUDE_ZEPHYR_ATMOSPHERE
#define INCLUDE_ZEPHYR_ATMOSPHERE

// Zephyr atmosphere colour model (see docs). Parameterised so any program can
// include it: (sun elevation, rain) in, linear RGB out.

vec3 zephyr_light_color(float elev, float rain) {
	float day  = smoothstep(-0.08, 0.30, elev);
	float gold = exp(-pow((elev - 0.05) / 0.11, 2.0));
	float twil = exp(-pow((elev + 0.10) / 0.13, 2.0));

	vec3 night  = vec3(0.12, 0.18, 0.34);
	vec3 noon   = vec3(1.00, 0.96, 0.90);
	vec3 warm   = vec3(1.00, 0.56, 0.26);
	vec3 violet = vec3(0.72, 0.52, 0.88);

	vec3 c = mix(night, noon, day);
	c = mix(c, warm,   gold * 0.90);
	c = mix(c, violet, twil * 0.50);

	vec3 grey = vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))) * vec3(0.78, 0.86, 1.02);
	return mix(c, grey, clamp(rain, 0.0, 1.0) * 0.75);
}

vec3 zephyr_ambient_color(float elev, float rain) {
	float day  = smoothstep(-0.10, 0.32, elev);
	float twil = exp(-pow((elev + 0.09) / 0.13, 2.0));

	vec3 night = vec3(0.020, 0.032, 0.075);
	vec3 dayc  = vec3(0.38, 0.52, 0.90);
	vec3 dusk  = vec3(0.50, 0.28, 0.40);

	vec3 c = mix(night, dayc, day);
	c = mix(c, dusk, twil * 0.60);
	return c * mix(1.0, 0.38, clamp(rain, 0.0, 1.0));
}

vec3 zephyr_sky_tint(vec3 dir, vec3 sun_dir, float rain) {
	float up   = clamp(dir.y, 0.0, 1.0);
	float elev = sun_dir.y;

	float gold = exp(-pow((elev - 0.05) / 0.12, 2.0));
	float twil = exp(-pow((elev + 0.10) / 0.14, 2.0));

	vec3 tint = mix(vec3(1.02), vec3(0.84, 0.92, 1.12), up);

	// Ozone: absorbs a little green/red near the zenith, which is what makes a
	// physically lit twilight sky go deep blue up high while staying warm low.
	tint *= mix(vec3(1.0), vec3(0.90, 0.96, 1.10), up * up * 0.55);

	tint = mix(tint, vec3(1.20, 0.96, 0.74), (1.0 - up) * gold);
	tint = mix(tint, vec3(0.96, 0.78, 1.08), (1.0 - up) * twil);
	return tint;
}

vec3 zephyr_sky_glow(vec3 dir, vec3 sun_dir, float rain) {
	float elev   = sun_dir.y;
	float cosang = max(dot(dir, sun_dir), 0.0);
	float horizon = pow(1.0 - clamp(dir.y, 0.0, 1.0), 3.0);

	float gold = exp(-pow((elev - 0.04) / 0.12, 2.0));
	float twil = exp(-pow((elev + 0.10) / 0.14, 2.0));

	// Multiple-scattering stand-in: a wide, soft halo around the sun plus a
	// tighter core, so the sunward horizon glows instead of clipping to a disc.
	vec3 glow = vec3(1.00, 0.56, 0.26) * pow(cosang, 2.5) * gold * 0.55;
	glow += vec3(1.00, 0.62, 0.30) * pow(cosang, 12.0) * gold * 1.20;
	glow += vec3(1.05, 0.30, 0.22) * pow(cosang, 2.0) * horizon * twil * 0.60;

	// Night: airglow + light pollution from the city along the horizon
	float night = 1.0 - smoothstep(-0.16, 0.02, elev);
	float city_glow = pow(1.0 - clamp(dir.y, 0.0, 1.0), 4.0);
	glow += vec3(0.42, 0.26, 0.14) * city_glow * night * ZEPHYR_SKY_CITY_GLOW;
	glow += vec3(0.10, 0.16, 0.30) * night * 0.20; // faint airglow

	glow *= 1.0 - clamp(rain, 0.0, 1.0) * 0.85;
	return glow;
}

vec3 zephyr_water_color(vec3 base, float elev, float rain) {
	float day  = smoothstep(-0.05, 0.35, elev);
	float twil = exp(-pow((elev + 0.10) / 0.13, 2.0));

	vec3 night = vec3(0.012, 0.030, 0.075);
	vec3 dayc  = vec3(0.050, 0.150, 0.210);
	vec3 dusk  = vec3(0.130, 0.075, 0.090);

	vec3 c = mix(night, dayc, day);
	c = mix(c, dusk, twil * 0.55);

	vec3 grey = vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))) * vec3(0.78, 0.90, 1.04);
	c = mix(c, grey, clamp(rain, 0.0, 1.0) * 0.55);
	return c;
}

#endif // INCLUDE_ZEPHYR_ATMOSPHERE
