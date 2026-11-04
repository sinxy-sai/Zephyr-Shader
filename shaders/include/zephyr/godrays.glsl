/*
  Zephyr | post: screen-space god rays
  Contract (host must declare):
    uniforms: sampler2D colortex5, depthtex0; mat4 gbufferModelView, gbufferProjection;
              vec3 sun_dir; float aspectRatio;
  Interface:
    vec3 zephyr_godrays(vec2 uv, float exposure)
  Notes: marches only *sky* pixels toward the sun so occluders stay dark; returns
         additive light in the same exposure space as the host scene colour.
*/
#ifndef ZEPHYR_GODRAYS_SAMPLES
	#define ZEPHYR_GODRAYS_SAMPLES 28
#endif
#ifndef ZEPHYR_GODRAYS_DECAY
	#define ZEPHYR_GODRAYS_DECAY 0.94
#endif
#ifndef ZEPHYR_GODRAYS_FINAL_SCALE
	#define ZEPHYR_GODRAYS_FINAL_SCALE 0.55
#endif

// -----------------------------------------------------------------------------
//   Zephyr god rays
//   Screen-space light shafts that do NOT depend on Photon's sun visibility:
//   they march from the pixel toward the sun and accumulate *sky* pixels only,
//   so gaps between buildings / under bridges produce visible shafts while
//   occluders stay dark.
// -----------------------------------------------------------------------------
vec3 zephyr_godrays(vec2 uv, float exposure) {
#ifdef ZEPHYR_GODRAYS
	vec3 sun_view = mat3(gbufferModelView) * sun_dir;
	if (sun_view.z > -0.05) return vec3(0.0);

	vec4 clip = gbufferProjection * vec4(sun_view * 1000.0, 1.0);
	if (abs(clip.w) < 1e-5) return vec3(0.0);
	vec2 sun_uv = clip.xy / clip.w * 0.5 + 0.5;
	if (sun_uv.x < -0.4 || sun_uv.x > 1.4 || sun_uv.y < -0.4 || sun_uv.y > 1.4) return vec3(0.0);

	const int samples = ZEPHYR_GODRAYS_SAMPLES;

	vec2  delta  = (sun_uv - uv) / float(samples);
	vec2  coord  = uv;
	float weight = 1.0;
	float wsum   = 0.0;
	vec3  color  = vec3(0.0);

	for (int i = 0; i < samples; ++i) {
		coord += delta;
		if (clamp(coord, vec2(0.0), vec2(1.0)) != coord) break;

		float depth = texelFetch(depthtex0, ivec2(coord * vec2(textureSize(depthtex0, 0))), 0).x;

		// only sky pixels scatter into the shaft
		float sky = step(0.99999, depth);
		if (sky > 0.5) {
			vec3 sample_color = texture(colortex5, coord).rgb;
			float lum = dot(sample_color, vec3(0.2126, 0.7152, 0.0722));
			// keep the shaft bright only where the sky is actually bright (sun glow)
			float glow = smoothstep(0.15, 3.5, lum);
			color += sample_color * glow * weight;
			wsum  += weight;
		}
		weight *= ZEPHYR_GODRAYS_DECAY;
	}

	if (wsum < 1e-4) return vec3(0.0);

	float coverage = wsum / float(samples);
	vec3  result   = color / max(wsum, 1e-4);

	// Only the brightest, most open paths toward the sun should glow, and the
	// effect fades with distance from the sun on screen. Without this the whole
	// frame turns into a bright wash.
	float openness = pow(clamp01(coverage), 3.0);
	float falloff  = 1.0 - smoothstep(0.05, 0.75, length((uv - sun_uv) * vec2(aspectRatio, 1.0)));

	return result * openness * falloff * ZEPHYR_GODRAYS_INTENSITY * exposure * ZEPHYR_GODRAYS_FINAL_SCALE;
#else
	return vec3(0.0);
#endif
}

