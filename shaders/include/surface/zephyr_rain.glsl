#if !defined INCLUDE_SURFACE_ZEPHYR_RAIN
#define INCLUDE_SURFACE_ZEPHYR_RAIN

/*
--------------------------------------------------------------------------------
  Zephyr rain-on-surface
  ----------------------
  v0.4 rework, after comparing with iterationT 3.2.0:

  - wetness is modulated by a large-scale noise field ("macro wetness") so the
    ground does not alternate between bone-dry patches and mirror puddles
  - horizontal faces get one coherent wet coat (albedo darkening + roughness +
    f0 + ssr), plus normal-only rain impact ripples (no splash particles)
  - vertical faces get a wet sheen and slow running streaks
  - everything is driven by rainStrength (impacts) and wetness (coat, survives
    the rain), and real Photon puddles are still applied afterwards

  Intended to be included after material decoding and before rain puddles.
--------------------------------------------------------------------------------
*/

#include "/include/misc/material_masks.glsl"

uniform sampler2D zephyr_ripple; // image/ripple.png: baked ripple normal (RG)

float zephyr_rain_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Large-scale wetness field. Keeps wet areas coherent instead of per-block
// patchwork. Returns ~0.55..1.0 so even "drier" spots still read as damp.
float zephyr_macro_wetness(vec3 world_pos) {
	float n = texture(noisetex, world_pos.xz * 0.010 + 0.37).w;
	n += 0.5 * texture(noisetex, world_pos.xz * 0.023 + 0.71).x;
	n /= 1.5;
	return 0.55 + 0.45 * smoothstep(0.25, 0.75, n);
}

// Rain ripples: SEUS-style. The ripple pattern is baked into image/ripple.png as
// a vertical strip of 16 animation frames (tileable, several drops per tile,
// each with 2-3 expanding crests). We sample it in world space and blend the two
// neighbouring frames, so rings grow continuously instead of per-grid tiling.
vec2 zephyr_ripple_offset(vec3 world_pos, float time, out float wave_sum) {
	vec2 result = vec2(0.0);
	wave_sum = 0.0;

	const float FRAMES = 16.0;

	for (int layer = 0; layer < 2; ++layer) {
		float scale = layer == 0 ? 0.45 : 0.85;   // tile repeats per block
		float speed = layer == 0 ? 0.45 : 0.75;   // animation cycles per second

		float frame = fract(time * speed) * FRAMES;
		float f0    = floor(frame);
		float ff    = frame - f0;

		vec2 p = world_pos.xz * scale;
		vec2 q = fract(p);

		vec2 uv0 = vec2(q.x, (f0 + q.y) / FRAMES);
		vec2 uv1 = vec2(q.x, (mod(f0 + 1.0, FRAMES) + q.y) / FRAMES);

		vec4 s0 = texture(zephyr_ripple, uv0);
		vec4 s1 = texture(zephyr_ripple, uv1);

		vec2 n = mix(s0.rg, s1.rg, ff) * 2.0 - 1.0;
		float strength = mix(s0.a, s1.a, ff);

		result += n * (0.55 + 0.45 * strength);
		wave_sum += length(n);
	}

	return result * 0.5;
}

// Thin water lines running down vertical faces.
float zephyr_wall_streak(vec3 world_pos, vec3 normal, float time) {
	float horizontal = dot(world_pos.xz, vec2(-normal.z, normal.x));
	float cell       = floor(horizontal * 7.0);
	float h          = zephyr_rain_hash12(vec2(cell, 3.7));
	float y          = world_pos.y * 1.2 + time * (0.30 + 0.55 * h);
	float line       = sin(y * tau + h * 11.0);

	return smoothstep(0.55, 1.0, line * 0.5 + 0.5);
}

void zephyr_rain_surface(
	vec3 world_pos,
	vec3 flat_normal,
	vec3 view_dir,
	uint material_mask,
	bool is_hand,
	inout vec3 normal,
	inout vec3 albedo,
	inout vec3 f0,
	inout float roughness,
	inout float ssr_multiplier
) {
	float base_wet = clamp01(wetness * biome_may_rain);
	if (base_wet < 0.02 || is_hand) return;
	if (material_mask == MATERIAL_LEAVES) return;

	float rain    = base_wet * zephyr_macro_wetness(world_pos);
	float falling = clamp01(rain * rainStrength);
	float up      = clamp01(flat_normal.y);

	if (up > 0.55) {
		// One coherent wet coat for the whole ground. Wet mineral surfaces get
		// darker, smoother and more reflective; this is what makes puddles and
		// dry paving stop looking like two different materials.
		float coat = rain * ZEPHYR_RAIN_WETNESS;
		albedo *= 1.0 - 0.20 * coat;
		roughness = mix(roughness, 0.22, coat * 0.72);
		f0        = mix(f0, vec3(0.030), coat);
		ssr_multiplier = max(ssr_multiplier, coat * 1.00);

		// Impacts: normal-only ripples (no bright particles)
		if (falling > 0.01 && ZEPHYR_RAIN_RIPPLE > 0.0) {
			float fade  = smoothstep(0.0, 5.0, length(world_pos - cameraPosition));
			float wave;
			vec2 offset = zephyr_ripple_offset(world_pos, frameTimeCounter, wave);

			float k = falling * fade * ZEPHYR_RAIN_RIPPLE;
			normal = normalize(normal + vec3(offset.x, 0.0, offset.y) * 0.25 * k);

			// Rings also disturb the mirror: crests are slightly rougher, so the
			// circular wavefronts read as dark/light rings instead of glitter.
			roughness += clamp01(wave) * 0.10 * k;
		}
	} else if (up < 0.30) {
		// Wet walls: sheen + running water lines
		float coat = rain * ZEPHYR_RAIN_WETNESS;
		albedo   *= 1.0 - 0.12 * coat;
		roughness = mix(roughness, 0.32, coat * 0.45);
		f0        = mix(f0, vec3(0.034), coat);
		ssr_multiplier = max(ssr_multiplier, coat * 0.45);

		if (falling > 0.01) {
			float streak = zephyr_wall_streak(world_pos, flat_normal, frameTimeCounter);
			float fade   = smoothstep(0.0, 4.0, length(world_pos - cameraPosition));
			normal = normalize(normal + vec3(flat_normal.z, 0.0, -flat_normal.x) * streak * 0.05 * falling * fade);
		}
	}
}

#endif // INCLUDE_SURFACE_ZEPHYR_RAIN
