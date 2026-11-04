#if !defined INCLUDE_SURFACE_ZEPHYR_RAIN
#define INCLUDE_SURFACE_ZEPHYR_RAIN

/*
--------------------------------------------------------------------------------
  Zephyr rain-on-surface
  ----------------------
  Vanilla/Photon only wets the ground inside scattered puddles. This layer makes
  every rain-exposed surface react to the rain:

  - horizontal faces: expanding ripple rings (each drop = one ring), plus a
    glossy "wet coat" that survives after the rain stops (wetness, not rainStrength)
  - vertical faces: thin water streaks that slowly run down, and a wet sheen so
    walls pick up neon reflections while it rains

  Intended to be included after material decoding and BEFORE rain puddles, so
  that real puddles (mirror-like) still win where they exist.
--------------------------------------------------------------------------------
*/

float zephyr_rain_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Expanding ripple rings. Returns a world-space horizontal normal offset.
vec2 zephyr_ripple_offset(vec3 world_pos, float time, float strength) {
	vec2 result = vec2(0.0);

	for (int layer = 0; layer < 2; ++layer) {
		float scale = layer == 0 ? 4.2 : 6.7;
		float speed = layer == 0 ? 1.35 : 1.95;

		vec2  p      = world_pos.xz * scale;
		vec2  cell   = floor(p);
		vec2  f      = fract(p);
		float h0     = zephyr_rain_hash12(cell + float(layer) * 31.7);
		vec2  center = vec2(zephyr_rain_hash12(cell + 11.3), zephyr_rain_hash12(cell + 5.9)) * 0.7 + 0.15;
		float phase  = fract(time * speed + h0);

		vec2  d      = f - center;
		float dist   = length(d);
		float radius = phase * 0.42;

		float ring = exp2(-abs(dist - radius) * 70.0);
		      ring *= (1.0 - phase) * smoothstep(0.0, 0.06, phase);

		result += d * ring;
	}

	return result * strength;
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
	float rain = clamp01(wetness * biome_may_rain);       // surface is wet
	float falling = clamp01(rain * rainStrength);          // drops are hitting it now

	if (rain < 0.02 || is_hand) return;
	if (material_mask == MATERIAL_LEAVES) return;

	float up = clamp01(flat_normal.y);

	if (up > 0.55) {
		// Glossy wet coat, kept after the rain stops
		float coat = rain * ZEPHYR_RAIN_WETNESS;
		roughness = mix(roughness, 0.22, coat * 0.65);
		f0        = mix(f0, vec3(0.030), coat);
		ssr_multiplier = max(ssr_multiplier, coat * 0.75);
		albedo   *= 1.0 - 0.14 * coat;

		// Ripple rings where drops are actually falling
		if (falling > 0.01 && ZEPHYR_RAIN_RIPPLE > 0.0) {
			float fade = smoothstep(0.0, 6.0, length(world_pos - cameraPosition));
			vec2  offset = zephyr_ripple_offset(world_pos, frameTimeCounter, ZEPHYR_RAIN_RIPPLE);
			      offset *= falling * fade;
			normal = normalize(normal + vec3(offset.x, 0.0, offset.y) * 0.42);
		}
	} else if (up < 0.30) {
		// Wet walls: sheen + faint vertical water lines
		float coat = rain * ZEPHYR_RAIN_WETNESS;
		roughness = mix(roughness, 0.30, coat * 0.50);
		f0        = mix(f0, vec3(0.036), coat);
		ssr_multiplier = max(ssr_multiplier, coat * 0.45);
		albedo   *= 1.0 - 0.10 * coat;

		if (falling > 0.01) {
			float streak = zephyr_wall_streak(world_pos, flat_normal, frameTimeCounter);
			float fade   = smoothstep(0.0, 4.0, length(world_pos - cameraPosition));
			normal = normalize(normal + vec3(flat_normal.z, 0.0, -flat_normal.x) * streak * 0.055 * falling * fade);
		}
	}
}

#endif // INCLUDE_SURFACE_ZEPHYR_RAIN
