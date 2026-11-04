/*
  Zephyr | program final (self-hosted)
  No Photon includes are used here except the colortex layout contract
  (include/buffers.glsl), which is part of the Iris pipeline declaration.
*/
layout (location = 0) out vec3 fragment_color;

in vec2 uv;

uniform sampler2D colortex0; // display-referred scene colour

uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;

#include "/include/zephyr/engine/final.glsl"

void main() {
	ivec2 texel = ivec2(gl_FragCoord.xy);
	fragment_color = zephyr_final_pass(
		colortex0,
		texel,
		uv,
		vec2(viewWidth, viewHeight),
		frameTimeCounter
	);
}

#include "/include/buffers.glsl"
