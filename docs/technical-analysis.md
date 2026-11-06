# 参考光影技术分析

本分析基于本机 `shaderpacks` 目录中的 14 套参考包，对文件结构、入口数量、compute 使用和关键模块名称做了扫描，并抽查了关键源码路径。统计用于架构判断，不代表不同版本之间的严格性能排名。

## 1. 参考样本

| 类别 | 参考包 | 主要价值 |
| --- | --- | --- |
| 基础与性能 | Chocapic13 V6/V9、SEUS Renewed、SEUS v11 | 经典 gbuffer、阴影、雾和后处理的简洁组织 |
| 综合型 | BSL、Bliss、Complementary、Euphoria Patches | 功能覆盖、质量档位、材质和设置系统 |
| 高质量时域 | SEUS PTGI E12、SEUS PTGI HRR 3、Solas | 屏幕空间路径追踪、历史重投影、降噪和水体效果 |
| 复杂管线 | Photon、iterationT、Continuum | compute、体素 GI、预计算大气、froxel、FFT 和大型后处理链 |

## 2. 结构和调度

### 2.1 入口组织

BSL、Complementary、Photon 等使用清晰的 gbuffer / shadow / composite 或 deferred 入口，便于按 Minecraft/Iris pass 调试。Continuum 则把许多工作拆为 `Passes/*.comp`，并用维度目录组织场景特化逻辑。Chocapic13 和 SEUS 的入口更接近传统 composite 链，结构较容易理解，适合低成本起步。

### 2.2 Compute 使用

本地样本中 Continuum 的 compute 文件最多，Photon、Bliss、BSL、Complementary 和 Solas 也使用 compute 完成部分阴影、体素或后处理。结论是：Zephyr 可以把 compute 作为 High 路径的加速与预计算工具，但不能把它作为 Low 路径的唯一依赖；必须保留 fragment 降级路线。

## 3. 光照、GI 和阴影

| 方案 | 参考实现特征 | 适合借鉴的原则 | Zephyr 取舍 |
| --- | --- | --- | --- |
| 阴影贴图 + PCF/PCSS | BSL、Complementary、Chocapic13、Photon | 稳定、兼容性好、可按档位扩展 | 作为所有档位的基础 |
| 屏幕空间接触阴影 | Solas、iterationT 等 | 补足小尺度遮蔽和接触关系 | 只做局部细节，避免替代主阴影 |
| 体素/LPV 彩色光 | BSL、Bliss、Photon、Continuum | 稳定传递局部彩色光，拖影少 | Medium/High 的主 GI 候选 |
| SSGI/SSPT + 时域降噪 | Solas、SEUS PTGI、Photon | 细节丰富，但依赖历史和深度质量 | 作为细节层，必须独立历史缓冲 |
| 全路径追踪式效果 | SEUS PTGI、Solas 的高质量路径 | 视觉上限高，成本和噪声也高 | 不作为第一阶段主路径 |

核心判断：先做稳定的直接光 + 阴影 + 简化局部光，再叠加体素或 SSGI 细节；不要一开始把整个渲染器押在高采样路径追踪上。

## 4. 天空、大气、云和体积

- iterationT 使用预计算大气与体积雾模块，说明 LUT 能把复杂散射从每像素计算中移走。
- Photon 采用大气、云、LPV 雾和天空 SH 等模块化组织，适合观察“预计算资源 + 实时合成”的边界。
- Continuum 的 `FroxelVolume.glsl`、`Froxels.glsl`、`AirVolume.glsl` 与 `C0A_GenerateFroxels.comp` 展示了 3D 体积介质的完整组织，但资源和调度复杂度最高。
- Complementary、Bliss、Chocapic13 和 Solas 的云方案更强调质量档位和低分辨率重建，适合先建立可控的电影感轮廓。

Zephyr 的顺序应是：解析天空和雾 → 低分辨率云 → 时域重建 → 再评估 froxel。这样能先验证色彩、曝光和空气透视，再承担 3D 体积的成本。

## 5. 水体与材质

- iterationT 和 Continuum 把水面波场推进到 Physics/FFT 级别，适合 High/Ultra 的远景海面。
- Photon、BSL、Solas 和 Chocapic13 都提供水面法线、吸收、雾和反射的模块化实现，适合拆成独立材质系统。
- Complementary/Euphoria 体现了大量可配置的材质和天气选项，优点是覆盖广，风险是设置复杂度高。

Zephyr 先使用多 octave Gerstner/程序法线作为默认路径，水面反射采用 Fresnel + SSR/天空回退；FFT 只在后续高质量档位引入。

## 6. 时域和后处理

参考包普遍使用 TAA 或历史累积，但实现目标不同：SEUS PTGI/Solas 更关注降噪，Photon 更关注 TAA 与曝光组合，iterationT/Continuum 则把 AgX/ACES、Bloom、DOF、运动模糊和镜头效果组织成完整成像链。

Zephyr 需要统一以下时域约定：

1. 相机重投影和历史有效性判断只有一套实现。
2. SSGI、反射、云和体积雾各自拥有独立历史目标，避免互相污染。
3. 方差裁剪和快速相机运动衰减优先于增加采样数。
4. 电影感以后处理顺序固定为曝光 → 色调映射 → Bloom/DOF/镜头效果 → 输出抖动。

## 7. 兼容性与许可证结论

参考包的许可证差异很大：Chocapic13、Photon、Complementary、Continuum、SEUS 和 Solas 都包含不同的修改、再分发或保留条款。尤其 SEUS、Continuum、Complementary 和 Solas 的许可不能假设为开源许可。

因此 Zephyr 采用以下边界：

- 只学习算法类别、渲染目标和公开接口思路，不复制代码片段或资源。
- 不把参考包的许可证、纹理、二进制 LUT 或配置文件加入仓库。
- Zephyr 自研文件统一使用 `ZEPHYR_` / `zephyr_` 命名，保留清晰的原创边界。
- `NOTICE.md` 只说明参考项目用于分析，不声称存在代码继承关系。

## 8. 设计输入

基于上述比较，下一阶段的自研设计应满足：

1. Iris 1.8.x 下有明确的 Low/Medium/High 降级路径。
2. 先建立可运行的 gbuffer、阴影、天空、材质和 final 输出闭环。
3. 直接光和接触阴影先于体素 GI、SSGI、froxel 和 FFT。
4. 时域框架必须在第一批高成本效果之前确定。
5. 每个新增高成本效果都要有资源预算、开关和五场景回归记录。
