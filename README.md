# MAA Mac GUI

MAA 的意思是 MAA Assistant Arknights

一款明日方舟游戏小助手

本 Repo 为 MAA 的 Mac GUI 仓库，是 MAA 主仓库的 submodule。 更多关于 MAA 的信息请参考 [MAA Assistant Arknights 主仓库](https://github.com/MaaAssistantArknights/MaaAssistantArknights)。

## 开发

### clone 代码
1. clone [主仓库](https://github.com/MaaAssistantArknights/MaaAssistantArknights)
2. 初始化 submodule `git submodule update --init --recursive`

### Build MAA Core
> 这部分内容可能过时，请参考 workflow 定义中与 macOS-GUI 相关的内容, 其中一部分步骤与 CPU 架构有关

#### Intel Mac
1. 安装依赖 `brew install ninja`
2. 下载预构建的第三方库 `python3 maadeps-download.py x64-osx`
3. `mkdir -p build && cmake -B build -GNinja -DCMAKE_OSX_ARCHITECTURES="x86_64"`

#### Apple Silicon Mac
1. 安装依赖 `brew install ninja`
2. 下载预构建的第三方库 `python3 maadeps-download.py arm64-osx`
3. `mkdir -p build && cmake -B build -GNinja -DCMAKE_OSX_ARCHITECTURES="arm64"`

### 以下与架构无关
4. `cmake --build build`
5. `cmake --install build --prefix build`
6. `cd build`
7. ```
   xcodebuild -create-xcframework -library   libMaaCore.dylib -headers ../include -output   MaaCore.xcframework
   xcodebuild -create-xcframework -library   libMaaDerpLearning.dylib -output   MaaDerpLearning.xcframework
   xcodebuild -create-xcframework -library   libonnxruntime.*.dylib -output ONNXRuntime   xcframework
   xcodebuild -create-xcframework -library libopencv*.dylib -output OpenCV.xcframework
   ```

🎉 打开 Xcode 可以尝试 build 了

### Q&A

1. 无法获取签名怎么办？
    - 开发时可以在本地更换为个人开发者签名， 但是提交代码时请不要提交这部分修改
2. 各种依赖下载失败/超时？
    - 科学上网

