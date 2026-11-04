/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/gbuffers_weather:
  Handle rain and snow particles

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout (location = 0) out vec4 frag_color;

/* RENDERTARGETS: 13 */

in vec2 uv;

flat in vec4 tint;

in float rain_seed;

// ------------
//   Uniforms
// ------------

uniform sampler2D gtexture;

uniform int frameCounter;

uniform vec3 sun_dir;

uniform vec2 taa_offset;
uniform vec2 view_pixel_size;

uniform float biome_may_snow;

#include "/include/lighting/colors/weather_color.glsl"
#include "/include/utility/encoding.glsl"

const uint rain_flag = 253u;
const uint snow_flag = 254u;

void main() {
#if defined TAA && defined TAAU
	vec2 coord = gl_FragCoord.xy * view_pixel_size * rcp(taau_render_scale);
	if (clamp01(coord) != coord) discard;
#endif

	vec4 base_color = texture(gtexture, uv);
	// Higher cutout: the faint 1-pixel blobs of the vanilla rain texture are what
	// read as "blue particles" on screen. Only keep the actual streaks.
	if (base_color.a < 0.30) discard;

	bool is_rain = (abs(base_color.r - base_color.b) > eps);

#ifdef ZEPHYR_RAIN_SHAPE
	// Per-drop opacity/width variation: vanilla rain is perfectly uniform.
	float drop_alpha = mix(1.0, 0.45 + 0.9 * rain_seed, ZEPHYR_RAIN_STREAK);
#else
	float drop_alpha = 1.0;
#endif

	vec3 rain_color = get_rain_color();

	// Complementary-style rain tint: the raw Photon rain color is strongly blue
	// (0.49, 0.65, 1.00) and its small specks read as "blue particles". Keep only
	// a hint of blue and push it toward neutral grey, like Complementary does.
	float rain_lum = dot(rain_color, vec3(0.2126, 0.7152, 0.0722));
	vec3  rain_grey = vec3(rain_lum) * vec3(0.97, 0.99, 1.01);
	rain_color = mix(rain_color, rain_grey, 0.90);
	rain_color *= 0.85;

	frag_color = is_rain
		? vec4(rain_color, RAIN_OPACITY * base_color.a * drop_alpha) * tint
		: vec4(get_snow_color(), SNOW_OPACITY * base_color.a) * tint;
	frag_color.rgb *= frag_color.a;
}

