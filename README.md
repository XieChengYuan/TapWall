# TapWall

让 Mac 桌面图标立体掉落、碰撞堆叠，再按视频时间归位。

原生 macOS 应用，Swift + SceneKit。读取真实文件和应用图标，双击打开原项目，不移动文件、不修改 Finder 布局。不绘制地面或底板。

## 案例视频

[![点击播放默认案例视频](docs/images/example-preview.jpg)](Assets/Examples/default-wallpaper.mp4)

[▶ 播放默认案例视频](Assets/Examples/default-wallpaper.mp4)

应用已内置同一视频，打开即可预览，点击「应用」开始运行。

## 控制台

![TapWall 控制台](docs/images/console.png)

默认设置：桌面与应用、方阵靠左、震落、依次归位，循环且静音。

| 动作 | 开始 | 结束 |
| --- | --- | --- |
| 掉落 | 2.35 秒 | 3.32 秒 |
| 归位 | 4.84 秒 | 5.94 秒 |

## 运行

需要 macOS 13+ 和 Xcode Command Line Tools：

```sh
xcode-select --install # 已安装可跳过

git clone https://github.com/XieChengYuan/TapWall.git
cd TapWall
bash run.sh
```

首次构建后安装到 `~/Applications/TapWall.app`，之后直接双击打开。无需第三方依赖、API Key 或联网服务。本机临时签名，未做 Apple 公证。

## 使用

1. 选择图标来源、横排／竖排／方阵及靠左／靠右。
2. 选择掉落和归位方式，点击按钮预演。
3. 使用内置案例或导入本地视频。蓝色区间设置掉落开始与结束，绿色区间设置归位开始与结束。
4. 拖动区间两端调整时长，拖动色块整体移动；也可输入秒数或设为当前帧。
5. 预览确认后点击「应用」，壁纸从头独立播放。之后修改设置，再点「应用更改」。

**短区间加速、长区间放慢，完整动作不会被截断。** 控制台的播放、暂停、拖动及更换视频只影响预览，不会改变已应用的壁纸。时间区间、动作、排列、循环和声音设置均在点击「应用」时生效。

空格掉落，`R` 归位，`D` 切换桌面模式，`Esc` 返回窗口。快捷键在舞台获得焦点时生效。菜单栏可重新打开控制台，`Cmd+Q` 退出。

桌面或所选文件夹中新建、删除、重命名文件会自动同步到图标层，无需重新应用；已应用的视频和动作设置保持不变。

窗口通过顶部标题栏移动。双击图标打开文件，右键在 Finder 显示；拖动图标可调整位置，视频播放时位置由时间轴控制。

## 开发

```sh
bash build.sh
bash test.sh # 需要已登录的 macOS 图形桌面
```

构建输出可用 `TAPWALL_APP_PATH=/绝对路径/TapWall.app` 指定。默认针对当前 Mac 架构构建；当前已在 Apple Silicon 上验证。

- `Sources/SpatialIcons.swift`：3D 材质、碰撞轨迹与时长映射。
- `Sources/VideoSession.swift`：视频、预览、时间区间。
- `Sources/Console.swift`：控制台与区间编辑。
- `Sources/main.swift`：窗口、图标来源、桌面模式。

## 当前限制

最多显示 32 个图标，主要面向单屏。修改图标来源、排列、掉落方式或窗口尺寸时，需要短暂重新计算物理轨迹。自选视频和时间区间尚不跨重启保存；每次启动载入内置案例及上述预设。不自动识别视频动作，也不支持人物抓取图标。

## License

[MIT](LICENSE)。文件与应用图标在使用者本机读取，相关图标权利归原权利人；仓库不附带这些第三方应用图标。TapWall 应用图标由 AI 生成。内置案例视频与控制台截图由项目维护者提供。
