# 真实 GUI 回归证据（2026-10-29）

对应源码 `71af78f365b5f60f9c01408229e3279d88b0390e`。完整结论及限制见 [回归报告](../../docs/reviews/pr-161-live-gui-regression.md)。三项通过，启动期间停止的界面反馈部分通过。

- `core-events.log`：实际 console.log 中测试时段的 append/start/stop/任务链终结及连接失败事件。按事件类型摘录，设备 uuid 统一替换为 `<device-id>`。
- `gui-events.log`：实际 gui.log 的测试时段摘录。持久日志与 GUI 当前可见列表不同；这里能看到被界面清掉的忙碌提示。
- `timer-events.log`：实际控制台中唯一测试定时器的设置、失败及关闭输出。Swift print 本身没有附带时间，定时触发时间同时由 Core 和 GUI 持久日志定位。
- `runtime-manifest.json`：测试应用与开发 Core 指纹、前轮 14 项源码摘要、实际事件计数、恢复后的连接和关闭的定时器，以及本地原始证据与公开摘录的 SHA-256。

这些文件由真实进程的持久日志筛选生成，没有重新运行模型 harness 来代替真实 GUI 验收。快捷键和原生可见状态由 CUA 会话观察，日志摘录本身不能重建全部输入。游戏截图含账号信息，仅保存在本机，未加入仓库。
