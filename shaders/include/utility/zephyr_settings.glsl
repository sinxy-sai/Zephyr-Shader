// Zephyr S0 settings. Keep names stable for later quality tiers.
#ifndef ZEPHYR_SETTINGS_GLSL
#define ZEPHYR_SETTINGS_GLSL

#define ZEPHYR_QUALITY_LOW 0
#define ZEPHYR_QUALITY_MEDIUM 1
#define ZEPHYR_QUALITY_HIGH 2

#ifndef ZEPHYR_QUALITY
#define ZEPHYR_QUALITY ZEPHYR_QUALITY_LOW
#endif

#ifndef ZEPHYR_EXPOSURE
#define ZEPHYR_EXPOSURE 0.0
#endif

#ifndef ZEPHYR_SUN_STRENGTH
#define ZEPHYR_SUN_STRENGTH 1.0
#endif

#endif
