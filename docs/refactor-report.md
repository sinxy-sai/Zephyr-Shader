# Zephyr 工程化重构报告

> 目标：为「逐步替换 Photon、最终重构光影」做准备。本轮先做**可验证的架构重构**，
> 不动渲染行为，保证 209/209 入口编译通过、画面不变。

---

## 1. 现有代码的坏味道

### 1.1 长函数 / 上帝对象

| 位置 | 问题 | 证据 |
| --- | --- | --- |
| `program/c14_color_grading.fsh` | 一个 pass 里同时做：bloom 合成、曝光、屏幕空间光柱、调色、tonemap、颗粒、暗角 | 226 行 |
| `include/surface/zephyr_rain.glsl` | 涟漪函数内嵌套 2 层循环 + 4 个魔法常数，且当前默认关闭（死代码） | 137 行 |
| `include/post_processing/zephyr_cinematic.glsl` | 调色/曲线/颗粒/信箱混在一个文件 | 159 行 |
| `settings.glsl` | 551 行，Zephyr 选项与 Photon 选项混排，枚举注释极长 | 551 行 |

### 1.2 重复代码

- `c14` 里的光柱函数是「取景到太阳、只累加天空像素」的完整实现，和 `c1`/最终合成
  没有复用关系，只能整段复制才能搬动 → 重构后抽成模块。
- `final.fsh` 与 `c14` 各自 `#include` 同一调色模块（重复 include 路径维护）。
- 水面涟漪、湿地涟漪、落地涟漪三套「环形扰动」各写一遍（实现手段不同，但概念重复）。

### 1.3 紧耦合（对 Photon 的隐式依赖）

- Zephyr 模块直接假设 host 已声明 uniforms：`depthtex0`、`gbufferProjection`、
  `colortex0/4/5`、`sun_dir`、`view_pixel_size` 等，**没有任何契约说明**；
  一旦 Photon 升级或我们换 host，编译错误会以 `undeclared identifier` 形式在
  完全无关的入口爆出来（之前 `depthtex0` 是 sampler3D 的坑就属此类）。
- `c1` 的 SSGI 曾经读了自己正在写的 `colortex0`（读写同一 RT → 拖影），
  本质是「模块没有声明输入/输出方向」。
- 颜色空间隐式约定：`tonemap_agx` 假设输入为 Photon 的 exposure 后 HDR 尺度，
  用 `ZEPHYR_AGX_PRESCALE` 硬凑，没有单位注释。

### 1.4 魔法数

- 光柱：`28` 采样、`0.94` 衰减、`0.55` 最终系数、`0.15/3.5` 亮度阈值、`pow(...,3.0)` 开方权；
- 调色：`1.6`（ACES RRT 匹配）、`1.08/0.94`（AgX punchy）、`0.014` 黑位抬升；
- 水面涟漪：`2.4/4.0` 格尺度、`9.0` 环宽、`0.10` 强度；
- 接触阴影：`10` 步、`0.60` 米、`0.0020+0.020t²` 偏置；
- 雾：`0.0060` 密度、`5.0` 高度、`1.60` 光雾倍率（这些已进设置，但代码里仍有默认值散落）。

### 1.5 条件编译爆炸

- 单个入口平均要展开 40+ 个 `#ifdef`；Zephyr 选项与 Photon 特性开关交织，
  「哪些组合是验证过的」没有记录。
- 布尔选项需要「空 decoy 块」才能被 Iris 保留在 settings.txt，属于框架 hack，
  没有集中管理。

### 1.6 命名与接口不一致

- `zephyr_pre_tonemap` / `zephyr_post_tonemap` / `zephyr_godrays` / `zephyr_rain_surface`
  / `zephyr_material_relief`：命名风格统一但**参数单位未约定**（线性 vs 显示，
  世界坐标 vs 屏幕 UV），调用方只能靠读实现。
- `zephyr_ripple_offset` 当前被 `ZEPHYR_RAIN_RIPPLE=0` 关闭，但代码 + 840KB 的
  `image/ripple.png` 仍在仓库里（死资产）。

---

## 2. 重构后的结构（本轮已落地）

```
shaders/include/zephyr/
├── atmosphere.glsl        # 颜色模型：light / ambient / sky tint+glow / water tint
├── contact_shadows.glsl   # 屏幕空间接触阴影（10 步 march depthtex1）
├── cinematic.glsl         # 调色：pre/post tonemap、曲线、颗粒、信箱
├── godrays.glsl           # 屏幕空间光柱（从 c14 抽出，采样数/衰减/系数常量具名）
└── water_rings.glsl       # 水面雨滴涟漪（从 Photon water_normal.glsl 抽出）
shaders/include/surface/
├── zephyr_rain.glsl       # 湿衣 / 落地涟漪（默认关闭，保留）
└── zephyr_relief.glsl     # 微凹凸
```

每个模块头部都有 **Contract 注释**：host 必须声明哪些 uniform、函数签名、单位、
以及是否可安全移除。示例（`godrays.glsl`）：

```glsl
/*
  Zephyr | post: screen-space god rays
  Contract (host must declare):
    uniforms: sampler2D colortex5, depthtex0; mat4 gbufferModelView, gbufferProjection;
              vec3 sun_dir; float aspectRatio;
  Interface: vec3 zephyr_godrays(vec2 uv, float exposure)
*/
#ifndef ZEPHYR_GODRAYS_SAMPLES
	#define ZEPHYR_GODRAYS_SAMPLES 28
#endif
#ifndef ZEPHYR_GODRAYS_DECAY
	#define ZEPHYR_GODRAYS_DECAY 0.94
#endif
```

### 2.1 SOLID 对应关系

| 原则 | 落地方式 |
| --- | --- |
| **S**RP | `c14` 只做编排（bloom → 曝光 → godrays → 调色 → tonemap → 颗粒/暗角）；光柱、调色各自成模块 |
| **O**CP | 所有可调量走 `settings.glsl` + `#ifndef` 默认值，新增效果不改既有模块 |
| **L**SP | 同类模块接口一致：`zephyr_*(input) -> output`，不依赖隐式全局状态（除 host uniform） |
| **I**SP | 调用方只 include 需要的模块（如 `final.fsh` 只 include `cinematic.glsl`） |
| **D**IP | 模块依赖「host 声明的 uniform 契约」而非具体 Photon pass；替换 host 时按契约适配 |

---

## 3. 改动点清单

| 文件 | 改动 | 行为 |
| --- | --- | --- |
| `program/c14_color_grading.fsh` | 删除内联光柱（约 55 行）→ `include "/include/zephyr/godrays.glsl"`；调色 include 改到新路径 | 不变 |
| `include/zephyr/godrays.glsl` | 新增：光柱实现 + 3 个具名常量（采样数/衰减/系数） | 不变（数值相同） |
| `include/post_processing/zephyr_cinematic.glsl` | 移动为 `include/zephyr/cinematic.glsl`，加 Contract 头注释 | 不变 |
| `program/final.fsh` | include 路径同步 | 不变 |
| `include/surface/water_normal.glsl` | 删除内联水面涟漪函数 → include `zephyr/water_rings.glsl`，保留 1 处调用 | 不变 |
| `include/zephyr/water_rings.glsl` | 新增：水面涟漪实现 + Contract | 不变 |

尚未做（下一轮）：

- `settings.glsl` 拆分（Photon 段 / Zephyr 段 / decoy 段），并生成「已验证组合」清单；
- 删除死资产：`image/ripple.png`（840KB）与 `zephyr_ripple_offset` 死代码路径；
- `zephyr_rain.glsl` 拆分（湿衣 / 落地涟漪 / 墙流三分）；
- 为每个 Zephyr 模块加「可独立编译的接口测试」（离线验证器支持单文件编译）。

---

## 4. Photon 替换路线（重构光影）

替换不能一次全砍，按「依赖倒置」的层次逐段替换，每段都有回退开关：

| 阶段 | 替换内容 | 接缝 | 回退 |
| --- | --- | --- | --- |
| P0（已完成） | 后处理链独立：tonemap/调色/光柱/颗粒 | `c14` + `final` | 关 `ZEPHYR_CINEMATIC` / `ZEPHYR_GODRAYS` |
| P1 | 大气与光照颜色：自己的 light/ambient/sky 模型 | `d0_sky_map.vsh` 的 `light_color/ambient_color/sky_color` | `ZEPHYR_ATMOSPHERE_STRENGTH=0` |
| P2 | 天空渲染：用自有辐亮度替换 `draw_sky()`（保留 Photon 云作为独立层） | `include/sky/sky.glsl` 的 `draw_sky` | 开关 `ZEPHYR_OWN_SKY` |
| P3 | 水体：自有吸收/散射/法线/焦散替代 `gbuffers_all_translucent` 水段 | `MATERIAL_WATER` 分支 | 开关 |
| P4 | 阴影：自有 PCSS + 接触阴影（替换 `sampling.glsl`） | `calculate_shadows()` | 开关 |
| P5 | 云/雨/天气：自有体素云与雨幕，删除 Photon 云 | `include/sky/clouds/*` | 开关 |

每阶段的验收标准相同（见第 5 节），并且**同一时间只允许一个阶段处于「默认开启」**，
避免多个新系统叠加导致问题无法定位。

---

## 5. 重构后的测试要点

### 5.1 静态（每次提交必跑）

```powershell
# 全量离线编译：期望 209/209 compiled, 0 failed
& C:\Users\liubingliang\Downloads\_shader_lab\venv\Scripts\python.exe tools\validate_glsl.py
```

- [ ] `209/209 compiled, 62 skipped (disabled by pack), 0 failed`
- [ ] `git status` 无 `image/ripple.png` 之类的意外删除/新增
- [ ] `shaders.properties` 里每个 `screen.*` 引用的选项都在 `settings.glsl` 有定义
      （否则 Iris 会报 unknown option，甚至整包加载失败）
- [ ] 每个 `#ifdef ZEPHYR_*` 都有对应 decoy 块（保证选项持久化）

### 5.2 运行时（`tools/mc-ctl.ps1`）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\mc-ctl.ps1 -Action reload2
# 期望日志：[System] [CHAT] Shaders Reloaded! 且无 "Failed to load the shaderpack"
```

- [ ] 日志无 `Failed to load the shaderpack`
- [ ] 日志无 `Shader compilation log` 相关 ERROR
- [ ] F3 里 FPS 与重构前差异 < 2%

### 5.3 视觉回归矩阵（手动，各拍一张对比）

| 场景 | 时间/天气 | 关注点 |
| --- | --- | --- |
| 白天街道 | 6000 / clear | 天空色、阴影、接触阴影暗线 |
| 黄昏 | 12300 / clear | AgX 高光不过曝、地平线暖色 |
| 暮色 | 13200 / rain | 天空紫、体积雾、水面涟漪 |
| 夜晚霓虹 | 18000 / rain | 光柱、雾中光晕、水面反射 |
| 室内/洞穴 | 任意 | 不该漏入天光（反射探针遮蔽） |

每个场景检查：
- [ ] 无拖影（重点回归 SSGI 移除后）
- [ ] 无蓝色小粒子（v0.5.x 回归项）
- [ ] 湿地面无「鱼鳞」纹理（v1.1 回归项：涟漪默认关闭）
- [ ] 水面有雨环但无「大色块」（v2.6）

### 5.4 设置开关回归（逐项关闭应「干净退化为 Photon 基线」）

| 设置 | 关闭后期望 |
| --- | --- |
| `ZEPHYR_ATMOSPHERE` | 天空/光照回到 Photon 原色，无其它变化 |
| `ZEPHYR_CINEMATIC` | 调色/颗粒/信箱消失，AgX 仍生效 |
| `ZEPHYR_GODRAYS` | 光柱消失，无残留亮斑 |
| `ZEPHYR_CONTACT_SHADOWS` | 接触暗线消失，阴影无空洞 |
| `ZEPHYR_MIST` | 体积雾变薄，无白屏 |
| `ZEPHYR_WATER_RINGS` | 水面恢复只有 Gerstner 波 |
| `ZEPHYR_MATERIAL_RELIEF` | 材质恢复平整 |

### 5.5 模块级（新增，建议下轮补自动化）

- [ ] `godrays.glsl`：`ZEPHYR_GODRAYS_INTENSITY=0` 时函数返回 `vec3(0.0)`；
      太阳在背后时返回 0（`sun_view.z > -0.05`）。
- [ ] `water_rings.glsl`：`rain=0` 时返回 `vec2(0.0)`。
- [ ] `contact_shadows.glsl`：`ZEPHYR_CONTACT_SHADOWS_STRENGTH=0` 时返回 1.0。
- [ ] `atmosphere.glsl`：`zephyr_light_color` 在 `elev=1.0`（正午）与
      `elev=-1.0`（深夜）之间亮度单调，无 NaN。

---

## 6. 已知风险

1. **框架限制**：Iris 不提供 compute/多相机渲染，天空/水面/阴影的「完全自有实现」只能
   在光栅 + 多 pass 约束内完成，Photon 替换是**渐进式**的，不是一次性删库。
2. **开关矩阵**：新系统与 Photon 特性组合容易互相抵消，必须保持「一个阶段默认开」。
3. **纹理声明坑**：自定义纹理必须用三段式键 `texture.<program>.<name>`
   （两段式会触发 Iris 1.8.8 的 `StringIndexOutOfBoundsException`，整包加载失败）。
