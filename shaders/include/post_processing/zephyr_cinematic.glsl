/*
--------------------------------------------------------------------------------

  Zephyr Cinematic Look
  ---------------------
  A film-look layer designed for the "photoreal anime" references the project
  targets (rain-wet streets, warm low sun, teal shadows, soft highlight bloom).

  This module is intentionally self-contained: it only depends on
  /include/utility/color.glsl and the Photon settings defines.

  Pipeline placement (see program/c14_color_grading.fsh and program/final.fsh)

    scene linear (rec.2020)
      -> zephyr_pre_tonemap()       warm highlights, protect bright areas
      -> grade_input()              Photon: exposure / contrast / saturation
      -> tonemap()                  Photon: tone curve
      -> grade_output()             Photon: HSL grading, rec.709
      -> zephyr_post_tonemap()      split tone, filmic curve, black lift,
                                    vibrance, highlight desaturation
      -> (final.fsh) zephyr_letterbox(), zephyr_apply_grain()

  All Zephyr parameters are settings.glsl defines. The module compiles to a
  near no-op when ZEPHYR_CINEMATIC is not defined, so it can be removed from a
  pack by deleting the two call sites plus this file.

--------------------------------------------------------------------------------
*/

#if !defined INCLUDE_POST_PROCESSING_ZEPHYR_CINEMATIC
#define INCLUDE_POST_PROCESSING_ZEPHYR_CINEMATIC

#include "/include/utility/color.glsl"

// Rec.709 weights, used after the tonemapper (display-linear rec.709)
const vec3 zephyr_luma_709 = vec3(0.2126, 0.7152, 0.0722);

// -----------------------------------------------------------------------------
//   Pre-tonemap
//   rgb := scene color in the working space (rec.2020 primaries, linear, [0, inf])
// -----------------------------------------------------------------------------

vec3 zephyr_pre_tonemap(vec3 rgb) {
#ifdef ZEPHYR_CINEMATIC
	float strength = ZEPHYR_STRENGTH;

	// High luminance mask. Kept in scene-linear so it tracks real light
	// intensity instead of display brightness.
	float lum   = dot(rgb, luminance_weights);
	float hi    = smoothstep(0.35, 3.20, lum);

	// Warm the highlights: the reference keeps its low sun in the amber
	// range while shadows stay neutral / slightly cool.
	vec3 warm = vec3(
		1.0 + 0.16 * ZEPHYR_WARMTH,
		1.0 + 0.04 * ZEPHYR_WARMTH,
		1.0 - 0.12 * ZEPHYR_WARMTH
	);
	rgb *= mix(vec3(1.0), warm, hi * strength);

	// Compress very bright, very saturated colors before the tonemapper so
	// the shoulder does not turn into neon (film highlight desaturation).
	float chroma = max_of(rgb) - min_of(rgb);
	float hot    = hi * smoothstep(0.55, 1.60, chroma);
	float roll   = hot * ZEPHYR_HIGHLIGHT_ROLLOFF * strength * 0.55;
	rgb = mix(rgb, vec3(lum), roll);

	return max0(rgb);
#else
	return rgb;
#endif
}

// -----------------------------------------------------------------------------
//   Post-tonemap
//   rgb := display-linear rec.709, [0, 1]
// -----------------------------------------------------------------------------

vec3 zephyr_post_tonemap(vec3 rgb) {
#ifdef ZEPHYR_CINEMATIC
	rgb = clamp01(rgb);

	// Perceptual (sqrt) space: 0.5 is roughly middle grey, which makes the
	// curve and split-tone pivots behave like photographic controls.
	vec3 c = sqrt(rgb);

	float split_strength = ZEPHYR_SPLIT_STRENGTH * ZEPHYR_STRENGTH;
	float lum = dot(c, zephyr_luma_709);

	// 1. Split toning: cool shadows, warm highlights.
	const vec3 shadow_tint    = vec3(0.90, 1.00, 1.09);
	const vec3 highlight_tint = vec3(1.06, 1.00, 0.93);

	float shadow_weight = 1.0 - smoothstep(0.06, 0.58, lum);
	float high_weight   = smoothstep(0.44, 1.00, lum);

	c *= mix(vec3(1.0), shadow_tint,    shadow_weight * split_strength);
	c *= mix(vec3(1.0), highlight_tint, high_weight   * split_strength);

	// 2. Filmic S-curve. smoothstep is an exact S-curve; blending keeps the
	//    midtone pivot and only adds contrast in the transitions.
	float curve = clamp(ZEPHYR_FILM_CURVE * ZEPHYR_STRENGTH, 0.0, 2.0);
	if (curve > 0.0) {
		c = mix(c, smoothstep(vec3(0.0), vec3(1.0), c), min(curve, 1.0));
		if (curve > 1.0) {
			c = mix(c, smoothstep(vec3(0.0), vec3(1.0), c), curve - 1.0);
		}
	}

	// 3. Black lift / film fade. Raises the toe slightly and desaturates the
	//    shadows, which is what gives the reference its "hazy film" feel.
	float lift = ZEPHYR_BLACK_LIFT;
	if (lift > 0.0) {
		c = c * (1.0 - lift) + lift * 0.55;
		c = mix(c, vec3(dot(c, zephyr_luma_709)), lift * 1.6);
	}

	// 4. Vibrance: boost restrained colors more than already saturated ones.
	lum = dot(c, zephyr_luma_709);
	float sat = max_of(c) - min_of(c);
	float vibrance = ZEPHYR_VIBRANCE * ZEPHYR_STRENGTH * (1.0 - smoothstep(0.0, 0.55, sat));
	c = mix(vec3(lum), c, 1.0 + vibrance);

	// 5. Highlight desaturation (film-like shoulder).
	float shoulder = smoothstep(0.62, 1.0, lum);
	c = mix(c, vec3(lum), shoulder * ZEPHYR_HIGHLIGHT_ROLLOFF * ZEPHYR_STRENGTH * 0.60);

	return sqr(clamp01(c));
#else
	return rgb;
#endif
}

// -----------------------------------------------------------------------------
//   Lens / display effects (used by final.fsh, display space)
// -----------------------------------------------------------------------------

// 2.39:1 style letterbox. aspect := view_width / view_height
vec3 zephyr_letterbox(vec3 color, vec2 uv, float aspect) {
#if defined ZEPHYR_CINEMATIC && ZEPHYR_LETTERBOX == 1
	float target = ZEPHYR_LETTERBOX_RATIO;
	if (target > 1.0 && aspect > 0.0 && aspect < target) {
		float visible = aspect / target;
		float bar = 0.5 * (1.0 - visible);

		if (uv.y < bar || uv.y > 1.0 - bar) {
			return vec3(0.0);
		}
	}
#endif
	return color;
}

// Animated film grain. Luminance weighted so highlights stay clean.
float zephyr_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 zephyr_apply_grain(vec3 color, vec2 frag_coord, float time) {
#ifdef ZEPHYR_CINEMATIC
	// NOTE: keep the threshold as a runtime branch. GLSL #if only accepts
	// integer constant expressions, so comparing float settings there is
	// invalid on strict drivers (AMD rejects it).
	if (ZEPHYR_GRAIN > 0.0) {
		float n = zephyr_hash12(frag_coord + fract(time * 0.37) * 1137.0);
		n = (n - 0.5) * 2.0;

		float lum = dot(color, zephyr_luma_709);
		float weight = (0.35 + 0.65 * smoothstep(0.0, 0.30, lum)) * (1.0 - smoothstep(0.60, 1.0, lum));
		float amount = n * ZEPHYR_GRAIN * 0.055 * weight;

		return clamp01(color + amount);
	}
#endif
	return color;
}

#endif // INCLUDE_POST_PROCESSING_ZEPHYR_CINEMATIC
