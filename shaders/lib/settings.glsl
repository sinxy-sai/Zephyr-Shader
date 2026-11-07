// Zephyr Z1 feature parameters.
// Naming rule (D4): <module>_<parameter>. No quality presets at this stage.
#include "/settings.glsl"

#define ATMOSPHERE_DENSITY        1.00
#define ATMOSPHERE_MIE_G          0.76
#define ATMOSPHERE_SUN_INTENSITY  1.00

#define LIGHT_SUN_INTENSITY       3.20
#define LIGHT_SKY_INTENSITY       0.85
#define LIGHT_EMISSIVE_SCALE      1.60

#define SHADOW_ENABLED            1
#define SHADOW_SOFTNESS           1.00
#define SHADOW_BIAS               0.0008

#define FOLIAGE_TRANSLUCENCY      0.45
#define AO_STRENGTH               0.35

#define CLOUD_ENABLED             1
#define CLOUD_COVERAGE            0.58
#define CLOUD_STEPS               8
#define CLOUD_ALTITUDE          168.0
#define CLOUD_DENSITY             1.00

#define FOG_DENSITY               0.0042
#define FOG_HEIGHT_FALLOFF        0.026
#define FOG_INSCATTER_BOOST       1.25

#define VL_ENABLED                1
#define VL_STEPS                 12
#define VL_INTENSITY              0.55
#define VL_DECAY                  0.94

#define WAVE_AMPLITUDE            0.055
#define WATER_ABSORPTION          0.36
#define WATER_F0                  0.02

#define BLOOM_STRENGTH            0.42
#define BLOOM_THRESHOLD           1.05
#define BLOOM_RADIUS              1.00

#define EXPOSURE_EV               0.00
#define EXPOSURE_TARGET           0.22
#define EXPOSURE_ADAPT_SPEED      0.06
#define TONEMAP_EXPOSURE_BIAS     1.00
#define GRADE_SATURATION          1.14
#define GRADE_CONTRAST            1.04
