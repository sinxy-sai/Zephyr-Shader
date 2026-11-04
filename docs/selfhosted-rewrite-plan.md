# 自研化重写计划（去 Photon 依赖）

> 现状：`shaders/program` 61 个文件 / 6164 行、`shaders/include` 100 个文件 / 9107 行，
> 其中 Zephyr 自研部分约 550 + 166 行。Photon 覆盖了：gbuffer 管线、阴影贴图与 PCSS、
> 大气散射 LUT、体积云/极光、水体材质、TAA、Bloom、DOF、DH、彩色方块光 LPV、
> Distant Horizons 支持、调试视图与文本渲染。
>
> 结论先说：**一次性把 1.5 万行 Photon 全部重写在一次会话内不可行**。
> 可行的是「绞杀者模式（Strangler Fig）」：保持光影随时可跑，按 pass 逐个用
> Zephyr 实现替换，每次替换都有开关与视觉对照。下面给出完整路线与验收标准。

---

## 1. 依赖清单（要替换的对象）

### 1.1 程序（Iris 入口）
| 分组 | 程序 | 用途 | 替换难度 |
| --- | --- | --- | --- |
| gbuffer | `gbuffers_basic` `gbuffers_textured` `gbuffers_textured_lit` `gbuffers_entities` `gbuffers_block` `gbuffers_hand` `gbuffers_weather` `gbuffers_water` `gbuffers_skybasic` `gbuffers_skytextured` | 写 albedo/normal/lightmap/材质掩码 | ★★★ |
| 阴影 | `shadow.fsh/vsh` `shadowcomp` | shadow map 渲染 | ★★★★ |
| 预处理 | `d0_sky_map` `d1_terrain`? `d2` `d3` `d4_deferred_shading` | 大气 LUT、延迟着色、天空 | ★★★★★ |
| 合成 | `c0_vl` `c1_blend_layers` `c2_dof` `c3_taau_prep` `c4_taa_exposure` `c5_c10_bloom` `c11..c13 bloom` `c14_color_grading` `c15_fxaa` `c16_motion_blur` `final` | 体积光、合成、后处理链 | ★★★（部分已自研） |
| 其它维度 | nether/end 各程序 | 维度特化 | ★★ |

### 1.2 关键子系统
1. 大气散射：`include/sky/atmosphere.glsl`（RLH 单次散射 + 3D LUT）
2. 阴影：`include/lighting/shadows/*`（扭曲 shadow map、blocker search、PCSS、VPS）
3. 云：`include/sky/clouds/*`（cumulus/altocumulus/cirrus/congestus 光线步进 + 时间上采样）
4. 体积光/彩色光：`include/fog/lpv_fog.glsl` + `include/lighting/lpv/*`（LPV 体素）
5. 水面：`gbuffers_all_translucent` 的 `MATERIAL_WATER` 分支 + `water_normal.glsl`
6. TAA/去噪：`c3/c4` + `include/utility/taa*.glsl`
7. Bloom/DOF：`c5_c10_bloom_downsample`、`c2_dof`
8. 材质/SH 光照：`include/surface/material.glsl`、`include/lighting/bsdf.glsl`、`sky_sh`

---

## 2. 迁移顺序（每个阶段都可单独发布）

| 阶段 | 替换 | 新文件（示意） | 开关 | 验收 |
| --- | --- | --- | --- | --- |
| **S0** | `final` 后处理（CAS/抖动/输出） | `zephyr/engine/final.glsl` | 始终使用 | 与旧 final 逐像素近似（±1/255） |
| **S1** | 后处理链：`c14` 调色/tonemap、`c16` 运动模糊、`c15` FXAA | `zephyr/engine/post_*.glsl` | `ZEPHYR_POST_OWN` | 关开关回到 Photon；开开关视觉一致 |
| **S2** | gbuffer 写入（albedo/normal/lightmap/材质 ID） | `zephyr/engine/gbuffer_*.glsl` | `ZEPHYR_GBUFFER_OWN` | 延迟着色输入一致（调试视图对比） |
| **S3** | 延迟着色（直接光+SH+反射+雾合成） | `zephyr/engine/deferred.glsl` | `ZEPHYR_DEFERRED_OWN` | 5 场景对照图 |
| **S4** | 阴影（自有 shadow pass + PCSS） | `zephyr/engine/shadows.glsl` | `ZEPHYR_SHADOW_OWN` | 阴影边缘/接触阴影对比 |
| **S5** | 天空与大气（自有 LUT + 云） | `zephyr/engine/sky.glsl` | `ZEPHYR_SKY_OWN` | 黄昏/夜间/雨天对照 |
| **S6** | 水体（自有吸收/折射/反射/焦散） | `zephyr/engine/water.glsl` | `ZEPHYR_WATER_OWN` | 河面/海岸对照 |
| **S7** | 彩色光（自有体素或 SSGI-lite） | `zephyr/engine/local_light.glsl` | `ZEPHYR_LOCAL_LIGHT_OWN` | 夜晚霓虹对照 |
| **S8** | 删除 Photon 文件，`shaders/include/photon/` 整目录移除 | — | — | 编译 0 个 Photon include |

每阶段完成条件：编译 209/209、实机无加载错误、对照截图无回归、性能差 < 5%。

---

## 3. S0 已落地（本轮）

- 新增 `zephyr` 自研后处理入口骨架：`final` 不再依赖 Photon 的 `global.glsl`/
  `utility/*`，改为 `zephyr/engine/final.glsl`（自有 sRGB/CAS/抖动/输出）。
- 保留 `ZEPHYR_CINEMATIC` 调色模块（自有）。
- 行为：视觉与旧 final 等价；Photon 调试视图（DEBUG_VIEW_*）移除（可后续补）。

---

## 4. 工作量估算（以 1 人 4h/天计）

| 阶段 | 估时 |
| --- | --- |
| S0 | 0.5 天 |
| S1 | 2 天 |
| S2 | 3 天 |
| S3 | 5 天 |
| S4 | 4 天 |
| S5 | 6 天（含云） |
| S6 | 4 天 |
| S7 | 5 天（可选） |
| S8 | 1 天（清理/回归） |
| **合计** | **约 30 人日** |

---

## 5. 风险与约束

1. **Iris 限制**：无 compute/SSBO、无多相机 pass → 体积云/探针只能是光栅近似。
2. **回归代价高**：Photon 的 uniform/buffer 布局（colortex 分配）必须逐个核对，
   自研 pass 的 `RENDERTARGETS` 与 mipmap 标志要匹配，否则会静默渲染错误。
3. **调试视图**：自研后最先丢失的是 Photon 的 DEBUG_VIEW，建议 S1 时自建简易调试视图。
4. **纹理声明**：自定义纹理必须 `texture.<program>.<name>`（Iris 1.8.8 两段式会崩包）。

---

## 6. 每阶段回归清单

```powershell
# 1) 编译
& ...\venv\Scripts\python.exe tools\validate_glsl.py   # 209/209, 0 failed

# 2) 实机
powershell -File tools\mc-ctl.ps1 -Action reload2      # 期望 Shaders Reloaded!
```

视觉矩阵：白天/黄昏/暮色雨/夜雨/室内 5 场景 + 逐开关关闭退化 + F3 帧率对比。
