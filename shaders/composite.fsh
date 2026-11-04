#version 400 compatibility

#include "/settings.glsl"
in vec2 uv;

uniform sampler2D colortex0;

uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;
uniform vec3 fogColor;
uniform float rainStrength;

#include "/include/zephyr/math.glsl"
#include "/include/zephyr/tonemap.glsl"
#include "/include/zephyr/fog.glsl"

/* RENDERTARGETS: 0 */
layout (location = 0) out vec4 color;

uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform mat4 gbufferModelViewInverse;

float zephyr_linear_depth(float depth) {
	vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 view = gbufferProjectionInverse * ndc;
	return -view.z / view.w;
}

void main() {
	vec3 scene = texture(colortex0, uv).rgb;

	// simple fog based on linear depth
	float depth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;
	if (depth < 1.0) {
		float dist = zephyr_linear_depth(depth);
		float fog = zephyr_fog_amount(dist, 0.0);
		vec3 fog_col = mix(vec3(0.55, 0.62, 0.75), fogColor, 0.5);
		scene = mix(scene, fog_col, fog);
	}

	scene *= EXPOSURE;
	vec3 mapped = zephyr_agx(scene);

	// saturation
	float lum = zephyr_luminance(mapped);
	mapped = mix(vec3(lum), mapped, GRADE_SATURATION);

	// vignette
	float aspect = viewWidth / max(viewHeight, 1.0);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	float vig = smoothstep(1.25, 0.35, length(p));
	mapped *= mix(1.0, vig, VIGNETTE_INTENSITY);

	// grain
	float g = fract(sin(dot(gl_FragCoord.xy + fract(frameTimeCounter) * 1000.0, vec2(12.9898, 78.233))) * 43758.5453);
	mapped += (g - 0.5) * GRAIN_INTENSITY * 0.05;

	color = vec4(clamp(mapped, 0.0, 1.0), 1.0);
}

#include "/include/buffers.glsl"