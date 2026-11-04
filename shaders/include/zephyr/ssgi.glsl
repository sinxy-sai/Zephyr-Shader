#if !defined INCLUDE_ZEPHYR_SSGI
#define INCLUDE_ZEPHYR_SSGI

// Screen-space one-bounce global illumination.
// Gathers already-lit pixels from the screen-space neighbourhood along a cosine
// weighted hemisphere around the reconstructed normal, giving coloured indirect
// light (neon bouncing off walls / wet street). Sampled in linear view space so
// the result is stable with TAA history.

vec3 zephyr_ssgi_view_pos(vec2 uv, float depth) {
	vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 view = gbufferProjectionInverse * ndc;
	return view.xyz / view.w;
}

float zephyr_ssgi_noise(float t) {
	return fract(52.9829189 * fract(dot(gl_FragCoord.xy + t, vec2(0.06711056, 0.00583715))));
}

vec3 zephyr_ssgi(vec2 uv, float depth) {
	if (depth >= 0.99999) return vec3(0.0);

	vec3 view_pos = zephyr_ssgi_view_pos(uv, depth);
	if (view_pos.z > -0.05) return vec3(0.0);

	// Reconstruct the normal from depth derivatives
	vec2 texel = view_pixel_size;
	float d0 = depth;
	float dx = texture(depthtex0, uv + vec2(texel.x, 0.0)).r;
	float dy = texture(depthtex0, uv + vec2(0.0, texel.y)).r;
	if (dx >= 0.99999 || dy >= 0.99999) return vec3(0.0);

	vec3 p0 = view_pos;
	vec3 p1 = zephyr_ssgi_view_pos(uv + vec2(texel.x, 0.0), dx);
	vec3 p2 = zephyr_ssgi_view_pos(uv + vec2(0.0, texel.y), dy);

	vec3 normal = normalize(cross(p1 - p0, p2 - p0));
	if (dot(normal, -normalize(p0)) < 0.0) normal = -normal;

	// Arbitrary orthonormal basis
	vec3 up = abs(normal.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(up, normal));
	vec3 bitangent = cross(normal, tangent);

	const int samples = 10;
	float radius = ZEPHYR_SSGI_RADIUS;

	float dither = 0.5; // deterministic pattern: less shimmering than per-frame noise

	vec3 indirect = vec3(0.0);
	float weight_sum = 0.0;

	for (int i = 0; i < samples; ++i) {
		float fi = (float(i) + dither) / float(samples);
		float phi = 6.2831853 * fract(fi * 7.0 + dither);
		float cos_theta = sqrt(1.0 - fi);
		float sin_theta = sqrt(fi);

		vec3 dir = normalize(
			tangent * (cos(phi) * sin_theta) +
			bitangent * (sin(phi) * sin_theta) +
			normal * cos_theta
		);

		// Short screen-space march
		const int steps = 4;
		for (int s = 1; s <= steps; ++s) {
			float t = radius * (float(s) / float(steps)) * (0.35 + 0.65 * sin_theta);
			vec3 probe_view = p0 + dir * t;

			vec4 clip = gbufferProjection * vec4(probe_view, 1.0);
			if (abs(clip.w) < 1e-5) break;
			vec2 probe_uv = clip.xy / clip.w * 0.5 + 0.5;
			if (clamp01(probe_uv) != probe_uv) break;

			float probe_depth = texture(depthtex0, probe_uv).r;
			if (probe_depth >= 0.99999) continue;

			vec3 surface_view = zephyr_ssgi_view_pos(probe_uv, probe_depth);

			// Hit when the ray went behind the surface
			float diff = surface_view.z - probe_view.z;
			if (diff > 0.0 && diff < 1.5) {
				vec3 gathered = texture(colortex5, probe_uv).rgb;
				float falloff = 1.0 - float(s) / float(steps + 1);
				float n_dot = max(dot(normal, normalize(surface_view - p0)), 0.0);
				indirect += gathered * falloff * (0.35 + 0.65 * n_dot);
				weight_sum += falloff;
				break;
			}
		}
	}

	if (weight_sum < 1e-4) return vec3(0.0);
	return indirect / weight_sum;
}

#endif // INCLUDE_ZEPHYR_SSGI
