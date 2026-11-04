#if !defined INCLUDE_SURFACE_ZEPHYR_RELIEF
#define INCLUDE_SURFACE_ZEPHYR_RELIEF

/*
  Fake material relief (bump from albedo luminance)
  -------------------------------------------------
  No resource pack / labPBR maps are installed, so instead of POM this derives a
  bump normal from the screen-space gradient of the albedo. It gives stone,
  bricks, planks and other noisy textures a subtle 3D relief, and makes wet
  surfaces catch the light in a less "flat painted" way.
*/
void zephyr_material_relief(vec3 position_scene, vec3 albedo, inout vec3 normal) {
#ifdef ZEPHYR_MATERIAL_RELIEF
	if (ZEPHYR_MATERIAL_RELIEF <= 0.0) return;

	float dist = length(position_scene);
	float fade = 1.0 - smoothstep(10.0, 30.0, dist);
	if (fade <= 0.001) return;

	vec3 dpx = dFdx(position_scene);
	vec3 dpy = dFdy(position_scene);
	if (dot(dpx, dpx) < 1e-8 || dot(dpy, dpy) < 1e-8) return;

	float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	float lx = clamp(dFdx(lum), -0.30, 0.30);
	float ly = clamp(dFdy(lum),  -0.30, 0.30);

	// Tangent frame from the position derivatives (same space as `normal`)
	vec3 t = normalize(dpx);
	vec3 b = normalize(dpy);

	normal = normalize(normal - (t * lx + b * ly) * (ZEPHYR_MATERIAL_RELIEF * 2.5 * fade));
#endif
}

#endif // INCLUDE_SURFACE_ZEPHYR_RELIEF
