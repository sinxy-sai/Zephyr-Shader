# Changelog

## v3.1 — 工程化重构（Zephyr 层模块化 + 契约化）（2026-11-05）

详细报告见 `docs/refactor-report.md`（坏味道清单 / SOLID 映射 / 改动点 / 测试要点 /
Photon 替换路线）。本轮只做「不改变行为」的重构：

- `c14_color_grading.fsh`：226 → 177 行，内联光柱抽成 `include/zephyr/godrays.glsl`，
  采样数/衰减/系数改为具名常量（`ZEPHYR_GODRAYS_SAMPLES/DECAY/FINAL_SCALE`）
- `post_processing/zephyr_cinematic.glsl` → `include/zephyr/cinematic.glsl`，
  `c14` 与 `final.fsh` 的 include 同步更新
- `surface/water_normal.glsl` 内联的水面涟漪抽成 `include/zephyr/water_rings.glsl`
- 每个 Zephyr 模块头部加 **Contract 注释**（host 必须声明的 uniform / 函数签名 / 单位）
- 删除已废弃的 SSGI 模块（v3.0 已移除）

校验：209/209 compiled, 0 failed（行为不变）。


## v3.0 — 移除 SSGI（拖影/反馈环问题）（2026-11-05）

实机反馈：SSGI 出现明显拖影。根因有两个，确实是设计问题：

1. **读写同一张 buffer 的反馈环**：SSGI 放在 `c1_blend_layers`（该 pass 的输出目标就是
   `colortex0`），却又从 `colortex0` 采样邻居颜色 → 同一 pass 内读写同一渲染目标，
   行为未定义，硬件上表现为上一帧内容被反复混进来 = 拖影
2. **没有重投影**：即使换个 buffer，逐像素屏幕空间采样在相机/物体移动时仍会拖尾

结论：这个近似做不到「稳定」，直接移除：

- `c1_blend_layers.fsh`：删除 SSGI include 与叠加
- 删除 `include/zephyr/ssgi.glsl`
- 移除 `ZEPHYR_SSGI / _STRENGTH / _RADIUS` 设置、菜单项、滑块与语言条目

间接光仍由 Photon 自带的 SH 天光 + 反弹光（`BOUNCED_LIGHT_I`）+ 体积光提供。
如果以后要做真 GI，需要「独立渲染目标 + 历史重投影 + 时域降噪」，而不是在合成
pass 里直接读自己。


## v2.9 — 水体升级：焦散 + 浑浊度 + 岸线（2026-11-05）

在 Photon 已有的 Gerstner 波浪 / 视差 / 吸收 / 折射基础上调默认与开关：

- 打开 `WATER_CAUSTICS`（水下焦散，之前是关的）
- 浑浊度 `WATER_SCATTERING 0.01 → 0.02`（河水/雨水该有的散射）
- 吸收系数 `R 0.39→0.45, G 0.14→0.16, B 0.07→0.08`（红光衰减更快，
  近处偏青、远处转深蓝，更有水体体积感）
- 岸线高光 `WATER_EDGE_HIGHLIGHT_INTENSITY 1.00 → 1.30`（岸边白色浪线更明显）
- 波浪强度 `WATER_WAVE_STRENGTH 1.00 → 1.15`
- 配合 v2.6 的雨滴涟漪（`ZEPHYR_WATER_RINGS`），雨天水面既有大波浪也有细环

实机：`shots/v2.9-water-upgrade.jpg`（本轮截图机位偏地面，水面在画面外；
下次可以对着河面再截一张对比）


## v2.8 — 天空升级：臭氧 + 多次散射光晕 + 夜间光污染（2026-11-05）

- **臭氧吸收**：天顶方向压一点绿/红（`tint *= mix(vec3(1), vec3(0.90,0.96,1.10), up²·0.55)`），
  黄昏时高空更深的蓝、地平线保持暖色，这是真实暮色天空的关键
- **多次散射近似**：太阳周围从「一个硬光斑」变成「宽 halo + 紧核心」两层叠加
  （`pow(cos,2.5)*0.55` + `pow(cos,12)*1.20`），日落地平线过渡更自然
- **夜间**：新增 airglow（极弱蓝）+ 城市光污染地平线暖光，
  强度由 `ZEPHYR_SKY_CITY_GLOW`（默认 0.35）控制，只作用于天空
- 截图：`shots/v2.8-dusk-sky.jpg`、`shots/v2.8-night-sky.jpg`


## v2.7 — 反射探针兜底：镜面遮蔽（2026-11-05）

在 v2.2 的「粗糙度感知天空反射」基础上，补上**镜面遮蔽**：

- `d4_deferred_shading` 的反射结果乘以 `mix(0.35, 1.0, sqrt(ao))`
- 作用：缝隙、物体底部、墙角等 GTAO 判定为遮蔽的地方，天空反射不再「漏光」，
  反射探针兜底亮度和周围直射/环境光一致
- 没有改 `get_specular_reflections()` 的签名（其它程序 water/lightning/hand 也在调用，
  改签名会连累 12 个入口），只在 d4 调用点乘系数


## v2.6 — 水面雨滴涟漪（程序化，无额外贴图）（2026-11-05）

`include/surface/water_normal.glsl` 增加 `zephyr_water_rain_rings()`：
每格随机一个雨滴，环随时间扩散、随 (1-phase)² 淡出，两层不同尺度叠加，
只作用于接近水平的水面，强度 `* rainStrength`，只在雨天出现。

- 设置：`ZEPHYR_WATER_RINGS`（默认 0.60，0 关闭）
- 程序化实现，不需要额外 sampler/贴图，也不会触发纹理声明相关的加载问题
- 复用 Photon 已有的 Gerstner 波浪 + 视差，环只作为叠加扰动

实机：`shots/v2.6-water-rain-rings.jpg`（12500 雨，河边）

## 关于「CSM 级联阴影」

调研结论：**在本管线里做不到干净的 CSM**。Iris/OptiFine 每帧只渲染一次
shadow map（`shadowtex0/1`），composite 阶段无法再触发一次场景渲染，因此无法
像游戏引擎那样为每个级联渲染一张 shadow map。而 Photon 的阴影已经是
**PCSS**（`blocker_search()` 求平均遮挡深度 → 计算半影 → 变半径 PCF + 锐化）
+ `SHADOW_VPS` 方差阴影，属于这条管线的上限附近。提升阴影精度的可行方向只剩：
- 提高 `shadowMapResolution` / 调小 `shadowDistance`（取舍）
- 接触阴影（v2.1 已做）
- SSR/反射探针来补远处视觉


## v2.5 — SSGI 移到 TAA 之前（消除静态颗粒）（2026-11-05）

上一版 SSGI 在 c14（TAA 之后），采样噪声不会被时域累积，画面有静态颗粒。
这版把它挪到 `c1_blend_layers`（合成层 + 雾之后、TAA 之前）执行：

- `c1_blend_layers.fsh`：在最终 `fragment_color` 合成完后加 `zephyr_ssgi(...)`
- SSGI 的 gather 源从 `colortex5` 改为 `colortex0`（c1 里当前帧场景色）
- 移除 c14 里的 SSGI hook（避免重复叠加）
- 采样方向改为固定 pattern（TAA 会跨帧累积，不再需要逐帧 dither）

实机：`shots/v2.5-ssgi-pretaa-night.jpg`（18000 夜，街道，颗粒消失）


## v2.4 — 屏幕空间一次反弹 GI（SSGI）（2026-11-05）

`include/zephyr/ssgi.glsl`：从深度重建视空间位置与法线，在半球内做
cosine 加权採样 + 短距离屏幕空间 march，命中后取场景颜色（colortex5）作为
间接光，乘 `ZEPHYR_SSGI_STRENGTH` 加进 HDR 场景（在 c14 里、曝光之后）。

- `ZEPHYR_SSGI`（默认开）、`ZEPHYR_SSGI_STRENGTH`（默认 0.35）、
  `ZEPHYR_SSGI_RADIUS`（默认 1.5 格）
- 固定 10 方向 pattern（不是逐帧噪声）以减少闪烁；c14 在 TAA 之后，所以仍会有
  一点静态颗粒感 —— 这是本版已知限制，下一版计划把 SSGI 挪到 TAA 之前的 pass
  （c1）做时域累积
- 中途踩坑：把 SSGI 插进 c1 时脚本出错（`s.replace(x, s)`）导致 c1 文件被复制
  一份，编译报 `eps` 重定义；已 `git checkout` 还原，c1 未改动

主要用途：霓虹/黄昏墙面在地面上的彩色间接光、街角暗部的色彩反弹。


## v2.3 — P2 第一步：体积地面薄雾 + 局部光雾（2026-11-05）

Photon 本身已有 LPV 体积光（`VL` + `LPV_VL`，24 步 raymarch、0.5 分辨率），
所以这轮不是从零写 froxel，而是在它的体积光系数里加两层 Zephyr 的控制：

- **地面薄雾层**（`include/fog/lpv_fog.glsl`）：
  `mist = ZEPHYR_MIST_DENSITY * exp2(-(y - SEA_LEVEL)/ZEPHYR_MIST_HEIGHT)`，
  直接加到体积散射/消光系数里 —— 薄雾贴地、几格高度内衰减，街道上会形成
  「灯光周围的雾层」，而不是整屏发白
- **局部光雾增强**：体积光采样到的 LPV 发射光乘 `ZEPHYR_LIGHT_FOG_SCALE`
  （默认 1.60），让霓虹/路灯在雾里的辉光更明显

设置（大气/雾 页）：
`ZEPHYR_MIST`（开关）、`ZEPHYR_MIST_DENSITY`（默认 0.0060）、
`ZEPHYR_MIST_HEIGHT`（默认 5.0 格）、`ZEPHYR_LIGHT_FOG_SCALE`（默认 1.60）

实机：`shots/v2.3-mist-night.jpg`（18000 + 雨，街道视角）


## v2.2 — 反射兜底：粗糙度感知的天空反射（2026-11-05）

SSR 打不到的时候（屏幕外、被遮挡）Photon 直接回退「一条方向采样天空图」，
导致湿地面/水面的反射像一面破镜子：近处有细节、远处突然变成一张平整天空。

真正的反射探针（cubemap 抓取 + 预过滤）在 Iris 里要额外多 pass 渲染场景，成本
很高；这里用便宜的近似先把最刺眼的问题修掉：

- `get_sky_reflection()` 增加 `roughness` 参数：粗糙度 > 0.06 时，围绕反射方向
  在 ±(roughness·0.30) 弧度内做 5 次采样（中心 + 4 个正交方向）取平均
  → SSR miss 的天空反射按粗糙度自然变糊，和远处 SSR 命中结果过渡更连续
- `trace_specular_ray()` 增加 `roughness` 透传，两处调用都传 `material.roughness`

这是 P1 的最后一项（「SSR 探针兜底」的可行近似版）。


## v2.1 — P1：AgX 色调映射 + 自动曝光 + 接触阴影（2026-11-05）

### AgX 色调映射
Photon 原来的 tonemap（Lottes/ACES）在日落会把高光压成一块饱和的橙黄。换成
AgX（Sobotka/Blender AgX base）后高光会往白色/柔和色偏，不再「糊成橙色」：

- `tonemap_operators.glsl` 新增 `tonemap_agx()`（inset 矩阵 → log2 EV 映射
  [-12.47, 4.03] → 对比曲线 → outset 矩阵 → 轻微 punchy + gamma）
- Photon 的 HDR 尺度比 AgX 预期高很多，加 `ZEPHYR_AGX_PRESCALE`（默认 0.075）
  做匹配；`settings.glsl` 里 `#define tonemap tonemap_agx`

### 自动曝光
启用 Photon 的 `AUTO_EXPOSURE_SIMPLE`（之前是 OFF）——黄昏/夜晚不再忽明忽暗，
`AUTO_EXPOSURE_MIN/MAX/RATE` 可在设置里继续调。

### 接触阴影
`include/zephyr/contact_shadows.glsl`：沿太阳方向在屏幕空间对 **depthtex1**
做 10 步短距离 march（0.6 格），几何被遮挡时压暗直射光，补 shadow map 分辨率
不足造成的「物体与地面接触处没有暗线」问题：

- 注意：`d4` 里的 `depthtex0` 是 3D 大气 LUT（sampler3D），接触阴影必须用
  `depthtex1`（sampler2D），否则整段 shader 编译失败
- 设置：`ZEPHYR_CONTACT_SHADOWS`、`ZEPHYR_CONTACT_SHADOWS_STRENGTH`（默认 0.70）

截图：`shots/v2.1-agx-dusk.jpg`（12300 黄昏）、`v2.1-agx-night.jpg`（18000 夜）、
`v2.1-agx-day.jpg`（11300 白天）。


## v2.0 — 自建大气/光照/水体色调（2026-11-05）

你说「脱离 Photon 光环后傍晚很丑」——原来的问题是 Photon 的日落直接给到
过饱和的橙黄（`shots/v2.0-dusk-baseline.jpg`，同一机位/时间 12300 的对照）。
这次不再只调参数，而是加了一层**自己的颜色模型**（`shaders/include/zephyr/atmosphere.glsl`）：

- `zephyr_light_color(elev, rain)`：太阳从正午中性白 → 黄金时刻暖橙 → 黄昏紫罗兰
  → 夜晚冷蓝，雨天去色；再按「保持原亮度、只换色相」的方式替换 Photon 的
  `light_color`（不会因为调色导致整体忽明忽暗）
- `zephyr_ambient_color(elev, rain)`：天光补色，黄昏偏玫瑰紫，夜里深蓝，
  同样按亮度归一化替换 `ambient_color` / `sky_color`
- `zephyr_sky_tint(dir, sun_dir, rain)` + `zephyr_sky_glow(...)`：天空色相偏移
  （天顶冷蓝、地平线黄金/紫红）+ 太阳附近与地平线的辉光层，
  在 `d0_sky_map`（反射/环境光用的天空图）和 `d4` 的可见天空上同时生效
- `zephyr_water_color(base, elev, rain)`：水体在白天偏青蓝、黄昏偏暗玫瑰、
  夜里近黑蓝，雨天去色后混入 `biome_water_color`

开关（游戏内「Zephyr 大气」页/settings）：
`ZEPHYR_ATMOSPHERE`（总开关）、`ZEPHYR_ATMOSPHERE_STRENGTH`（0~1，默认 0.85，
调 0 即回到 Photon 原色）、`ZEPHYR_WATER_TINT`（水体色调强度，默认 0.70）

对照图：
- `shots/v2.0-dusk-baseline.jpg`（强度 0，Photon 原始日落）
- `shots/v2.0-dusk-atmosphere.jpg`（强度 0.85，Zephyr 大气）
- `shots/v2.0-night-atmosphere.jpg`（夜间）


## v1.1 — 默认关闭涟漪（按你的意见）（2026-11-05）

「别做坑坑洼洼的地面了」→ 涟漪默认关掉：

- `ZEPHYR_RAIN_RIPPLE` 默认 `0.90 → 0.00`（代码保留，游戏内调回数值即可恢复）
- 湿地面回到「平滑湿衣」：albedo `−26%`、roughness `0.11`、f0 0.045、SSR ×1.3
  —— 只保留湿润变暗与反射，不再有波纹法线引起的凹凸
- 其余保留：中性灰雨丝（无蓝色粒子）、统一湿度场、光柱、材质立体感、雾


## v1.0 — 湿地面均匀化 + SEUS 式正弦涟漪（2026-11-05，待实机确认）

针对两点反馈：

### 1. 「没水的区域变多」

- 宏观湿度场从 `0.55~1.0` 收到 `0.88~1.0`（基本整条街统一潮湿，不再随机干块）
- 湿衣加强：albedo `−20% → −32%`、roughness `0.22 → 0.075`、f0 `0.03 → 0.045`、
  SSR 乘数 `1.0 → 1.3`（更接近一层薄水膜，阴影里也能看出湿）

### 2. 「看不出圆环」

读 SEUS 的 `RainRipples()` 发现关键不是贴图本身，而是他们用**正弦调制高度场**：

```glsl
float ripple = (sin(rippleTex.r * 10.0 + rippleTime * 20.0) * 0.5 + 0.5) * rippleTex.r;
```

也就是说涟漪的法线不是直接取贴图法线，而是「高度场 + 高频 sin + 时间」算梯度，
这样环才有锐利的亮暗边，不会被双线性过滤糊成团。

Zephyr 按这个思路重写 `zephyr_ripple_offset()`：

- `image/ripple.png` 改为 16 帧高度场动画条带（20 个雨滴源/tile，环厚 0.02~0.04）
- 采样后用 `sin(h*22 + t*16)` 调制，再对**调制后的高度**求梯度得到法线
- 环峰值处 roughness 降低 35% + 轻微 albedo 提亮（中性灰，不加蓝）

> ⚠️ 这版改动还没在实机确认（截图时你正在操作键鼠，R 重载被菜单挡住）。
> 如果观感反而更差，把 `ZEPHYR_RAIN_RIPPLE` 设为 0 即可整体关闭涟漪；
> 想继续调就从 `zephyr_rain.glsl` 的 `sin(h0*22 + time*16)` 频率和
> `image/ripple.png` 的雨滴源数量/环厚度入手。


## v0.9 — 让涟漪真的「看得出环」（2026-11-05）

v0.8 之后还是看不出环，原因有三个：

1. **环太细被 mipmap 抹平**：256px 帧里环只有 3~5px，远处被过滤成一片模糊
2. **法线强度不足**：0.25 的扰动量在低角度反射里几乎看不出来
3. **湿地面太糊**：coat roughness 0.22 把反光糊掉，环没有可断的「镜面」

修复：

- 重新生成 `image/ripple.png`：18 个雨滴源/tile，环半径 3%~8%（更小），
  环宽 0.016+0.022·phase（更粗，抗过滤），双环
- 采样改用 `textureLod(..., 0.0)`，不让 mipmap 把环糊掉
- 法线强度 `0.25 → 0.95`、粗糙度扰动 `0.10 → 0.16`
- 湿地面 coat roughness `0.22 → 0.14`（更接近镜面，环才能断开反光）

对照：`shots/reference-seus-ripples.jpg`（SEUS）vs `shots/v0.9-zephyr-ripples.jpg`（Zephyr）
现在 Zephyr 的湿路面在太阳反光带上能清楚看到一串串小圆环。


## v0.8 — 对照 SEUS 调整涟漪密度/大小（2026-11-05）

在游戏里切到 SEUS-Renewed 实机看了它的雨滴落地效果：地面像积了一层薄水，
散布着很多**小而独立的圆环**（每个几厘米，稀疏、只在反射里可见）。

对照后调 Zephyr 的动画条带采样：

- 平铺尺度 `0.85 / 1.55` → `0.45 / 0.85`（每张 256px 贴图覆盖约 2.2 / 1.2 格，
  环更稀疏，不再满屏）
- 法线强度 `0.35` → `0.25`，粗糙度扰动 `0.22` → `0.10`（只在镜面反射里出环，
  不再把反光打碎成噪点）
- 动画速度 `0.50 / 0.85` → `0.45 / 0.75`

对照图：`shots/reference-seus-ripples.jpg`（SEUS 实机）与
`shots/v0.8-zephyr-ripples.jpg`（Zephyr 实机，02:38:55 加载成功）。


## v0.7 — 参考 SEUS 的涟漪动画贴图（2026-11-05）

去看了 SEUS（PTGI/Renewed）的涟漪实现：

- `textures/RippleAnimation1/2/3.png` = **128×7680** 的动画条带（60 帧 128×128 垂直堆叠）
- 他们在世界空间采样这张「多雨滴涟漪法线图」，靠时间推进帧来做扩散动画

Zephyr 之前是「每格一个环 + 按半径映射采样一张单环贴图」，半径映射会让环变成大色块
（你说的 bug 感）。现在改成同款思路：

- 生成了我们自己的 `shaders/image/ripple.png`：**256×4096 动画条带（16 帧 256×256）**，
  每帧里 ~14 个随机雨滴源，每个源 2~3 圈同心扩散环，位置可平铺、随帧扩大
- `zephyr_rain.glsl` 在世界空间采样（两层不同 scale/speed），相邻两帧线性混合 →
  涟漪连续生长；不再做「半径反推 uv」的映射
- 环强度/尺度参数仍在 `ZEPHYR_RAIN_RIPPLE` 与 `zephyr_rain.glsl` 的 `scale/speed`

验证：`02:36:29 Using shaderpack: Zephyr` 加载成功，无加载错误。
（之后你切到了 SEUS-Renewed，所以没有再截到 Zephyr 的成片。）


## v0.6 — 雨滴涟漪重做（真·一圈圈波纹）（2026-11-05）

之前地面上的涟漪是「每个网格一个环」的平铺写法，看起来像鱼鳞斑纹。这次改成
**每个雨滴一个独立扩散波前**：

- 生成 `shaders/image/ripple.png`（128×128 法线贴图：两道同心环的斜率编码在 RG）
- `zephyr_rain.glsl` 里每滴雨：随机格点 + 随机中心 + 随机相位；采样纹理时用
  `uv = 0.5 + (f - center) * (0.34 / radius)`，让纹理里的环正好落在当前世界半径上
  → 环随 phase 扩大、波前变宽、强度按 `(1-phase)²` 淡出
- 只有 ~45% 的格子会在当前周期落雨，两层不同尺度/频率叠加，消除平铺感
- 涟漪同时轻微提高粗糙度（`roughness += wave * 0.22`），让环在镜面反射里表现为
  明暗圆环而不是散点闪光
- **坑**：Iris 1.8.8 遇到两段式自定义纹理键（`texture.ripple = ...`）会抛
  `StringIndexOutOfBoundsException` 导致整个包加载失败；必须用三段式
  `texture.deferred.<sampler> = image/ripple.png`
- `tools/mc-ctl.ps1` 的 `reload2` 改为用聊天行 `Shaders Reloaded!` 校验重载

验证：02:30:27 `Using shaderpack: Zephyr` 加载成功；`shots/v0.6-ripples.jpg`


## v0.5.2 — 蓝色粒子真正定位并消除（2026-11-05）

上次的「rain neutral」截图其实是在 Complementary 上截的（Iris 日志 02:13:09 显示当时
是 Complementary），所以 v0.5.1 的雨色修改并没有被真正验证。这次在 Zephyr 下重做：

- 用调试色块定位：把 `gbuffers_weather` 的雨染成红色、雪染成绿色后截图——雨四边形全变红，
  但蓝色小方块**仍然是蓝色** → 它们根本不由天气 pass 渲染，而是走 `gbuffers_textured`
  （`gbuffers_all_translucent.fsh` 的 `PROGRAM_GBUFFERS_TEXTURED`）的粒子 pass
- 在该 pass 末尾加处理：去饱和 85% + alpha ×0.20 → 蓝色小方块变淡灰、几乎不可见
- 保留 v0.5.1 的雨色中性化（90% 去蓝）、`RAIN_OPACITY 0.16`、alpha 裁切 0.30
- 移除 v0.5 的「皇冠飞溅」亮斑与雨滴几何拉伸（已被证明会制造小方块）
- `tools/mc-ctl.ps1` 新增 `reload2`：按 R 后用日志里的 `Using shaderpack` 行数校验是否真的重载

验证：Iris 日志 `02:20:02 Using shaderpack: Zephyr`，截图 `shots/v0.5-05-rain-neutral.jpg`
（Sayama-0.3，雨+黄昏，蓝色粒子消失）。


## v0.5.1 — 蓝色雨点清理（2026-11-05）

实机对比 `ComplementaryReimagined + EuphoriaPatches` 后发现：那些「蓝色小粒子」其实是
**原版雨滴粒子**，Photon 的雨色把它们染成了很蓝的 `(0.49, 0.65, 1.00)` 蓝，看起来像飞溅粒子。
Complementary 是把雨色改成「受场景光照的灰白色 + 低透明度」，所以不显眼。对应处理：

- `gbuffers_weather.fsh`：
  - 雨色 90% 去色到中性灰（只保留 10% 蓝调），整体亮度 ×0.85
  - alpha 裁切 0.10 → **0.30**（丢掉纹理里那些 1 像素小碎块）
  - `RAIN_OPACITY 0.25 → 0.16`（雨更细更淡）
- 删除了上一版加的「皇冠飞溅」亮斑（`albedo +=` 那一段）——那才是真正的「蓝色粒子」观感来源
- 删除 `gbuffers_weather.vsh` 里按世界锚点拉伸/变细雨丝的写法：它会让跨方块边界的
  雨滴四边形撕裂成小方块（这也是蓝色小方块的一个来源）；保留逐滴透明度变化与风向扰动

实机截图：`shots/v0.5-05-rain-neutral.jpg`（Sayama-0.3，雨+黄昏）


## v0.5 — 光柱 / 材质立体 / 雨的风感 / 反射锐化（2026-11-05）

四个方向同时推进 + 材质立体感。

### 1. 自己的丁达尔光柱（`c14_color_grading.fsh`）

- 新增 `zephyr_godrays()`：从每个像素朝太阳屏幕位置 ray-march，**只累积天空像素**，
  因此建筑缝隙/桥洞会自然出现光柱，不依赖 Photon 的「太阳可见度」
- 用 `openness^3`（天空覆盖率）+ 到太阳的屏幕距离衰减，避免整屏发白
- 设置：`ZEPHYR_GODRAYS`、`ZEPHYR_GODRAYS_INTENSITY`（默认 0.40；调 3.0 会整屏白，
  调试范围 0.2~0.8 比较安全）

### 2. 材质立体感（`include/surface/zephyr_relief.glsl`）

- 没有材质包 / labPBR 贴图，所以不用 POM，而是用 **albedo 亮度梯度的屏幕空间导数**
  做赝造凹凸法线（bump），让石头/砖/木板有轻微立体起伏，湿表面挂光更自然
- 10~30 格距离淡出，避免远处噪点
- 设置：`ZEPHYR_MATERIAL_RELIEF`（0~1，默认 0.50）

### 3. 雨的风感（`gbuffers_weather.vsh`）

- 加入风向 `ZEPHYR_RAIN_WIND_X/Z` + 正弦扰动 `ZEPHYR_RAIN_DISTURBANCE`，
  雨丝会随高度偏移、波动（类似 iterationT 的 wind/disturbance）

### 4. 湿反射锐化 + 飞溅

- 湿地面 roughness 0.24 → 0.16、SSR 乘数 0.80 → 1.00、水洼 roughness 0.030：
  霓虹/灯在湿路面上的反射更长更锐（参考图那种竖条反光）
- 涟漪法线扰动 0.34（更少噪点），飞溅改成「皇冠」形状：
  `albedo += (crown + 0.35*splash) * 0.060`，落点中心更亮、外圈更淡

### 验证

- 离线：209/209 入口编译通过（62 个被禁用，0 失败）
- 实机：Sayama-0.3，R 重载 + F2 截图（`shots/v0.5-*.jpg`）


## v0.4 — 湿地面重做 / 飞溅 / 雾 / 光柱（2026-11-05）

参考了 `iterationT 3.2.0` 的做法（雨=alpha 遮罩 + rainAlpha 驱动泛光；飞溅=多层
动画涟漪纹理；湿度=3D 噪声调制），在 Zephyr 里做了对应实现：

### 湿地面重做（解决「一块干一块水坑」）

`include/surface/zephyr_rain.glsl` v2：

- **宏观湿度场**：`0.55~1.0` 的大尺度噪声调制 wetness —— 整条街统一「潮湿」，不再出现
  干/湿硬切换
- **统一湿衣**：地面 albedo −20%、roughness → 0.24、f0 → 0.030、SSR ×0.80
- **水洼柔化**（改 Photon `rain_puddles.glsl`）：硬阈值 `linear_step(0.45,0.55)` →
  `smoothstep(0.40,0.62)`；水洼 roughness `0.002 → 0.055`（不再镜面）；变暗 `0.33 → 0.20`
- **雨点涟漪 + 飞溅**：两层细网格（5.4 / 7.7）+ 每格随机相位；飞溅核心额外给
  `albedo +0.045`、roughness → 0.10、SSR 提升 —— 雨滴落地有小白点飞溅感

### 雾

- `AIR_FOG_MIE_DENSITY_RAIN 0.038 → 0.060`、`_EVENING 0.0050 → 0.0046`、
  `_NOON 0.0001 → 0.0004`、`OVERWORLD_FOG_INTENSITY 1.15`、`BLOOMY_FOG_INTENSITY 1.15`
  （先试到 0.085/0.0090 会整屏发白，已回调，保留可见空气透视）
- 雨天泛光 `BLOOM_INTENSITY` 额外 ×(1 + 0.30 × rainStrength)（雨丝在亮天空下更明显）

### 丁达尔光柱

- 确认 Photon 的 `VL`（体积光）与 `CREPUSCULAR_RAYS`（屏幕空间光柱）都是开启状态，
  并把 `CREPUSCULAR_RAYS_INTENSITY 1.00 → 1.60`
- 实测：太阳被城市建筑遮挡时体感很弱、太阳落入街道尽头时光晕明显但柱状不强。
  下一步建议做我们自己的体积光柱（可绕过「太阳可见度」限制）

### 验证

- 离线：209/209 入口编译通过（62 个被禁用，0 失败）
- 实机：Sayama-0.3，R 重载 + F2 截图多轮（`shots/v0.4-*.jpg`）


## v0.3 — 雨滴形状 + 雨水表面反应（2026-11-05）

本轮全部在 **Sayama-0.3**（实际使用的地图）上通过「改代码 → R 重载 → F2 截图」迭代，
截图见 `shots/v0.3-*.jpg`。

### 新增：雨滴形状（`gbuffers_weather.vsh/.fsh`）

原版雨丝是等长等宽的细白线。现在：

- 顶点着色器把雨丝沿世界 Y 拉伸 `1.0 + 1.15 × ZEPHYR_RAIN_STREAK`，横向压细 `1.0 − 0.45 × 拉伸`，
  绕方块/0.2 网格锚点缩放，不会出现接缝
- 每滴雨用 `hash(floor(world_pos.xz × 5))` 生成 seed：长度 ±25%、透明度 0.45~1.35 倍随机，
  雨不再是「复制粘贴」
- 设置：`ZEPHYR_RAIN_SHAPE`（开关）、`ZEPHYR_RAIN_STREAK`（0 = 原版）

### 新增：雨水落到表面（`include/surface/zephyr_rain.glsl` + `d4_deferred_shading.fsh`）

挂在 deferred 里、puddle 之前（真实水洼仍然优先）：

- **水平面（地面/屋顶）**：湿润高光 coat（`f0 0.03`、roughness 0.22，雨停后仍保留）
  + 雨点落地扩散圆环：两层网格（4.2 / 6.7 频率）+ 每格随机相位/中心，法线扰动 0.42，
  近处增强、6 格后淡出
- **垂直面（墙/建筑外表面）**：湿润 sheen（f0 0.036、roughness 0.30）+ 沿墙面缓慢流下的细水线
  （按墙面水平坐标分格、随时间下移），并给法线加 0.055 的水线扰动
- 设置：`ZEPHYR_RAIN_SURFACE`、`ZEPHYR_RAIN_WETNESS`、`ZEPHYR_RAIN_RIPPLE`（都做了中英文标签 + 滑块）

### 工具

- `tools/mc-ctl.ps1` 增强：`-Action look -DX -DY`（相对鼠标视角）、可靠的 `SetForegroundWindow`
  （AttachThreadInput + BringWindowToTop + ALT 解锁 + 校验前台窗口）、按键按住 80ms 更稳
- 截图自动等待 PNG 写盘完成（避免 0 字节）

### 验证

- 离线：209/209 入口编译通过（62 个被禁用，0 失败）
- 实机：Sayama-0.3 多轮 R 重载 + F2 截图，无编译错误


## v0.2 — 天气自适应与实机迭代（2026-11-05）

在 Weston City V0.3 上用 Iris 的 **R 键重载**做了真实画面迭代（实机截图见 `shots/`）。

### 新增

- **天气自适应调色** `ZEPHYR_WEATHER_ADAPT`（`zephyr_cinematic.glsl`）
  - 雨天/阴天自动：降低对比曲线 28%、黑位额外 +0.014、暗部加冷雾（`vec3(0.86,0.95,1.06)`）、
    自然饱和度 -35%、高光柔化 +0.18 —— 对应参考图里「雨天不发黑、亮部不炸」的观感
  - c14 新增 `rainStrength` uniform 传入调色层
- `tools/mc-ctl.ps1`：对已运行的游戏窗口做聚焦 / 按键 / 聊天命令（剪贴板粘贴绕开输入法）/ F2 截图 / R 重载
- `tools/mc-launch.ps1`：从 PCL 启动命令派生 `--quickPlaySingleplayer` 受控实例

### 调优（实机对比后）

- 湿地面/雨雾：`AIR_FOG_MIE_DENSITY_RAIN 0.038→0.055`、`OVERWORLD_FOG_INTENSITY 1.00→1.10`、
  `BLOOM_INTENSITY 1.30→1.38`、`GRADE_BRIGHTNESS 0.97→1.02`
- 日落去「整屏橙」：`ZEPHYR_WARMTH 0.70→0.15`、`GRADE_ORANGE_SAT_BOOST 0.06→0.02`、
  `GRADE_WHITE_BALANCE 6300→6700`、`AIR_FOG_MIE_DENSITY_EVENING 0.0080→0.0058`

### 验证

- 离线：209/209 入口编译通过（62 个被禁用的 pass 跳过，0 失败）
- 实机：Weston City V0.3 连续多轮 `R` 重载 + F2 截图，无编译错误

## v0.1 — Cinematic layer（2026-11-05）

首个可运行版本：在 **Photon Shaders 1.2a**（SixthSurge）基础上加入 Zephyr 电影感层。

### 新增

- `shaders/include/post_processing/zephyr_cinematic.glsl`
  - `zephyr_pre_tonemap()`：高光加暖（琥珀色）、极亮高光预压缩/去饱和
  - `zephyr_post_tonemap()`：青橙分离色调、胶片 S 曲线、黑位抬升 + 暗部去饱和、自然饱和度、高光肩部去饱和
  - `zephyr_letterbox()`：2.35:1 电影黑边
  - `zephyr_apply_grain()`：亮度加权的动态胶片颗粒
- 管线挂载：`program/c14_color_grading.fsh`、`program/final.fsh`
- 设置项（游戏内「后处理 → Zephyr Cinematic」）：
  `ZEPHYR_CINEMATIC / STRENGTH / FILM_CURVE / BLACK_LIFT / HIGHLIGHT_ROLLOFF / SPLIT_STRENGTH / WARMTH / VIBRANCE / GRAIN / LETTERBOX / LETTERBOX_RATIO`
- `profile.cinematic` 预设：DOF + 动态模糊 + 更高泛光/暗角 + 强度 1.0
- 中英文标签（`lang/en_US.lang`、`lang/zh_CN.lang`）
- 默认观感调校（按参考图）：
  - `GRADE_WHITE_BALANCE 6500 → 6300`
  - `GRADE_CONTRAST 1.00 → 1.04`、`GRADE_SATURATION 1.00 → 1.03`
  - `GRADE_ORANGE_SAT_BOOST 0.00 → 0.06`、`GRADE_TEAL_SAT_BOOST 0.10 → 0.14`
  - `BLOOM_INTENSITY 1.00 → 1.30`、`VIGNETTE_INTENSITY 1.00 → 1.25`
  - `AIR_FOG_MIE_DENSITY_EVENING 0.0050 → 0.0080`、`_RAIN 0.030 → 0.038`

### 修复（Photon 1.2a 遗留，Iris 1.8.8 会警告）

- `shaders.properties` 中失效的选项引用（实机日志中的 `Invalid pack option` / `Unable to resolve shader pack option menu element`）：
  - profile 中的 `GTAO` / `!GTAO` → `SHADER_AO=SHADER_AO_GTAO` / `SHADER_AO=SHADER_AO_NONE`
  - `WATER_REFRACTION` / `WATER_REFRACTION_INTENSITY` → `REFRACTION` / `REFRACTION_INTENSITY`
  - 移除已不存在的 `CLOUDS_DAILY_WEATHER`
  - `CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS_H/_Z` → `CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS`
- 修复后 `shaders.properties` 的未知选项引用数：**0**

### 工具

- `tools/validate_glsl.py`：离线 GLSL 校验（moderngl + PyOpenGL 真实驱动编译；Iris 宏注入 + `#include` 解析 + `shaders.properties` 启用条件）
- `tools/analyze_look.py` + `docs/look-analysis.md`：把参考截图量化（影调/暗部色偏/高光色偏），并离线渲染调色响应曲线与色卡对比（可直接看 Zephyr 层对画面的影响）
- `tools/mc-test.ps1`：MC 启动 → 进存档 → 自动截图 → 抓 Iris 日志
- 文档：`README.md`、`docs/look-dev.md`、`NOTICE.md`

### 验证

- 离线：`209/209` 个光影程序入口编译通过（62 个被光影自身禁用的 pass 跳过，0 失败）
- 实机：见 `reports/launch-report.md`（由实机验证流程生成）

### 已知限制

- 没有夜间/蓝调专用预设（v0.3 计划）
- 泛光仍是各向同性，霓虹横向 streak 未做（v0.2 计划）
- 湿地面反射沿用 Photon 的 SSR + 雨坑系统，尚未加雨纹法线扰动（v0.2 计划）
- Distant Horizons 未安装，`dh_*` 程序未纳入离线校验
