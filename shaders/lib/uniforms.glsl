// Zephyr Z1 shared uniforms.
// Samplers are declared per pass on purpose: a gbuffer must never declare the
// colortex it writes to (feedback loop / A3 contract).

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
// M7 temporal reprojection (Iris/OptiFine standard uniforms).
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

// Iris-only: xyz = strike position (world space), w = current flash strength.
// Zero when no bolt is active, so it is safe in every pass.
uniform vec4 lightningBoltPosition;

uniform float sunAngle;
uniform float worldTime;
uniform float rainStrength;
uniform float wetness;
uniform float eyeAltitude;
uniform float frameTimeCounter;
// Iris: duration of the previous frame in seconds. Used to evaluate the
// foliage wave at t-1 for the TAA velocity buffer (M20).
uniform float frameTime;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float near;
uniform float far;

uniform int frameCounter;
uniform int isEyeInWater;
uniform int moonPhase;
