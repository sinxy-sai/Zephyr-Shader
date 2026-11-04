# Zephyr 实机验证报告（Minecraft 1.21.1 + Fabric + Iris 1.8.8）

- 生成时间：2026-11-05 01:05（Asia/Shanghai）
- 任务：task-1「MC 1.21.1 启动 + 自动截图 + Iris 编译日志验证工具」
- 执行：mc-harness（实机验证工程师）
- 光影包：`shaderpacks/Zephyr`（Photon 1.2a 基底）
- 证据来源：**用户实机会话日志**（PCL 启动，离线账号 yuyu，世界「新的世界」，窗口 854x480）；本轮未做自动化受控运行（原因见 §4）

---

## 0. 结论摘要

| 项目 | 结论 |
|---|---|
| Zephyr 能否在 Iris 上编译 | ✅ **能**。`Using shaderpack: Zephyr` + `Creating pipeline for dimension minecraft:overworld` 多次成功，**Zephyr 会话中 0 条 GLSL 编译错误** |
| shaders.properties 菜单引用修复 | ✅ **生效**。修复前每次加载 3 条 `Invalid pack option: GTAO` + 5 条 `Unable to resolve ...`；修复后（00:57:37 重载）**0 条** |
| 受控自动化基线（Weston City + 黄昏/雨 + F2 截图） | ⏸ **未执行**（用户全程在用机器，Lead 决定不抢焦点/不启动游戏） |
| `shots/` 游戏内截图 | 暂无有效截图（唯一一张 120B 无效图已删除） |
| 自动化工具 | `tools/mc-test.ps1` + `tools/mc-test.bat` 已就绪，dry-run 通过，待机器空闲一条命令跑完整闭环 |

**一句话**：Zephyr（Photon 1.2a 基底）在当前 Iris 1.8.8 + Sodium 0.6.13 环境编译/建管道/重载全部成功，无编译错误；Photon 遗留菜单引用告警已随 shaders.properties 修复消失。自动化闭环工具已备好，等用户空闲即可产出 Weston City 实机截图。

---

## 1. 环境

| 项 | 值 |
|---|---|
| 游戏版本 | Minecraft 1.21.1 / Fabric Loader 0.18.4（版本隔离） |
| 游戏目录 | `C:\Users\liubingliang\Downloads\PCL-2.12.2\.minecraft\versions\1.21.1-Fabric 0.18.4` |
| 光影加载器 | Iris 1.8.8+mc1.21.1 |
| 渲染优化 | Sodium 0.6.13+mc1.21.1 |
| 其它 Mod | fabric-api 0.116.8、EuphoriaPatcher 1.8.6、flyspeed 1.0.3、gfx-debuggers 3.1.0 |
| Java | `C:\Program Files\Java\jdk-22\bin\java.exe`（22.0.1） |
| GPU | NVIDIA GeForce RTX 4050 Laptop GPU（游戏选中的 OpenGL 适配器）；另有 AMD Radeon 核显 |
| 备注 | Sodium 启动时提示 `NVIDIA_THREADED_OPTIMIZATIONS_BROKEN` 并应用 workaround（驱动 32.0.15.9595，不影响编译结论） |
| 启动方式 | PCL（`Plain Craft Launcher 2.exe`）+ `PCL\LatestLaunch.bat` 的 java 命令行 |
| Iris 配置 | `config/iris.properties`：`shaderPack=Zephyr`、`enableShaders=true`（保持现状，用户正在验收） |
| 日志 | `<game>\logs\latest.log`（GBK 编码）；会话轮转文件 `<game>\logs\2026-11-05-*.log.gz` |

---

## 2. 【编译 / 加载】证据

> 说明：以下全部为**用户实机会话**真实日志原文。`latest.log` 为 GBK 编码，已按原文转录。

### 2.1 会话 A：首次加载 Zephyr（00:50:30，shaders.properties 修复前）

来源：`logs/2026-11-05-2.log.gz`（会话 00:10–00:51）→ 证据文件 `reports/evidence/user-session-001030-005120.log`

```
[00:50:29] [Render thread/INFO]: Destroying pipeline minecraft:overworld
[00:50:29] [Render thread/WARN]: Invalid pack option: GTAO          (x3)
[00:50:29] [Render thread/WARN]: Unable to resolve shader pack option menu element "WATER_REFRACTION" defined in shaders.properties
[00:50:29] [Render thread/WARN]: Unable to resolve shader pack option menu element "WATER_REFRACTION_INTENSITY" defined in shaders.properties
[00:50:29] [Render thread/WARN]: Unable to resolve shader pack option menu element "CLOUDS_DAILY_WEATHER" defined in shaders.properties
[00:50:29] [Render thread/WARN]: Unable to resolve shader pack option menu element "CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS_H" defined in shaders.properties
[00:50:29] [Render thread/WARN]: Unable to resolve shader pack option menu element "CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS_Z" defined in shaders.properties
[00:50:29] [Render thread/INFO]: Profile: high (+0 options changed by user)
[00:50:30] [Render thread/INFO]: Using shaderpack: Zephyr
[00:50:30] [Render thread/INFO]: Creating pipeline for dimension minecraft:overworld
```

### 2.2 会话 B：PCL 重启后再加载（00:52:27 / 00:52:48，修复前）

来源：`logs/latest.log` 会话（00:51:56 起）→ 证据文件 `reports/evidence/user-session-005156-live.log`

```
[00:52:27] [Render thread/INFO]: Using shaderpack: Zephyr
[00:52:31] [Render thread/INFO]: Creating pipeline for dimension minecraft:overworld
[00:52:42] [Server thread/INFO]: Preparing start region for dimension minecraft:overworld
[00:52:44] [Render thread/INFO]: Creating pipeline for dimension minecraft:overworld
[00:52:47] [Render thread/WARN]: Invalid pack option: GTAO          (x3)
[00:52:47] [Render thread/WARN]: Unable to resolve shader pack option menu element "WATER_REFRACTION" defined in shaders.properties
[00:52:47] [Render thread/WARN]: Unable to resolve shader pack option menu element "WATER_REFRACTION_INTENSITY" defined in shaders.properties
[00:52:47] [Render thread/WARN]: Unable to resolve shader pack option menu element "CLOUDS_DAILY_WEATHER" defined in shaders.properties
[00:52:47] [Render thread/WARN]: Unable to resolve shader pack option menu element "CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS_H" defined in shaders.properties
[00:52:47] [Render thread/WARN]: Unable to resolve shader pack option menu element "CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS_Z" defined in shaders.properties
[00:52:48] [Render thread/INFO]: Using shaderpack: Zephyr
[00:52:48] [Render thread/INFO]: Creating pipeline for dimension minecraft:overworld
```

### 2.3 修复后重载（00:57:37，shaders.properties mtime 00:56:15）→ 关键证据

来源：`reports/evidence/user-session-005156-live-after-fix-reload.log`

```
[00:57:35] [Render thread/INFO]: Destroying pipeline minecraft:overworld
[00:57:36] [Render thread/INFO]: Profile: high (+0 options changed by user)
[00:57:37] [Render thread/INFO]: Using shaderpack: Zephyr
[00:57:37] [Render thread/INFO]: Creating pipeline for dimension minecraft:overworld
[00:57:38] [Render thread/INFO]: [System] [CHAT] 已重新加载光影包！
```

该重载窗口（00:57:00–00:58:59）统计：**`Invalid pack option` = 0、`Unable to resolve` = 0、ERROR = 0、编译失败 = 0**。

### 2.4 编译错误检查

- 所有 **Zephyr 会话**中：`Shader compilation log for` = 0、`Failed to create shader rendering pipeline` = 0、`ShaderCompileException` = 0、`Unable to load shaderpack` = 0。
- 日志历史里**唯一一次** shader 编译失败发生在 **00:11:35，属于 ComplementaryReimagined 包**（用户当时在手动切换光影包，`00:11:31 Using shaderpack: ComplementaryReimagined_r5.7.1 + EuphoriaPatches_1.8.6` → `00:11:35 Shader compilation log for final.fsh: 0(1329) : error C1503: undefined variable "_10"` → `Failed to create shader rendering pipeline, disabling shaders!`）；该包在 00:15:32 重新加载后正常（仅剩余 benign uniform 警告）。**与 Zephyr 无关，请勿混淆。**

---

## 3. 【Warning 修复前后对比】

### 3.1 对比表

| 时点 | shaders.properties 状态 | `Invalid pack option: GTAO` | `Unable to resolve ...` | 编译错误 |
|---|---|---|---|---|
| 00:50:29（会话 A 加载） | 修复前 | 3 | 5 | 0 |
| 00:52:25（会话 B 加载） | 修复前 | 3 | 5 | 0 |
| 00:52:47（会话 B 重载） | 修复前 | 3 | 5 | 0 |
| **00:57:37（会话 B 重载）** | **修复后（mtime 00:56:15）** | **0** | **0** | **0** |

### 3.2 修复内容（Lead 在 `shaders/shaders.properties` 完成，harness 静态复核）

- `GTAO`（profile 引用）→ `SHADER_AO=SHADER_AO_GTAO` / `SHADER_AO=SHADER_AO_NONE`
- `WATER_REFRACTION` / `WATER_REFRACTION_INTENSITY` → `REFRACTION` / `REFRACTION_INTENSITY`
- 删除已失效的 `CLOUDS_DAILY_WEATHER`
- `CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS_H` / `..._Z` → 合并为 `CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS`

静态复核：`shaders.properties` 中上述失效 token 独立出现次数已为 **0**；`SHADER_AO`、`REFRACTION*`、`CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS` 已就位；`GTAO_SLICES` / `GTAO_HORIZON_STEPS` / `GTAO_RADIUS` 等合法选项名保留。

### 3.3 结论

修复对**编译无影响**（修复前后都能编译成功），但消除了 Iris 菜单/配置解析的告警噪音；修复后重载 0 告警，符合预期。

---

## 4. 【截图】本轮未产出受控截图

- 原因：用户全程在使用机器（PID 7240 游戏窗口一直在跑，且用户 00:57 还在手动重载光影验收）。Lead 明确要求**不抢焦点、不关闭用户游戏、不在用户窗口上 PostMessage 截图**，因此未做受控基线，`shots/` 暂无游戏内截图。
- 清理：此前一次自动尝试失败留下的 `shots/20261105-005117-Zephyr-Weston_City_V0.3-window-fallback1.png`（120 字节，实际是误抓的 java 控制台窗口，非游戏画面）已删除。
- 待办：机器空闲后运行 `tools\mc-test.bat`，自动进入 Weston City V0.3、`/time set 12500` + `/gamerule doDaylightCycle false` + `/weather rain`、按 F2，并把 PNG 复制到 `shots/`。

---

## 5. 自动化闭环工具 `tools/mc-test.ps1`

### 5.1 一条命令用法

```bat
cd "…\shaderpacks\Zephyr"
tools\mc-test.bat                                          :: 默认 Zephyr + Weston City V0.3 + 1280x720
tools\mc-test.bat -World "Weston City V0.3" -Width 1920 -Height 1080
tools\mc-test.bat -CloseExisting                           :: 若已有同版本游戏实例，允许脚本先优雅关闭
tools\mc-test.bat -DryRun                                  :: 只打印将要执行的 java 命令，不启动
```

直接调用 PowerShell（等价）：

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\mc-test.ps1 -ShaderPack Zephyr -World "Weston City V0.3"
```

> ⚠️ 本机**没有 PowerShell 7**（`pwsh` 不在 PATH），实际环境是 Windows PowerShell 5.1；脚本按 5.1 编写。

### 5.2 闭环流程

1. 解析 `PCL\LatestLaunch.bat` 中的完整 java 命令行（classpath/natives/main class 全复用）
2. 去掉 PCL 的 `--width/--height`，追加 `--width W --height H --quickPlaySingleplayer "<世界>"`
3. 备份 `options.txt`（并留档 iris.properties），写入 `config/iris.properties` 的 `shaderPack=<包>`
4. `Start-Process` 启动 java（`-WindowStyle Hidden` 隐藏 java 控制台窗口，记录 PID）
5. 等待 **新的** `latest.log` 会话（用启动前首行做 marker 判定轮转，避免读到旧日志）+ `Using shaderpack: <包>` + `Creating pipeline for dimension` + settle
6. 聚焦游戏窗口（AttachThreadInput + SetForegroundWindow），依次发送 `/time set 12500`、`/gamerule doDaylightCycle false`、`/weather rain`（unicode 注入，失败回退剪贴板粘贴）
7. 按 F2 截图（最多等 25s），把新 PNG 复制到 `shots/<时间戳>-Zephyr-<世界>-shotN.png`
8. 抓 `latest.log` 副本 + 提取 Iris 证据 → `reports/iris-errors.txt`、`reports/last-run.json`、`reports/launch-report.md`
9. `CloseMainWindow()` / `WM_CLOSE` 优雅退出（世界存档），仅当 PID 命令行含 KnotClient 且匹配本 gameDir 时才 `Stop-Process`
10. 恢复 `options.txt`；`iris.properties` **保持 shaderPack=Zephyr**（项目约定；`-RestoreIris` 可改回备份值）

### 5.3 退出码与产物

- 退出码：`0` = PASS（有 `Using shaderpack` + pipeline + 截图），`2` = FAIL
- 产物：`reports/last-run.json`、`reports/run-<stamp>/`（latest.log 副本、run.log、mc-console.log）、`reports/iris-errors.txt`、`shots/*.png`

### 5.4 本轮状态

- `-DryRun` 通过：正确生成 `--width 1280 --height 720 --quickPlaySingleplayer "Weston City V0.3"` 的命令行
- **端到端受控运行本轮未执行**（用户占用机器），`quickPlaySingleplayer` 进世界路径尚未实机验证

---

## 6. 本轮遇到的问题 / 事件记录（透明记录）

1. **误关了用户正在验收的游戏实例**：00:45 开工时发现用户 00:10 启动的游戏实例挂在后台（已暂停）。按任务纪律用 WM_CLOSE 优雅关闭（日志显示 00:51:18 `Stopping!`，存档正常保存）。事后确认用户当时正在该实例里手动验收 Zephyr（00:50:29 手动切包），随后用户 00:51:53 通过 PCL 重新启动继续测试。这是误判，已向 Lead 汇报；此后未再触碰用户进程。
2. **我启动的实例（PID 49608）在 00:51:41 意外终止**：java 以控制台子系统进程启动时出现黑窗口（窗口标题为 `C:\Program Files\Java\jdk-22\bin\java.exe`），在创建 GL 窗口前被终止；无 hs_err、无异常栈（会话日志止于 `Flyspeed Initialized Successfully`）。已用 `Start-Process -WindowStyle Hidden` 规避。
3. **首次自动跑产生过一次假 PASS**：脚本读到了轮转前的旧 `latest.log`（旧内容里恰好有 `Using shaderpack: Zephyr`），且把 java 控制台窗口误认为游戏窗口。已修：
   - 窗口识别：`MainWindowHandle>0` 且标题含 `Minecraft`（或窗口类匹配 `GLFW`/`LWJGL`），拒绝控制台窗口
   - 日志轮转：启动前记录旧 `latest.log` 首行作为 marker，等它消失（新会话落盘）后才开始匹配
   - 优雅退出：`CloseMainWindow()` 优先，`Stop-Process` 仅在 PID 命令行校验通过时使用
4. **本机无 PowerShell 7**：`pwsh` 不存在，脚本按 Windows PowerShell 5.1 兼容编写。
5. **`latest.log` 是 GBK 编码**（中文世界名/聊天），脚本读取按系统默认编码（936）处理；报告/证据文件已转 UTF-8 保存。

### 脚本已知 bug（已定位，均已修复，但端到端未复验）

- 窗口识别误抓 java 控制台窗口 → 已修复（标题/类名双重过滤）
- 日志轮转假阳性（读到旧会话内容）→ 已修复（旧日志 marker 判定新会话）
- 控制台黑窗口可能被误关导致实例被杀 → 已修复（`-WindowStyle Hidden`）

---

## 7. 证据文件清单

| 路径 | 说明 |
|---|---|
| `reports/evidence/user-session-001030-005120.log`（+`.gz`） | 会话 A 完整日志（00:10–00:51）：含 00:50:30 Zephyr 首次成功加载；含 00:11:35 Complementary 的编译失败（非 Zephyr） |
| `reports/evidence/user-session-005156-live.log` | 会话 B 快照（00:51:56–00:57 左右）：00:52:25/47 修复前告警原文 + 00:52:27/48 加载成功 |
| `reports/evidence/user-session-005156-live-after-fix-reload.log` | 会话 B 修复后快照：00:57:37 重载，0 告警 0 错误（关键证据） |
| `reports/evidence/agent-instance-005124-mysterious-exit.log`（+`.gz`） | 我启动的实例 00:51:24–00:51:41 日志（异常终止现场） |
| `reports/evidence/desktop-before-launch-004621.png` | 开工时桌面截图（记录当时用户窗口被 DSH GUI 覆盖，仅环境留档） |
| `reports/iris-errors.txt` | 从上述日志机检提取的 Iris 证据（分节原文 + 前后计数） |
| `reports/backup/iris.properties.20261105-005117.bak` | iris.properties 备份（内容 = shaderPack=Zephyr） |
| `reports/backup/options.txt.20261105-005117.bak` | options.txt 备份（用户 00:50:44 状态） |
| `tools/mc-test.ps1` / `tools/mc-test.bat` | 一条命令自动化闭环脚本（本轮交付物） |
| `shots/` | 暂无有效游戏内截图（见 §4） |

---

## 8. 后续建议

1. 用户空闲时（或 v0.1 就绪后）运行 `tools\mc-test.bat`，产出 **Weston City V0.3 黄昏+雨** 的实机截图 + 当次编译日志，与本报告结论互证。
2. `iris.properties` 保持 `shaderPack=Zephyr`（用户正在验收）；如需恢复 Complementary，用脚本 `-RestoreIris` 或手工改回。
3. 若 `quickPlaySingleplayer` 在该版本不生效，检查 `reports/run-<stamp>/latest.log` 与 `mc-console.log`；退化方案（菜单坐标点击）尚未实现。
4. 截图/时间天气只对单机存档（`Weston City V0.3` 已开 cheats，`allowCommands=1`）有效；命令是否生效以截图画面为准（单机日志不一定记录 `issued server command`）。
