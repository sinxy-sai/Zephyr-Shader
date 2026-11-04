#if !defined INCLUDE_MISC_TONEMAP_OPERATORS
#define INCLUDE_MISC_TONEMAP_OPERATORS

#include "/include/post_processing/aces/aces.glsl"
#include "/include/utility/color.glsl"

// ACES RRT and ODT
vec3 tonemap_aces_full(vec3 rgb) {
	rgb *= 1.6; // Match the exposure to the RRT

	rgb = rgb * rec2020_to_ap0;

	rgb = aces_rrt(rgb);
	rgb = aces_odt(rgb);

	return rgb * ap1_to_rec2020;
}

// ACES RRT and ODT approximation
vec3 tonemap_aces_fit(vec3 rgb) {
	rgb *= 1.6; // Match the exposure to the RRT

	rgb = rgb * rec2020_to_ap0;

	rgb = rrt_sweeteners(rgb);
	rgb = rrt_and_odt_fit(rgb);

	// Global desaturation
	vec3 grayscale = vec3(dot(rgb, luminance_weights));
	rgb = mix(grayscale, rgb, odt_sat_factor);

	return rgb * ap1_to_rec2020;
}

vec3 tonemap_hejl_2015(vec3 rgb) {
	const float white_point = 5.0;

	vec4 vh = vec4(rgb, white_point);
	vec4 va = (1.425 * vh) + 0.05; // eval filmic curve
	vec4 vf = ((vh * va + 0.004) / ((vh * (va + 0.55) + 0.0491))) - 0.0821;

	return vf.rgb / vf.www; // white point correction
}

// Filmic tonemapping operator made by Jim Hejl and Richard Burgess
// Modified by Tech to not lose color information below 0.004
vec3 tonemap_hejl_burgess(vec3 rgb) {
	rgb = rgb * min(vec3(1.0), 1.0 - 0.8 * exp(rcp(-0.004) * rgb));
	rgb = (rgb * (6.2 * rgb + 0.5)) / (rgb * (6.2 * rgb + 1.7) + 0.06);
	return srgb_eotf_inv(rgb); // Revert built-in sRGB conversion
}

// Timothy Lottes 2016, "Advanced Techniques and Optimization of HDR Color Pipelines"
// https://gpuopen.com/wp-content/uploads/2016/03/GdcVdrLottes.pdf
vec3 tonemap_lottes(vec3 rgb) {
	const vec3 a      = vec3(1.5); // Contrast
	const vec3 d      = vec3(0.91); // Shoulder contrast
	const vec3 hdr_max = vec3(8.0);  // White point
	const vec3 mid_in  = vec3(0.26); // Fixed midpoint x
	const vec3 mid_out = vec3(0.32); // Fixed midput y

	const vec3 b =
		(-pow(mid_in, a) + pow(hdr_max, a) * mid_out) /
		((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
	const vec3 c =
		(pow(hdr_max, a * d) * pow(mid_in, a) - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out) /
		((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);

	return pow(rgb, a) / (pow(rgb, a * d) * b + c);
}

// Filmic tonemapping operator made by John Hable for Uncharted 2
vec3 tonemap_uncharted_2_partial(vec3 rgb) {
	const float a = 0.15;
	const float b = 0.50;
	const float c = 0.10;
	const float d = 0.20;
	const float e = 0.02;
	const float f = 0.30;

	return ((rgb * (a * rgb + (c * b)) + (d * e)) / (rgb * (a * rgb + b) + d * f)) - e / f;
}

vec3 tonemap_uncharted_2(vec3 rgb) {
	const float exposure_bias = 2.0;
	const vec3 w = vec3(11.2);

	vec3 curr = tonemap_uncharted_2_partial(rgb * exposure_bias);
	vec3 white_scale = vec3(1.0) / tonemap_uncharted_2_partial(w);
	return curr * white_scale;
}

// Tone mapping operator made by Tech for his shader pack Lux
vec3 tonemap_tech(vec3 rgb) {
	vec3 a = rgb * min(vec3(1.0), 1.0 - exp(-1.0 / 0.038 * rgb));
	a = mix(a, rgb, rgb * rgb);
	return a / (a + 0.6);
}

// Tonemapping operator made by Zombye for his old shader pack Ozius
// It was given to me by Jessie
vec3 tonemap_ozius(vec3 rgb) {
    const vec3 a = vec3(0.46, 0.46, 0.46);
    const vec3 b = vec3(0.60, 0.60, 0.60);

	rgb *= 1.6;

    vec3 cr = mix(vec3(dot(rgb, luminance_weights_ap1)), rgb, 0.5) + 1.0;

    rgb = pow(rgb / (1.0 + rgb), a);
    return pow(rgb * rgb * (-2.0 * rgb + 3.0), cr / b);
}

vec3 tonemap_reinhard(vec3 rgb) {
	return rgb / (rgb + 1.0);
}

vec3 tonemap_reinhard_jodie(vec3 rgb) {
	vec3 reinhard = rgb / (rgb + 1.0);
	return mix(rgb / (dot(rgb, luminance_weights) + 1.0), reinhard, reinhard);
}


// AgX display transform (Troy Sobotka / Blender AgX base)
// Operates on linear HDR in Photon's working space; returns display-referred
// linear values in [0, 1]. Compared to ACES/Lottes it keeps highlights from
// turning into a saturated orange wall, which is what made the sunset look ugly.
vec3 agx_default_contrast(vec3 x) {
	vec3 x2 = x * x;
	vec3 x4 = x2 * x2;
	return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}

vec3 tonemap_agx(vec3 rgb) {
	const mat3 agx_inset = mat3(
		 0.856627153315983,   0.137318972929847,   0.111898212999950,
		 0.095121240538159,   0.761241990602591,   0.076799418603190,
		 0.048251104852477,   0.101439025833993,   0.811302368396859
	);
	const mat3 agx_outset = mat3(
		 1.127100581814437,  -0.110606643096603,  -0.016493938717835,
		-0.141329763498438,   1.157823702216272,  -0.016493938717834,
		-0.141329763498438,  -0.110606643096603,   1.251936406595040
	);
	const float agx_min_ev = -12.47393;
	const float agx_max_ev =   4.026069;

	// Photon's HDR scale is much hotter than AgX's expected linear range
	rgb *= ZEPHYR_AGX_PRESCALE;
	rgb = max(rgb, vec3(0.0));
	rgb = agx_inset * rgb;
	rgb = max(rgb, vec3(1e-10));
	rgb = log2(rgb);
	rgb = (rgb - agx_min_ev) / (agx_max_ev - agx_min_ev);
	rgb = clamp(rgb, 0.0, 1.0);
	rgb = agx_default_contrast(rgb);
	rgb = agx_outset * rgb;

	// Small "punchy" look: lifts mid-tone contrast without clipping highlights
	rgb = clamp(rgb, 0.0, 1.0);
	float lum = dot(rgb, luminance_weights);
	rgb = max0(mix(vec3(lum), rgb, 1.08));
	rgb = pow(rgb, vec3(0.94));

	return clamp(rgb, 0.0, 1.0);
}

#endif // INCLUDE_MISC_TONEMAP_OPERATORS