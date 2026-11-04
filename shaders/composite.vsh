#version 400 compatibility

// Fullscreen pass vertex shader (Iris needs an explicit composite/final vsh)
in vec2 mc_Entity;
out vec2 uv;

void main() {
	uv = gl_MultiTexCoord0.xy;
	gl_Position = ftransform();
}
