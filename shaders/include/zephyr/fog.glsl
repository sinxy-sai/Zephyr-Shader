#if !defined INCLUDE_ZEPHYR_FOG
#define INCLUDE_ZEPHYR_FOG

float zephyr_fog_amount(float dist, float y) {
	float height_falloff = exp2(-max(y, 0.0) / FOG_HEIGHT);
	float density = FOG_DENSITY * (0.35 + 0.65 * height_falloff);
	return 1.0 - exp(-dist * density);
}

#endif
