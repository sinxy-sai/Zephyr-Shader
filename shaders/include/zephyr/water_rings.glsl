/*
  Zephyr | surface: rain impact rings on water
  Contract (host must declare): uniforms none; uses settings ZEPHYR_WATER_RINGS.
  Units: coord = world-space water tangent coordinates (blocks), time = seconds,
         rain = 0..1 rain strength.
*/
// Zephyr: rain impact rings on the water surface. Procedural (no texture) so it
// needs no extra sampler and costs almost nothing: each grid cell spawns one
// expanding ring, only ~40%% of cells are active so it doesn't tile visibly.
vec2 zephyr_water_rain_rings(vec2 coord, float time, float rain) {
	vec2 result = vec2(0.0);
	if (rain < 0.01) return result;

	for (int layer = 0; layer < 2; ++layer) {
		float scale = 2.4 + float(layer) * 1.6;   // cells per block
		vec2 p = coord * scale;
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;

		float h = fract(sin(dot(cell + float(layer) * 31.7, vec2(12.9898, 78.233))) * 43758.5453);
		if (h < 0.55) continue;

		float phase = fract(time * (0.9 + float(layer) * 0.5) + h * 7.0);
		float r = length(f) * 2.0;               // 0..1 over the cell
		float radius = phase;

		float ring = exp2(-sqr((r - radius) * 9.0)) * (1.0 - phase) * (1.0 - phase);
		result += normalize(f + 1e-5) * ring;
	}

	return result;
}

