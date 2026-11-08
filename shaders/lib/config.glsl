// Zephyr Z1 buffer contract.
// The table in docs/dev/plan/02-pipeline.md must match this file exactly.

// Iris reads the *identifier* on the right-hand side of colortexNFormat, but
// GLSL still needs those identifiers to exist as compile-time constants.
const int RGB8 = 0;
const int RGBA8 = 0;
const int RGBA16 = 0;
const int RG16F = 0;
const int RGB16F = 0;
const int RGBA16F = 0;
const int RGBA32F = 0;
const int R11F_G11F_B10F = 0;

const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
const int colortex2Format = RGBA16F;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
const int colortex5Format = RGBA16F;
// TAA: colortex6 is read AND written by composite2 in the same pass. Iris
// gives such a feedback attachment an implicit ping-pong pair, so it must
// never be cleared and must NOT have a flip. entry in shaders.properties.
const int colortex6Format = RGBA16F;
const int colortex7Format = RGBA16F;
const bool colortex6Clear = false;

const bool colortex3MipmapEnabled = true;

// M13: these ids live in colortex1.a (spare slot of outData). colortex0.a is
// reserved for the real alpha so Iris can blend translucent geometry.
#define MAT_SOLID       0.0
#define MAT_WATER       1.0
#define MAT_TRANSLUCENT 2.0
#define MAT_HAND        3.0
#define MAT_EMISSIVE    4.0

#define ZEPHYR_PI       3.14159265359
