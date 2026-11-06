# Zephyr Shader

Zephyr 是面向 Minecraft Java Edition 的自研光影项目，目标是把物理可信的光照、稳定的时域效果和电影化成像结合起来。

当前仓库处于**基线整理阶段**：已完成参考光影的技术调研和开源边界定义，`shaders/` 将从零实现，不复制任何受限光影的源码、资源或许可证文本。

## 项目目标

- 真实感：稳定的阴影、天空、大气、水体和材质响应。
- 电影感：自然曝光、柔和高光、可控景深、镜头光晕和低干扰调色。
- 可维护：每个渲染子系统有清晰的入口、资源约定和质量档位。
- 可分发：Zephyr 自有源码采用 Apache-2.0；参考光影只用于学习和对比，不作为代码或资源上游。

## 支持范围

- Minecraft：1.21.1
- Mod loader：Fabric 0.18.4
- Shader loader：优先 Iris 1.8.x，具体兼容版本以实现阶段的验证矩阵为准。

## 仓库结构

```text
Zephyr/
├─ shaders/                 # 可分发的 Iris shader 源码
├─ docs/                    # 技术分析、项目规范与设计文档
├─ LICENSE                  # Apache License 2.0
├─ NOTICE.md                # 项目归属和第三方学习边界
├─ CONTRIBUTING.md          # 开发、验证和提交规范
└─ .gitignore               # 本地测试产物与缓存忽略规则
```

## 开发状态

1. 基线：仓库规范、许可和参考技术分析。
2. 设计：确定管线、资源布局、质量档位和验证矩阵。
3. 实现：从最小可运行管线开始，逐个替换光照、天空、水体和后处理模块。

详细约束见 [`docs/project-spec.md`](docs/project-spec.md)，参考包的技术比较见 [`docs/technical-analysis.md`](docs/technical-analysis.md)。

## 许可

Zephyr 自有源码和文档以 Apache License 2.0 发布，见 [`LICENSE`](LICENSE)。

参考光影包拥有各自的作者、许可证和分发限制。它们不属于本仓库的代码来源；本项目只记录从公开源码中学习到的技术方向和文件级观察，见 [`NOTICE.md`](NOTICE.md)。
