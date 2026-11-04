/*
  Zephyr | shadows: own PCF sampling (P4 of the Photon replacement plan)
  Contract (host must declare/include before this module):
    uniforms: shadowtex0, shadowtex1, shadowModelView, shadowProjection,
              shadowDistance, light_dir, cameraPosition
    helpers:  transform, project_ortho, distort_shadow_space, get_shadow_bias,
              lightmap_shadows (Photon geometry conventions, kept as the seam)
  Interface:
    vec3 zephyr_shadows(vec3 scene_pos, vec3 flat_normal, float skylight,
                        float cloud_shadows, out float distance_fade)
  Returns: per-channel shadow factor (1 = lit, 0 = shadowed), same meaning as
           Photon's calculate_shadows(). Softness grows with shadow distance so
           far shadows do not turn into a hard staircase.
  Toggle: ZEPHYR_OWN_SHADOWS
*/
#ifndef INCLUDE_ZEPHYR_SHADOWS
#define INCLUDE_ZEPHYR_SHADOWS

#ifndef ZEPHYR_SHADOW_PCF_TAPS
	#define ZEPHYR_SHADOW_PCF_TAPS 8
#endif
#ifndef ZEPHYR_SHADOW_PCF_RADIUS
	#define ZEPHYR_SHADOW_PCF_RADIUS 1.35
#endif

vec3 zephyr_shadows(
	vec3 scene_pos,
	vec3 flat_normal,
	float skylight,
	float cloud_shadows,
	out float distance_fade
) {
	distance_fade = 0.0;

	float NoL = dot(flat_normal, light_dir);
	if (NoL < 1e-3) return vec3(0.0);

	vec3 bias = get_shadow_bias(scene_pos, flat_normal, NoL, skylight);

	vec3 shadow_view = transform(shadowModelView, scene_pos + bias);
	vec3 shadow_clip = project_ortho(shadowProjection, shadow_view);
	vec3 shadow_screen = distort_shadow_space(shadow_clip) * 0.5 + 0.5;

	distance_fade = pow32(max(
		max_of(abs(shadow_screen.xy * 2.0 - 1.0)),
		length_squared(scene_pos.xz) * rcp(shadowDistance * shadowDistance)
	));

	vec3 distant_shadow = vec3(lightmap_shadows(skylight, NoL));
	if (distance_fade >= 1.0) return distant_shadow;

	// Radius grows with the distance to the shadow map centre so far shadows are
	// softer, approximating a wider penumbra without a blocker search.
	float radius = shadow_map_pixel_size * ZEPHYR_SHADOW_PCF_RADIUS
	             * (1.0 + 2.0 * distance_fade)
	             * (5.0 - 4.0 * cloud_shadows);

	vec3 shadow = vec3(0.0);

	for (int i = 0; i < ZEPHYR_SHADOW_PCF_TAPS; ++i) {
		float angle = 6.2831853 * (float(i) + 0.5) / float(ZEPHYR_SHADOW_PCF_TAPS);
		vec2 offset = vec2(cos(angle), sin(angle)) * radius;
		vec2 uv = shadow_screen.xy + offset;
		shadow += vec3(texture(shadowtex1, vec3(uv, shadow_screen.z)));
	}

	shadow /= float(ZEPHYR_SHADOW_PCF_TAPS);
	return mix(shadow, distant_shadow, distance_fade);
}

#endif // INCLUDE_ZEPHYR_SHADOWS
