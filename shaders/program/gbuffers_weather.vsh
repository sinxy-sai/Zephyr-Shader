/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/gbuffers_weather:
  Handle rain and snow particles

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 uv;

flat out vec4 tint;

out float rain_seed;

// ------------
//   Uniforms
// ------------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec3 cameraPosition;

uniform int frameCounter;

uniform vec2 taa_offset;
uniform vec2 view_pixel_size;

uniform float rainStrength;
uniform float biome_may_snow;

void main() {
	uv = mat2(gl_TextureMatrix[0]) * gl_MultiTexCoord0.xy + gl_TextureMatrix[0][3].xy;

	tint = gl_Color;

	vec3 view_pos = transform(gl_ModelViewMatrix, gl_Vertex.xyz);

	vec3 scene_pos = transform(gbufferModelViewInverse, view_pos);
	vec3 world_pos = scene_pos + cameraPosition;

	// Zephyr rain streaks: longer, thinner, with per-drop variation.
	// Rain quads are one block tall, 0.2 wide and aligned to that grid, so we
	// can stretch them around the nearest block/grid anchor without snapping.
	rain_seed = fract(sin(dot(floor(world_pos.xz * 5.0), vec2(12.9898, 78.233))) * 43758.5453);
#ifdef ZEPHYR_RAIN_SHAPE
	if (rainStrength > 0.01 && biome_may_snow < 0.5) {
		const float vertical_scale = 1.0 + 1.15 * ZEPHYR_RAIN_STREAK;
		const float width_scale    = 1.0 - 0.45 * ZEPHYR_RAIN_STREAK;

		float seed = rain_seed;

		// Stretch around the block base, with a little per-drop length variance
		float stretch = vertical_scale * (0.75 + 0.5 * seed);
		float anchor_y = floor(world_pos.y);
		world_pos.y = anchor_y + (world_pos.y - anchor_y) * stretch;

		// Thin around the 0.2-wide grid cell centre
		vec2 anchor_xz = floor(world_pos.xz / 0.2) * 0.2 + 0.1;
		world_pos.xz = anchor_xz + (world_pos.xz - anchor_xz) * width_scale;
	}
#endif

	scene_pos = world_pos - cameraPosition;

#ifdef SLANTED_RAIN
	const float rain_tilt_amount = 0.25;
	const float rain_tilt_angle  = 30.0 * degree;
	const vec2  rain_tilt_offset = rain_tilt_amount * vec2(cos(rain_tilt_angle), sin(rain_tilt_angle));

	float tilt_wave = 0.7 + 0.3 * sin(dot(world_pos, vec3(5.0)));
	scene_pos.xz -= rain_tilt_offset * tilt_wave * scene_pos.y;
#endif

	view_pos = transform(gbufferModelView, scene_pos);

	vec4 clip_pos = project(gl_ProjectionMatrix, view_pos);

#if   defined TAA && defined TAAU
	clip_pos.xy  = clip_pos.xy * taau_render_scale + clip_pos.w * (taau_render_scale - 1.0);
	clip_pos.xy += taa_offset * clip_pos.w;
#elif defined TAA
	clip_pos.xy += taa_offset * clip_pos.w * 0.66;
#endif

	gl_Position = clip_pos;
}

