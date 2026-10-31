# PR #161 评审核实与修复验证

日期：2026-10-29。基线：`3d3cc38d0d3406f66e551dca3ca8283fad86ed02`，对应 [PR #161](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161)。首轮修复针对该提交的四条评审意见；首轮生产代码和回归测试的 SHA-256 记录在 [manifest.json](../../artifacts/pr-161-review/manifest.json)。

## 首轮四条意见的结论（111fbb0）

| 评审 | 核实 | 修复 |
| --- | --- | --- |
| [4409248943](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#discussion_r4409248943)：Copilot / 识别与运行中任务重叠 | 存在状态破坏，但“会直接追加并启动忙碌核心”描述过强。`ensureHandle()` 已检查 `running` 并抛错；此前调用方先设 pending，出错后又恢复 idle，所以核心继续运行、UI 却显示 idle。 | 在更改状态、访问 handle 前要求 idle；所有同一核心的启动入口使用同一准入检查。干员识别、寻访、小游戏也受保护，避免绕过进行中标记。 |
| [4409248947](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#discussion_r4409248947)：开始按钮可用但请求被拒 | 成立。核心回调可在异步调用返回前将 status 置为 idle，原菜单只观察 status。 | `isStartStopInFlight` 改为 Published；统一 `canStartTasks`，菜单、任务与工具按钮使用它；NewViewModel 观察 status 和操作标记两者，更新 Copilot 的可用状态。 |
| [4409248954](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#discussion_r4409248954)：Copilot 未启动却切至日志 | 成立。token 在配置校验和父级启动之前就已更新，父级忙碌时还正常返回。 | 拒绝请求时抛错；父级实际启动成功后才更新 token。配置无效、连接失败、核心启动失败均不发布成功信号。 |
| [4409248960](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#discussion_r4409248960)：启动期间请求被静默丢弃 | 成立。原 stop 和受保护的启动方法遇到进行中操作直接正常返回。 | 采用评审建议的“显式忙碌结果”方案：抛出 `taskOperationInProgress`，同时记录“当前正在启动或停止任务，请稍后重试。”；运行中启动则抛出 `taskAlreadyRunning`。不会把停止请求排队；原操作结束后可重试停止，回归用例验证重试真正调用核心停止。 |

## 首轮验证（111fbb0，历史记录）

在首轮提交上运行：

```sh
python3 Tests/run-task-operation-tests.py
```

runner 从当前生产源码逐字提取状态声明、日常启动、停止、Copilot / 所有工具入口、菜单禁用条件及 Copilot 桥接方法和 Observation 订阅；编译执行 Swift 测试。替身仅用于核心 / 连接边界、与用例无关的配置及模型初始化。用 continuation Gate 精确暂停连接和停止，而非依赖休眠碰时序；不复制入口守卫实现。

- 原 PR 提交：82 项断言，27 项失败，退出码 1，见 [before.log](../../artifacts/pr-161-review/before.log)。runner 支持 `MAA_TEST_SOURCE_ROOT` 指向源码快照；对基线提取的源码跑同一 runner，可重复这些失败。
- 修复后：116 项断言全部通过，见 [after.log](../../artifacts/pr-161-review/after.log)。额外覆盖全部七类工具启动的跨 await 保护、仅操作标记释放时的 Observation 更新、启动 / 连接 / 停止失败后的释放、重复停止与停止重试。额外 Observation 用例在基线尚无此属性时不编译。
- `git diff --check` 通过。
- 完整 macOS Debug arm64 应用构建成功，见 [xcodebuild.log](../../artifacts/pr-161-review/xcodebuild.log)（仅去除行尾空白）。仍有工程既存的未消费 throwing Task 等警告；没有将此称为零警告构建。新增冲突拒绝在抛出前写入应用日志，不依赖调用者消费 Task 结果。

构建使用临时工程 `/tmp/maa-pr161-build-project/MeoAsstMac.xcodeproj`，源码目录符号链接指向本工作区。仅临时工程的外部 Core / 资源路径改成当前主机的绝对路径；未修改仓库工程文件。Swift 包使用本地主工程现有的忽略锁文件和已缓存依赖（JBird `c9d750d6ed069f37b4bd543327cffaa44280a594`、Sparkle 2.10.1、ZIPFoundation 0.9.20、swift-syntax 603.0.2）。

```sh
xcodebuild -project /tmp/maa-pr161-build-project/MeoAsstMac.xcodeproj \
  -scheme MAA -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/maa-pr161-derived \
  -clonedSourcePackagesDirPath /tmp/maa-pr163-20261029-derived/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

## 本轮追加核实：核心仍运行但 UI 已空闲

上一轮 head：`111fbb0b63b730f555f4f8020ba10dc0f4a56100`。Sourcery 自动确认并关闭了首轮四条意见，随后新增 [4410030637](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#discussion_r4410030637)。

意见成立：操作标记已释放后，回调仍可能使 UI 显示 idle，而核心的 running 为 true。原准入检查只读 UI 状态，进入 pending 后才在 ensureHandle 检查核心，再次回到 idle，持续提供会失败的启动按钮。

修复：

- `beginTaskOperation()` 改为异步；先设置进行中标记，再查询核心 actor 的 running，防止查询挂起时其他启动或停止插入。
- 查询到运行中的核心时，将 UI 校正为 busy，抛出 `taskAlreadyRunning`，且不进入 pending、不准备连接、不追加任务。查询返回后同时复核 UI 状态，避免 await 期间的回调使此前判断过期。
- 准入失败或查询期间被取消时，由 helper 释放预约标记；准入成功后交由调用者的 defer 释放。停止路径不要求核心空闲。
- 日常启动也走这一核心准入入口。ensureHandle 的后续 running 检查作为防御，会保留 busy，避免核心稍后开始运行时错误地恢复 idle。
- runner 直接提取 ensureHandle 的生产 running guard，不再在替身中手写这段检查；Swift 模块缓存位于临时目录。

当前命令仍为 `python3 Tests/run-task-operation-tests.py`。用当前 runner 对 `111fbb0` 源码快照运行：**178 项断言、32 项失败、退出码 1**（[before.log](../../artifacts/pr-161-core-running/before.log)）；修复后 **242 项断言全部通过**（[after.log](../../artifacts/pr-161-core-running/after.log)）。新增异步准入专属用例在旧同步 helper 源码上不编译。

覆盖全部八类启动（每日任务和七类工具）的 stale-idle 场景、核心查询期间的重复启动及停止、查询过程中核心 / UI 状态变化、取消、ensureHandle 后续 running 拒绝、首次无 handle 启动及停止后重试。

完整 macOS Debug arm64 构建成功（[xcodebuild.log](../../artifacts/pr-161-core-running/xcodebuild.log)，仅去除行尾空白）；构建工程、命令和依赖与首轮相同。当前源码与测试摘要见 [manifest.json](../../artifacts/pr-161-core-running/manifest.json)。`git diff --check` 通过。

## 停止冲突日志断言的归因修复

Sourcery 在 `c4dae14` 新增 [4411856833](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#discussion_r4411856833)，指出 `!model.errors.isEmpty` 无法证明日志来自 stop。当前重复日常启动会被 canStartTasks 提前拦截，本身不写日志；但已有其他错误时，宽泛断言确实可能掩盖停止日志缺失。

本轮仅修改测试与验证材料：先添加一条无关诊断作为前置条件，紧贴 stop 调用前快照日志数；stop 被拒后只检查新增切片，要求它恰好等于预期的忙碌提示。旧日志无法再满足该断言。

- 当前完整回归：**242 项断言、0 失败**（[clean.log](../../artifacts/pr-161-stop-log/clean.log)）。
- 可重跑变异验证：`python3 artifacts/pr-161-stop-log/mutation-check.py`。脚本仅在临时副本中让停止冲突路径不写日志，保留其他启动冲突日志，并提供相同的先前无关错误。
- 旧宽泛断言在该变异下误通过（242 项、0 失败）；修复后准确失败，且仅报 `stop rejection appends its own busy log`（242 项、1 失败）。详见 [mutation.log](../../artifacts/pr-161-stop-log/mutation.log)、[old-oracle.log](../../artifacts/pr-161-stop-log/old-oracle.log)、[fixed-oracle.log](../../artifacts/pr-161-stop-log/fixed-oracle.log)。脚本自身在两种预期结果均得到验证后退出 0。
- 生产代码、工程及依赖声明与 `c4dae14` 一致；本轮未重复构建应用，沿用该提交的完整 Debug arm64 构建证据。源码摘要见 [manifest.json](../../artifacts/pr-161-stop-log/manifest.json)。

## 变异脚本的子进程参数审计

`19af36a` 在推送前已完成 Standards 和 Spec 两项独立审核，均 PASS、无需修改；Spec 审核还独立重跑完整回归和变异验证。随后 Sourcery 对脚本发出 [4412002542](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#discussion_r4412002542) 的 `dangerous-subprocess-use-audit`，因为 subprocess.run 参数中包含动态拼接的临时脚本路径。

旧调用使用参数列表、没有启用 shell，且路径由本地临时目录生成；未发现外部输入形成 shell 注入的路径。本轮将命令本身改为两个固定字符串 `['python3', 'Tests/run-task-operation-tests.py']`，仅通过 cwd 选择生成的临时副本，并显式设置 shell=False。验证内容不变，不添加针对审计规则的忽略标记。

重跑变异验证通过：旧断言在缺失停止日志时误通过，新断言准确失败一次。AST 检查也确认该调用 argv 全为字符串字面量且 shell=False，见 [static-command.log](../../artifacts/pr-161-stop-log/static-command.log)。生产代码、任务测试和工程均未变化；本轮只重新运行受调整影响的变异验证，没有重复应用构建。

## 完整重审：快速完成回调与定时器结果

自动复查通过及旧线程关闭，并不代表已经重新进行完整代码审查。2026-10-29 对 `c6da345` 单独发送 `@sourcery-ai review` 后，Sourcery 发布了 [完整审查 5697457563](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#pullrequestreview-5697457563)，新增两条有效意见：

- [4412137251](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#discussion_r4412137251)：核心快速完成，resetStatus 在 handle.start 返回前已清理状态，随后恢复的启动代码却重新写入 busy 和日常启动时间。
- [4412137260](https://github.com/MaaAssistantArknights/MaaMacGui/pull/161#discussion_r4412137260)：Bool 无法区分准入跳过与实际启动失败，定时器错误地把连接 / 核心启动失败记为跳过。

初始候选 `8fb205e` 让 resetStatus 推进完成代次，并在实际 start 前捕获代次；该候选未推送，双审核进一步发现旧运行回调延迟到达时可能误判新任务完成，最终修正见下节。所有八类启动继续共用 startCoreTasks。

日常执行新增 started / skipped / failed 结果，定时器穷尽处理这三种结果；菜单等原调用方继续使用兼容的 Bool 包装入口 tryStartTasks。快速完成仍算实际启动成功，即使启动方法返回时已空闲。

测试 runner 直接提取生产 resetStatus、公共启动收尾方法、结果类型和日常结果入口，并执行生产定时器方法的异步日志分支；核心替身只在真实 start 调用边界提供可控暂停。

- 上一提交 c6da345：289 项断言、29 失败、退出码 1（[before.log](../../artifacts/pr-161-completion-timer/before.log)）。
- 本轮：289 项断言全部通过（[after.log](../../artifacts/pr-161-completion-timer/after.log)）。覆盖八类快速完成及重启、元数据不复活、先前回调、连接失败 / 核心启动失败的定时器日志、正常开始与状态变化跳过。
- 原停止日志变异证明仍成立：旧断言 242/0，新断言准确失败一次 289/1（[mutation-old.log](../../artifacts/pr-161-completion-timer/mutation-old.log)、[mutation-fixed.log](../../artifacts/pr-161-completion-timer/mutation-fixed.log)）。新增 timer 源文件也复制到每个变异快照；旧版断言数保持历史基线，当前目标失败断言数按实际套件核验。
- 完整 macOS Debug arm64 构建成功（[xcodebuild.log](../../artifacts/pr-161-completion-timer/xcodebuild.log)，仅去除行尾空白），工程、依赖与命令与此前相同；不代表真实游戏并发验收。

## 推送前双审核追出的旧回调问题

两个独立审核代理分别复现：先启动并停止上一轮任务，马上启动下一轮；上一轮 TaskChainStopped 在新 start 等待 actor 执行之前或执行之后才被处理。初始候选 8fb205e 的全局代次变化不能区分旧、新运行，因此可能保留 idle 并丢掉新运行的启动元数据。该候选未推送。

最终改为在核心 start 返回后重新读取实际 running。代次只用于判断这次跨 actor 的 running 读数是否已经被回调更新过；若过期就重读。稳定读数为运行中时发布 busy 和日常启动时间；核心已停时清理完成状态。这样既不会复活真正快速完成的任务，也不会因旧停止回调而压制正在运行的新任务。

- 对初始候选 8fb205e 的新用例：297 项断言、4 失败（[before.log](../../artifacts/pr-161-post-start/before.log)）。
- 最终：305 项断言、0 失败（[after.log](../../artifacts/pr-161-post-start/after.log)）。保留全部快速完成与定时器分类用例，补充旧回调在实际 start 前 / 后到达，以及 running 读取本身返回旧值时的重读与元数据一致性。
- 变异验证仍准确定位缺失停止日志：旧断言 242/0，新断言 305/1、且唯一失败为目标日志断言（[旧](../../artifacts/pr-161-post-start/mutation-old.log)、[新](../../artifacts/pr-161-post-start/mutation-fixed.log)）。
- 最终完整 macOS Debug arm64 构建成功（[xcodebuild.log](../../artifacts/pr-161-post-start/xcodebuild.log)，只移除行尾空白）；当前源码摘要见 [manifest.json](../../artifacts/pr-161-post-start/manifest.json)。

## 模型验证的证据边界（真实 GUI 补测前）

此前这些测试复现并锁定 GUI 模型的准入、异步时序与通知行为，完整构建检查真实类型和 SwiftUI 调用点。截至该阶段，未启动正式应用、连接游戏、实际执行识别 / 作业 / 寻访，未验证游戏端停止时延或真实 Core 回调次序，也未声称完成连接游戏后的 GUI 并发验收。没有修改真实偏好或任务文件；评审线程的 resolved 状态不能代替代码与测试核实。

## 真实游戏 GUI 补测（21:04–21:15）

在最终源码 `71af78f` 的独立 Debug 实例中，连接 Arknight AVD 上已登录的 Bilibili 2.7.81 游戏，实际验证重复 ⌘R、启动期停止及重试、短任务 / 空队列快速收尾后的重启、自然触发定时器的连接失败及恢复。**三项通过，启动期停止的互斥和重试通过但界面忙碌提示被清掉，该项部分通过。** 本轮没有修改生产代码。

**后续修复：** 该"部分通过"的界面忙碌提示缺口已在后续修复提交中闭环：清空上一会话日志的时机移入 `beginTaskOperation()` 准入，且仅在核心运行复核通过、未被取消后才清除准入时刻之前的旧条目，被拒路径不再清空任何日志。上文结论保留为修复前时点的记录，详见 [真实 GUI 回归报告](pr-161-live-gui-regression.md) 的"后续修复"段。

详见 [真实 GUI 回归报告](pr-161-live-gui-regression.md) 和 [证据目录](../../artifacts/pr-161-live-gui/README.md)。实际 Core 为本机 `DEBUG_VERSION` 开发构建；没有验证 PlayCover、实体设备、发布包或全部工具入口，不宣称关闭全部 GUI 验收。
