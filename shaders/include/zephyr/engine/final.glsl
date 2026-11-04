/*
  Zephyr | engine: final pass (self-hosted, S0 of the no-Photon rewrite)
  Contract (host must declare):
    uniforms: sampler2D colortex0; float viewWidth, viewHeight, frameTimeCounter
  Interface:
    vec3 zephyr_final_pass(sampler2D scene, ivec2 texel, vec2 uv, vec2 view_size, float time)
  Units: scene = display-referred linear RGB in [0,1]; return = display-encoded
         colour in [0,1], ready to be written to the framebuffer.
  Photon dependency: none (this file is intentionally standalone).
*/
#ifndef INCLUDE_ZEPHYR_ENGINE_FINAL
#define INCLUDE_ZEPHYR_ENGINE_FINAL

// ---- sRGB transfer functions (own implementation) -------------------------
vec3 zephyr_display_eotf(vec3 linear_color) {
	vec3 x = max(linear_color, vec3(0.0));
	vec3 encoded = 1.055 * pow(x, vec3(1.0 / 2.4)) - 0.055;
	return mix(encoded, x * 12.92, step(x, vec3(0.0031308)));
}

vec3 zephyr_display_inv_eotf(vec3 display_color) {
	vec3 x = clamp(display_color, 0.0, 1.0);
	vec3 linear_color = pow((x + 0.055) / 1.055, vec3(2.4));
	return mix(linear_color, x / 12.92, step(x, vec3(0.04045)));
}

// ---- contrast-adaptive sharpening (own implementation) --------------------
vec3 zephyr_min5(vec3 a, vec3 b, vec3 c, vec3 d, vec3 e) {
	return min(a, min(b, min(c, min(d, e))));
}
vec3 zephyr_max5(vec3 a, vec3 b, vec3 c, vec3 d, vec3 e) {
	return max(a, max(b, max(c, max(d, e))));
}

vec3 zephyr_cas_filter(sampler2D scene, ivec2 texel, float sharpness) {
	vec3 a = texelFetch(scene, texel + ivec2(-1, -1), 0).rgb;
	vec3 b = texelFetch(scene, texel + ivec2( 0, -1), 0).rgb;
	vec3 c = texelFetch(scene, texel + ivec2( 1, -1), 0).rgb;
	vec3 d = texelFetch(scene, texel + ivec2(-1,  0), 0).rgb;
	vec3 e = texelFetch(scene, texel, 0).rgb;
	vec3 f = texelFetch(scene, texel + ivec2( 1,  0), 0).rgb;
	vec3 g = texelFetch(scene, texel + ivec2(-1,  1), 0).rgb;
	vec3 h = texelFetch(scene, texel + ivec2( 0,  1), 0).rgb;
	vec3 i = texelFetch(scene, texel + ivec2( 1,  1), 0).rgb;

	// sharpening operates in display space
	a = zephyr_display_eotf(a); b = zephyr_display_eotf(b); c = zephyr_display_eotf(c);
	d = zephyr_display_eotf(d); e = zephyr_display_eotf(e); f = zephyr_display_eotf(f);
	g = zephyr_display_eotf(g); h = zephyr_display_eotf(h); i = zephyr_display_eotf(i);

	vec3 min_color = zephyr_min5(d, e, f, b, h);
	     min_color += zephyr_min5(min_color, a, c, g, i);
	vec3 max_color = zephyr_max5(d, e, f, b, h);
	     max_color += zephyr_max5(max_color, a, c, g, i);

	vec3 w = clamp(min(min_color, 2.0 - max_color) / max(max_color, vec3(1e-4)), 0.0, 1.0);
	     w = 1.0 - (1.0 - w) * (1.0 - w);
	     w *= -1.0 / mix(8.0, 5.0, sharpness);

	vec3 weight_sum = 1.0 + 4.0 * w;
	return clamp((b + d + f + h) * w + e, 0.0, 1.0) / weight_sum;
}

// ---- output helpers -------------------------------------------------------
float zephyr_hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float zephyr_bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	const float m[16] = float[16](
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0
	);
	return (m[i.x + 4 * i.y] + 0.5) / 16.0 - 0.5;
}

vec3 zephyr_dither_8bit(vec3 display_color, vec2 texel) {
	return display_color + zephyr_bayer4(texel) * (1.0 / 255.0);
}

vec3 zephyr_final_pass(
	sampler2D scene,
	ivec2 texel,
	vec2 uv,
	vec2 view_size,
	float time
) {
#ifdef CAS
	vec3 color = zephyr_cas_filter(scene, texel, CAS_INTENSITY * 2.0 - 1.0);
#else
	vec3 color = zephyr_display_eotf(texelFetch(scene, texel, 0).rgb);
#endif

#ifdef ZEPHYR_CINEMATIC
	// Letterbox (2.39:1) — black bars, own implementation
	#if ZEPHYR_LETTERBOX == 1
		const float target_aspect = 2.39;
		float aspect = view_size.x / max(view_size.y, 1.0);
		if (aspect < target_aspect) {
			float bar = 0.5 * (1.0 - aspect / target_aspect);
			if (abs(uv.y - 0.5) > 0.5 - bar) color = vec3(0.0);
		}
	#endif

	// Film grain (display space, own hash)
	#if ZEPHYR_GRAIN > 0.0
		float grain = zephyr_hash12(texel + fract(time) * 1000.0) - 0.5;
		color += grain * ZEPHYR_GRAIN * 0.05;
	#endif
#endif

	color = zephyr_dither_8bit(color, vec2(texel));
	return clamp(color, 0.0, 1.0);
}

#endif // INCLUDE_ZEPHYR_ENGINE_FINAL
