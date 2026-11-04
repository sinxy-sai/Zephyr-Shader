# Changelog

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
