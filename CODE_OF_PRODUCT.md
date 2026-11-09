# CODE_OF_PRODUCT / 产品行为准则

本文件说明 Zephyr 作为可分发光影包对外承诺的行为边界，面向使用者与打包发布者。技术实现见 `README.md`，开发约定见 `CONTRIBUTING.md`。

## 产品定位

Zephyr 是面向 Minecraft Java Edition 的免费、开源、自研光影包。优先级依次为：**画面稳定 > 视觉质量 > 可配置性 > 性能覆盖 > 新特性数量**。当新特性会引入闪烁、重影、过曝或难以回退的视觉回归时，默认不启用，或提供关闭开关。

## 兼容性

| 项目 | 版本 |
| --- | --- |
| Minecraft | 1.21.1 |
| Mod loader | Fabric 0.18.4 |
| Shader loader | Iris 1.8.x |

兼容范围外的版本不承诺可运行。升级游戏或加载器后，建议在晴天与雷雨的正午、日落、夜晚分别检查画面。

## 用户可见行为

- **设置界面**：「光影包配置」提供英文与简体中文的标签及悬停说明，随游戏语言自动选择，缺失时回退英文。
- **性能预设**：低 / 中 / 高 / 极致四档，仅调整公开选项；应用后每一项仍可单独修改。
- **默认值与可回退**：每项设置都有明确默认值，并与仓库中提交的配置一致；效果开关可关闭到接近基线的状态，不保存隐藏的全局覆盖。
- **无侵入**：光影包不修改世界存档、不放置或删除方块、不执行游戏命令、不改动玩家位置，也不写入游戏目录之外的文件。
- **无外部依赖**：不下载、不请求、不读取外部资源；天空、云、噪声、水洼等效果均程序化生成。
- **隐私**：无遥测、无统计上报、不读取账号或硬件信息。

## 视觉质量承诺与已知限制

承诺：白天不过曝、夜景不糊白、时域抗锯齿不产生持续闪烁、玻璃与半透明物品可辨、光源泛光不过界、天气变化不会让夜空异常变亮。

当前已知限制：

- 树叶等镂空材质的边缘在远处仍可能有轻微闪烁。
- 阴影分辨率与距离受加载器实际分配限制，相关设置项可能不生效。
- 完整视差映射、真前向半透明、接触硬化阴影、反射与环境光遮蔽的时域降噪仍在开发中。

限制清单随版本更新，以 `README.md` 为准。不把尚未实现的行为描述为已完成特性。

## 变更与发布

- 每次改动都应可编译、可热重载、可回退，并附验证记录。
- 选项布局、渲染缓冲或渲染阶段结构的变更属于契约变更，需同步 `README.md`、`CONTRIBUTING.md` 与两份语言文件。
- 发布前检查 `git diff --check`、工作区干净、调试视图全部关闭、游戏日志无编译错误。
- 不发布未经同条件画面对比的视觉参数调整；提交采用 Conventional Commits。

## 反馈

提交问题时建议提供：Minecraft / Fabric / Iris 版本、游戏语言、天气与时间、使用的性能预设、当前机位截图、相关选项值，以及游戏日志中的相关片段。涉及闪烁问题时请说明观察方式，以便区分渲染缺陷与截图过程本身的干扰。

## 许可

自有源码与文档采用 Apache-2.0；参考光影的学习边界见 `NOTICE.md`。本准则不改变任何许可条款。

## English Summary

Zephyr is a free, open-source, self-authored shaderpack for Minecraft Java Edition (1.21.1 / Fabric 0.18.4 / Iris 1.8.x). Stability takes priority over visual quality, configurability, performance coverage and feature count. The in-game options screen is bilingual (English / Simplified Chinese) with four performance presets that only change public options. Every setting has a documented default and can be turned off; the pack never modifies world saves, places blocks, runs commands, changes the player position, requires external downloads, or collects telemetry. Known limitations — slight distant shimmer on cutout foliage, loader-bounded shadow resolution/distance, and effects still in development — are disclosed in `README.md`. Releases require a clean build, disabled debug views, no compilation errors and same-condition visual comparisons. Licensed under Apache-2.0; see `NOTICE.md` for third-party boundaries.
