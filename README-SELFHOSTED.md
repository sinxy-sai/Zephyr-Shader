# Zephyr 2.0 — 自研光影（从零重写）
# 不依赖 Photon / Complementary / 任何第三方 shader 代码。

## 当前状态（v0.1 骨架）

- 前向光照：lightmap（方块光/天光）+ 太阳 Lambert + 自有太阳/环境色曲线
- 天空：自有梯度 + 臭氧 + 黄昏暖带 + 日晕/日盘 + 星场 + fbm 云层
- 水体：自有波浪法线 + Fresnel
- 后处理：AgX 色调映射 + 曝光 + 饱和度 + 暗角 + 颗粒 + 8bit 抖动
- 雾：高度雾（线性深度）
- 22 个入口全部离线编译通过（22/22）

## 还缺（下一步）

- 阴影贴图（shadow pass + PCSS）
- Bloom / DOF / TAA
- 环境反射 / 湿地面 / 雨滴涟漪
- 水体吸收/折射/焦散、云阴影
- 维度特化（下界/末地）
- 调试视图

## 目录

```
shaders/
├── settings.glsl          # 选项（Iris 自动注入）
├── shaders.properties     # 菜单/滑块
├── include/zephyr/        # 引擎模块（math/lighting/sky/tonemap/fog）
├── include/buffers.glsl   # Iris colortex 契约
└── gbuffers_*.fsh/vsh     # 各自研程序
```
