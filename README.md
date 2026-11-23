# MAA Mac GUI

MAA 的意思是 MAA Assistant Arknights

一款明日方舟游戏小助手

本 Repo 为 MAA 的 Mac GUI 仓库，是 MAA 主仓库的 submodule。 更多关于 MAA 的信息请参考 [MAA Assistant Arknights 主仓库](https://github.com/MaaAssistantArknights/MaaAssistantArknights)。

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

## 腾讯应用宝 Mac 连接

需要包含 `AndrowsMac` 配置的 MaaCore 资源，旧资源会显示更新提示。

1. 先在应用宝中启动明日方舟，确认 ADB 设备在线。
2. 在 MAA 的游戏设置中选择客户端，在连接设置中选择 ｢腾讯应用宝 Mac｣，填写 ADB 设备地址。
3. 此配置使用 ADB 触控，关闭 adb-lite，并允许 Gzip 截图；连接时按客户端包名自动查询游戏 display。
4. 游戏关闭、重开后需要重新连接，以获取新的 display 编号。无需固定 display 或修改缓存资源。

默认的 ｢通用 / PlayCover｣ 配置保留原有连接行为。
