#if !defined INCLUDE_ZEPHYR_TONEMAP
#define INCLUDE_ZEPHYR_TONEMAP

// AgX display transform (own implementation), input linear HDR -> [0,1] linear
vec3 zephyr_agx_contrast(vec3 x) {
	vec3 x2 = x * x;
	vec3 x4 = x2 * x2;
	return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}

vec3 zephyr_agx(vec3 rgb) {
	const mat3 inset = mat3(
		 0.856627153315983,  0.137318972929847,  0.111898212999950,
		 0.095121240538159,  0.761241990602591,  0.076799418603190,
		 0.048251104852477,  0.101439025833993,  0.811302368396859
	);
	const mat3 outset = mat3(
		 1.127100581814437, -0.110606643096603, -0.016493938717835,
		-0.141329763498438,  1.157823702216272, -0.016493938717834,
		-0.141329763498438, -0.110606643096603,  1.251936406595040
	);

	rgb = max(rgb, vec3(0.0));
	rgb = inset * rgb;
	rgb = max(rgb, vec3(1e-10));
	rgb = log2(rgb);
	rgb = (rgb + 12.47393) / (16.5);
	rgb = clamp(rgb, 0.0, 1.0);
	rgb = zephyr_agx_contrast(rgb);
	rgb = outset * rgb;

	float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	rgb = mix(vec3(lum), rgb, 1.08 * AGX_LOOK);
	return clamp(rgb, 0.0, 1.0);
}

#endif
