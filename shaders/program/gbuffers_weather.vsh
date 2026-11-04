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
uniform float frameTimeCounter;

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

	// Zephyr: per-drop alpha variation only. (Earlier versions also stretched and
	// narrowed the quads around world anchors; that tore quads that crossed a
	// block boundary and produced the small blue "particle" specks.)
	rain_seed = fract(sin(dot(floor(world_pos.xz * 5.0), vec2(12.9898, 78.233))) * 43758.5453);

	float wind_phase = dot(world_pos, vec3(3.0, 0.5, 3.0)) + frameTimeCounter * 0.20;
	vec2  rot        = vec2(sin(wind_phase), cos(wind_phase));
	vec2  wind       = (vec2(ZEPHYR_RAIN_WIND_X, ZEPHYR_RAIN_WIND_Z) + rot * ZEPHYR_RAIN_DISTURBANCE);
	world_pos.xz    += wind * scene_pos.y * 0.06;

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

