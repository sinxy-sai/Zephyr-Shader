#if !defined INCLUDE_ZEPHYR_CONTACT_SHADOWS
#define INCLUDE_ZEPHYR_CONTACT_SHADOWS

float zephyr_contact_shadow(vec3 position_scene, vec3 sun_direction, vec3 flat_normal, float dither) {
	const int   steps    = 10;
	const float max_dist = 0.60;

	float occlusion = 0.0;
	vec3 origin = position_scene + flat_normal * 0.02;

	for (int i = 1; i <= steps; ++i) {
		float t = (float(i) + dither) / float(steps);
		vec3 probe_scene = origin + sun_direction * (t * max_dist);
		vec3 probe_view = mat3(gbufferModelView) * probe_scene + gbufferModelView[3].xyz;
		if (probe_view.z > -0.05) break;
		vec4 clip = gbufferProjection * vec4(probe_view, 1.0);
		if (abs(clip.w) < 1e-5) break;
		vec3 probe_screen = clip.xyz / clip.w * 0.5 + 0.5;
		if (any(lessThan(probe_screen.xy, vec2(0.0))) || any(greaterThan(probe_screen.xy, vec2(1.0)))) break;
		float scene_depth = texture(depthtex1, probe_screen.xy).r;
		float probe_depth = probe_screen.z;
		float bias = 0.0020 + 0.020 * t * t;
		if (scene_depth < probe_depth - bias) occlusion = max(occlusion, (1.0 - t) * (1.0 - t));
	}

	return 1.0 - occlusion * ZEPHYR_CONTACT_SHADOWS_STRENGTH;
}

#endif
