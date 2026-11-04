# Changelog

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
