# MAA Mac GUI

MAA 的意思是 MAA Assistant Arknights

一款明日方舟游戏小助手

本 Repo 为 MAA 的 Mac GUI 仓库，是 MAA 主仓库的 submodule。 更多关于 MAA 的信息请参考 [MAA Assistant Arknights 主仓库](https://github.com/MaaAssistantArknights/MaaAssistantArknights)。

## 自定义基建时间轮换

在基建设置中选择“自定义基建配置”和排班文件。文件中任一班次包含非空 `period` 时，班次列表提供“时间轮换（当前班次）”；选择文件时默认启用时间轮换，没有时段则默认第一班。已有配置中保存的具体班次不会自动改成时间轮换。

时间轮换与 Windows 一致：手动启动和定时启动均在提交任务时按电脑本地时间选班，同一班次任一时段匹配即可，多个班次重叠时选文件中靠前的一班。提交后，界面的时间预览更新不改变本次执行班次。时间轮换完成后不递增班次；手动选择具体班次则在基建完成后顺序推进，末班回到第一班。

`period` 的起止点都包含在区间内，但结束分钟不会扩展为整分钟，例如 `13:59:00` 匹配结束时间 `13:59`，`13:59:30` 已不匹配。跨午夜需要拆成两段，例如 `[["22:00", "23:59"], ["00:00", "06:00"]]`。详见[基建排班协议](https://github.com/MaaAssistantArknights/MaaAssistantArknights/blob/master-v2/docs/zh-cn/protocol/base-scheduling-schema.md)。

修改文件后点击“重新加载文件”。重载保留仍有效的选择；与 Windows 一样，失效选择会设为时间轮换状态，即使新文件已没有时段，此时下拉框可能没有对应选项。时间轮换没有匹配时段或班次列表为空时，仍向 Core 提交索引 `0` 并记录错误。解析错误会清空已加载班次；手动索引越界则报错。可重新选择文件或有效班次。任务运行期间禁止修改基建设置。

## 开发

### clone 代码
1. clone [主仓库](https://github.com/MaaAssistantArknights/MaaAssistantArknights)
2. 初始化 submodule `git submodule update --init --recursive`

### Build MAA Core
> 为方便使用，现已将编译过程写成一键脚本。在版本迭代过程中，脚本可能无法及时更新。这时请以 workflow 定义中与 macOS 相关的内容为准

1. 安装依赖 `brew install ninja`
2. 运行位于主仓库的脚本 `MAA_DEBUG=1 ./tools/build_macos_universal.zsh`

🎉 打开 Xcode 可以尝试 build 了

### Q&A

1. 无法获取签名怎么办？
    - 开发时可以在本地更换为个人开发者签名， 但是提交代码时请不要提交这部分修改
2. 各种依赖下载失败/超时？
    - 科学上网
3. 本地测试环境的 Mirror 酱 CDK 和正式版不同？
    - 此功能涉及到钥匙串访问。由于签名问题，测试环境和正式版无法通用。
