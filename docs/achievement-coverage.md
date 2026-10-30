# 本地成就覆盖

WPF 定义固定于 MaaAssistantArknights `4d948320d94f54dcc60f558b430aa812bd1c4dcf` 的 `AchievementTrackerHelper.cs` `_allAchievements`，共 111 项。本 PR 提供 45 项引擎定义，其中 41 项当前接入事件。表中“已实现”指生产适配已接入且有本地逻辑测试；不表示真实游戏或高阈值累计已验收。其余逐项保留具体接入依赖；不声明 Windows 全量对齐。

事件计数：StageDrops `cur_times` 是本批成功关数，缺失按 WPF 算 1；不同时累计 FightTimes。药按 UseMedicine.count；临期单批按 is_expiring=true 的 count 最大值。公招刷新按每次成功回调计 1，忽略累计显示 count。非六星累计/连续进度按 RecruitResult 计，六星将连续进度重置为 1，严格保留该固定 WPF 版本现行规则。UnlockClues 后可能进入识别错误分支，SendClues 只表示打开传递页面；交流与赠送进度暂停新增，等待可验证的成功及数量事件。已保存的旧进度不自动清除。GamePass 按 ProcessTask 开始事件；难度只接受成功结算的实际 difficulty。存款取 deposit 最大值。每个 native 接收生成新 envelope；相同 envelope 重分发可去重，相同内容的两个真实接收均计。没有 Core event ID 的消息不能保证跨崩溃恰好一次。

同一安装跨配置共享；不代表游戏账号，不同步，不扫描旧日志。最近 2048 个 envelope ID 与最近运行累计持久保存；解锁 ID 本身永久幂等。旧 schema 1 缺定义保留，未知未来 schema 只读拒绝覆盖；损坏数据先留备份再恢复。隐藏成就解锁前不展示标题或条件。只在原子保存成功后提示。

| ID | Mac 状态 | 入口或依赖 |
|---|---|---|
| `SanitySpender1` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SanitySpender2` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SanitySpender3` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SanitySaver1` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SanitySaver2` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SanitySaver3` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RoguelikeGamePass1` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RoguelikeGamePass2` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RoguelikeGamePass3` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RoguelikeN04` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RoguelikeN08` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RoguelikeN12` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RoguelikeN15` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RoguelikeRetreat` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RoguelikeGoldMax` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `FirstLaunch` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SanityExpire` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `OverLimitAgent` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RecruitGambler` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `ClueCollector` | 依赖未交付 | UnlockClues 可能误识别，需可确认交流成功的事件 |
| `CluePhilosopher` | 依赖未交付 | UnlockClues 可能误识别，需可确认交流成功的事件 |
| `ClueObsession` | 依赖未交付 | 需逐个线索编号与上次开启数据的持久化契约，当前交流/赠送均等待可确认的成功事件 |
| `ClueSharer` | 依赖未交付 | SendClues 仅打开传递页；需可确认成功赠送与数量的事件，暂停新增计数 |
| `CluePhilanthropist` | 依赖未交付 | SendClues 仅打开传递页；需可确认成功赠送与数量的事件，暂停新增计数 |
| `TimeManagementMaster` | 依赖未交付 | 需 Mac 可确认的“时间管理大师”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:622`，当前阶段未接该 GUI/历史事件 |
| `DoubleSync` | 依赖未交付 | 需 Mac 可确认的“人货两清”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:623`，当前阶段未接该 GUI/历史事件 |
| `ResumeRecord` | 依赖未交付 | 需 Mac 可确认的“重新建档”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:624`，当前阶段未接该 GUI/历史事件 |
| `QueueExpansion` | 依赖未交付 | 需 Mac 可确认的“队伍扩编”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:625`，当前阶段未接该 GUI/历史事件 |
| `QueueSimplifier` | 依赖未交付 | 需 Mac 可确认的“精简流程”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:626`，当前阶段未接该 GUI/历史事件 |
| `ScheduleMaster1` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `ScheduleMaster2` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `MirrorChyanFirstUse` | 依赖未交付 | 需 MirrorChyan 下载成功事件适配；当前 Mac 更新源存在但未发成就事件 |
| `MirrorChyanCdkError` | 依赖未交付 | 需 MirrorChyan 可确认 CDK 错误类型适配 |
| `Pioneer1` | 依赖未交付 | 需 Mac 可确认的“将 MAA 更新至公测版”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:636`，当前阶段未接该 GUI/历史事件 |
| `Pioneer2` | 依赖未交付 | 需 Mac 可确认的“将 MAA 更新至内测版（隐藏）”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:637`，当前阶段未接该 GUI/历史事件 |
| `Pioneer3` | 依赖未交付 | 需 Mac 可确认的“使用未发布版本的 MAA（隐藏）”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:638`，当前阶段未接该 GUI/历史事件 |
| `MosquitoLeg` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RealGacha` | 依赖未交付 | 需 Mac 可确认的“真正的抽卡”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:641`，当前阶段未接该 GUI/历史事件 |
| `PeekScreen` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `CustomizationMaster` | 平台不适用 | 依赖 WPF 专属窗口、主题、通知、代理或彩蛋交互；Mac 无等价产品契约 |
| `LogSupervisor` | 依赖未交付 | 需 LogView 持续可见时长事件，不用点击查看替代 |
| `TaskChainKing` | 依赖未交付 | 需 Mac 可确认的“任务链王”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:646`，当前阶段未接该 GUI/历史事件 |
| `HotkeyMagician` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `WarehouseMiser` | 依赖未交付 | 需完整仓库成功与范围适配 C7，当前基础仓库 UI 不建立可信完整快照 |
| `HrSpecialist` | 依赖未交付 | 需 Mac 可确认的“人事部专员”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:650`，当前阶段未接该 GUI/历史事件 |
| `HrSeniorSpecialist` | 依赖未交付 | 需 Mac 可确认的“人事部高级专员”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:651`，当前阶段未接该 GUI/历史事件 |
| `NotFound404` | 依赖未交付 | 需 Mac 可确认的“404！”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:653`，当前阶段未接该 GUI/历史事件 |
| `Linguist` | 依赖未交付 | 需可确认语言切换完成事件，当前 Mac 使用系统语言 |
| `StartupBoot` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SortingMaster` | 依赖未交付 | 需 Mac 可确认的“排序大师”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:657`，当前阶段未接该 GUI/历史事件 |
| `AchievementObserver` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `DisappearTrick` | 平台不适用 | 依赖 WPF 专属窗口、主题、通知、代理或彩蛋交互；Mac 无等价产品契约 |
| `TitleTweaker` | 平台不适用 | 依赖 WPF 专属窗口、主题、通知、代理或彩蛋交互；Mac 无等价产品契约 |
| `AllChannelBroadcast` | 平台不适用 | 依赖 WPF 专属窗口、主题、通知、代理或彩蛋交互；Mac 无等价产品契约 |
| `ConnectionTester` | 依赖未交付 | 需 Mac 可确认的“连接测试员”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:662`，当前阶段未接该 GUI/历史事件 |
| `MasterDirector` | 依赖未交付 | 需 Mac 可确认的“总导演”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:663`，当前阶段未接该 GUI/历史事件 |
| `PrivateDormManager` | 依赖未交付 | 需 Mac 可确认的“私人宿管”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:664`，当前阶段未接该 GUI/历史事件 |
| `OperatorRoster` | 依赖未交付 | 需 Mac 可确认的“花名册”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:665`，当前阶段未接该 GUI/历史事件 |
| `UseCopilot1` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `UseCopilot2` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `UseCopilot3` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `CopilotLikeGiven1` | 依赖未交付 | 需 Mac 可确认的“点赞 1 次”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:673`，当前阶段未接该 GUI/历史事件 |
| `CopilotLikeGiven2` | 依赖未交付 | 需 Mac 可确认的“点赞 10 次”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:674`，当前阶段未接该 GUI/历史事件 |
| `CopilotLikeGiven3` | 依赖未交付 | 需 Mac 可确认的“点赞 50 次”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:675`，当前阶段未接该 GUI/历史事件 |
| `CopilotError` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `MapOutdated` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `Irreplaceable` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SnapshotChallenge1` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SnapshotChallenge2` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SnapshotChallenge3` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SnapshotChallenge4` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SnapshotChallenge5` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `SnapshotChallenge6` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `QuickCloser` | 依赖未交付 | 依赖统一提示框展示/关闭时间事件，以确认 1 秒内关闭；WPF MessageBoxHelper.cs:146–150 |
| `TacticalRetreat` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `Martian` | 依赖未交付 | 需 Mac 可确认的“90 天没更新”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:692`，当前阶段未接该 GUI/历史事件 |
| `AnnouncementStubbornClick` | 依赖未交付 | 需 Mac 可确认的“不看公告”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:693`，当前阶段未接该 GUI/历史事件 |
| `RecruitNoSixStar` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `RecruitNoSixStarStreak` | 已实现 | AchievementEventAdapter / AchievementStore；E1 断言，真实长期累计待验 |
| `Time325` | 依赖未交付 | 需 Mac 可确认的“325”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:698`，当前阶段未接该 GUI/历史事件 |
| `CongratulationError` | 依赖未交付 | 需 Mac 可确认的“喜报”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:702`，当前阶段未接该 GUI/历史事件 |
| `UnexpectedCrash` | 依赖未交付 | 需 Mac 可确认的“不速之客”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:703`，当前阶段未接该 GUI/历史事件 |
| `ProblemFeedback` | 依赖未交付 | 需 Mac 可确认的“问题反馈”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:704`，当前阶段未接该 GUI/历史事件 |
| `CdnTorture` | 依赖未交付 | 需 Mac 可确认的“下载资源失败超过3次”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:705`，当前阶段未接该 GUI/历史事件 |
| `BackstageExplorer` | 依赖未交付 | 需 Mac 可确认的“走进后台”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:706`，当前阶段未接该 GUI/历史事件 |
| `MissionStartCount` | 依赖未交付 | 需 Mac 可确认的“一天内开始任务超过 3 次”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:710`，当前阶段未接该 GUI/历史事件 |
| `LongTaskTimeout` | 依赖未交付 | 依赖 #132 超时策略最终接口 |
| `ProxyOnline3Hours` | 依赖未交付 | 依赖 DailyRunCoordinator 实际连续运行超过 3 小时的计时事件；WPF RunningState.cs:209–222 的代理指任务运行，并非网络代理 |
| `TaskStartCancel` | 依赖未交付 | 需 Mac 可确认的“在开始任务后马上又停止”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:713`，当前阶段未接该 GUI/历史事件 |
| `AfkWatcher` | 依赖未交付 | 依赖 Mac NSWindow 最小化/恢复及连续 1 小时可观察时长事件；WPF MainWindowManager.cs:120–139，不是平台排除项 |
| `UseDaily1` | 依赖未交付 | 需 Mac 可确认的“连续使用时间”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:716`，当前阶段未接该 GUI/历史事件 |
| `UseDaily2` | 依赖未交付 | 需 Mac 可确认的“UseDaily2”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:717`，当前阶段未接该 GUI/历史事件 |
| `UseDaily3` | 依赖未交付 | 需 Mac 可确认的“UseDaily3”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:718`，当前阶段未接该 GUI/历史事件 |
| `UpdateObsession` | 依赖未交付 | 需 Mac 可确认的“更新强迫症”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:720`，当前阶段未接该 GUI/历史事件 |
| `UpdateEarlyBird` | 依赖未交付 | 需 Mac 可确认的“更新尝鲜者”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:721`，当前阶段未接该 GUI/历史事件 |
| `ChangelogReader` | 依赖未交付 | 需 Sparkle 更新说明成功展示事件 |
| `LatestVersionInspector` | 依赖未交付 | 需 Sparkle 明确已是最新版本结果事件 |
| `TimeMachine` | 依赖未交付 | 需版本降级确认和历史版本存储 |
| `LoadLastSave` | 依赖未交付 | 需用户显式进度恢复与备份选择流程 |
| `Rules` | 平台不适用 | 依赖 WPF 专属窗口、主题、通知、代理或彩蛋交互；Mac 无等价产品契约 |
| `VersionClick` | 平台不适用 | 依赖 WPF 专属窗口、主题、通知、代理或彩蛋交互；Mac 无等价产品契约 |
| `AprilFools` | 依赖未交付 | 需 Mac 可确认的“愚人节”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:732`，当前阶段未接该 GUI/历史事件 |
| `MidnightLaunch` | 依赖未交付 | 需 Mac 可确认的“0~4 点”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:733`，当前阶段未接该 GUI/历史事件 |
| `LunarNewYear` | 依赖未交付 | 需 Mac 可确认的“春节”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:734`，当前阶段未接该 GUI/历史事件 |
| `Lucky` | 依赖未交付 | 需 Mac 可确认的“启动 MAA 时有极小概率触发”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:736`，当前阶段未接该 GUI/历史事件 |
| `SanityPlanner` | 依赖未交付 | 需 Mac 可确认的“理智规划师”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:738`，当前阶段未接该 GUI/历史事件 |
| `WarehouseKeeper` | 依赖未交付 | 依赖 C7 的可信完整仓库快照与其总量单位 |
| `PallasStarter` | 依赖未交付 | 依赖 Roguelike core_char 的规范 pallas 身份解析及任务追加成功事件；WPF RoguelikeTaskUserControlModel.cs:1719/1818，Mac 已有开局干员入口 |
| `PallasCheers` | 平台不适用 | 依赖 WPF 专属窗口、主题、通知、代理或彩蛋交互；Mac 无等价产品契约 |
| `OneMoreLook` | 依赖未交付 | 需 Mac 可确认的“再看一眼”事件及对应跨启动状态；固定定义入口 `AchievementTrackerHelper.cs:742`，当前阶段未接该 GUI/历史事件 |
| `SlackingOff` | 依赖未交付 | 依赖 miniGame(name:) 的成功提交事件；WPF ToolboxViewModel.cs:3583，Mac 已有小游戏入口 |
