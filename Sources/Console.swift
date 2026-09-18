import AppKit
import SwiftUI
import AVFoundation

enum ConsoleAction {
    case selectWallpaper(WallpaperKind)
    case apply, scatter, restore, toggleDesktop, hide, reload, sourceChanged, chooseFolder
    case chooseVideo, clearVideo, useWallpaper
    case arrangement(IconArrangement), edge(IconEdge), dropMode(DropMode), returnMode(ReturnMode)
}

private enum Ink {
    static let text = Color(red: 0.12, green: 0.13, blue: 0.15)
    static let secondary = Color(red: 0.38, green: 0.40, blue: 0.44)
    static let background = Color(red: 0.97, green: 0.975, blue: 0.985)
    static let accent = Color(red: 0.17, green: 0.34, blue: 0.85)
    static let restore = Color(red: 0.09, green: 0.46, blue: 0.40)
    static let line = Color.black.opacity(0.08)
}

private struct ActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity).frame(height: 35)
            .foregroundStyle(primary ? .white : Ink.text)
            .background(primary ? Ink.accent : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? Color.clear : Ink.line))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
    }
}

private final class PreviewSurface: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
private struct MoviePreview: NSViewRepresentable {
    let player: AVPlayer?
    func makeNSView(context: Context) -> PreviewSurface { PreviewSurface(frame: .zero) }
    func updateNSView(_ view: PreviewSurface, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

struct ConsoleView: View {
    @ObservedObject var model: ConsoleModel
    @ObservedObject var video: VideoSession
    let action: (ConsoleAction) -> Void
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                inspector.frame(width: 260)
                Divider()
                Group {
                    if model.wallpaperKind == .video { editor } else { catEditor }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
        .frame(minWidth: 900, minHeight: 670)
        .background(Ink.background)
        .foregroundStyle(Ink.text)
        .font(.system(size: 12))
        .tint(Ink.accent)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let url = Bundle.main.url(forResource: "TapWall", withExtension: "png"), let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().frame(width: 38, height: 38).accessibilityHidden(true)
            }
            Text("TapWall").font(.system(size: 19, weight: .semibold, design: .rounded))
            Text("壁纸与互动").font(.system(size: 11)).foregroundStyle(Ink.secondary).padding(.leading, 5)
            Spacer()
            Button { action(.toggleDesktop) } label: {
                Label(model.isDesktop ? "返回窗口" : "桌面模式", systemImage: model.isDesktop ? "macwindow" : "desktopcomputer")
            }.buttonStyle(ActionStyle()).frame(width: 108)
            Button { action(.apply) } label: {
                Label(model.hasApplied ? "应用更改" : "应用", systemImage: "checkmark")
            }.buttonStyle(ActionStyle(primary: true)).frame(width: 110)
                .disabled(model.wallpaperKind == .video && (video.isLoading || video.error != nil))
                .help("将当前壁纸与设置应用到桌面，预览操作保持独立")
            Button { action(.hide) } label: { Image(systemName: "minus").frame(width: 28, height: 28) }
                .buttonStyle(.plain).foregroundStyle(Ink.secondary).help("隐藏控制台，可从菜单栏重新打开").accessibilityLabel("隐藏控制台")
        }.padding(.horizontal, 22).frame(height: 62)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                wallpaperLibrary
                Divider()
                if model.wallpaperKind == .video {
                sourceSection
                Divider()
                arrangementSection
                Divider()
                motionSection
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("预演")
                    HStack(spacing: 8) {
                        Button { action(.scatter) } label: { Label("掉落", systemImage: "arrow.down") }
                            .buttonStyle(ActionStyle(primary: true))
                        Button { action(.restore) } label: { Label("归位", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(ActionStyle())
                    }.disabled(model.count == 0)
                    Text("也可用空格掉落，R 归位。")
                        .font(.system(size: 10)).foregroundStyle(Ink.secondary)
                }
                } else if model.wallpaperKind == .cat {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("和它相处")
                        Text("把鼠标移到猫咪附近，慢慢晃动，再轻轻移开。")
                        Text("它会观察、蓄力和扑过去。安静一会儿，它就会打盹。")
                        Text("停在头顶，它会眯眼蹭你；移到窗台下，它会靠近、俯身伸爪去够。")
                        Text("桌面文件仍可正常点击。")
                    }.font(.system(size: 12)).foregroundStyle(Ink.secondary).lineSpacing(5)
                }
                Spacer(minLength: 0)
            }.padding(22)
        }.background(Color.white.opacity(0.52))
    }
    private var wallpaperLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("壁纸类型")
            ForEach(WallpaperCategory.allCases) { category in
                Button { action(.selectWallpaper(category == .video ? .video : .cat)) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: category.symbol).font(.system(size: 20, weight: .regular)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title).font(.system(size: 12, weight: .semibold))
                            Text(category.detail).font(.system(size: 10)).foregroundStyle(Ink.secondary)
                        }
                        Spacer(minLength: 0)
                        if model.wallpaperKind.category == category { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.wallpaperKind.category == category ? Ink.accent.opacity(0.08) : Color.clear)
                        .foregroundStyle(model.wallpaperKind.category == category ? Ink.accent : Ink.text)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(model.wallpaperKind.category == category ? .isSelected : [])
            }
        }
    }
    private var catEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("互动场景").font(.system(size: 12, weight: .semibold))
                Picker("选择互动场景", selection: Binding(get: { model.wallpaperKind }, set: { action(.selectWallpaper($0)) })) {
                    ForEach(WallpaperKind.interactiveScenes) { scene in
                        Text(scene.title).tag(scene)
                    }
                }.labelsHidden().frame(width: 180)
                Spacer()
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("窗边的猫").font(.system(size: 18, weight: .semibold))
                    Text("一段不着急的陪伴").font(.system(size: 12)).foregroundStyle(Ink.secondary)
                }
                Spacer()
                Text("互动壁纸").font(.system(size: 11)).foregroundStyle(Ink.secondary)
            }
            CatPreview(paused: model.catPreviewPaused)
                .frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("猫咪互动预览，将鼠标移入画面逗猫")
            HStack {
                Label("移入画面，试着逗逗它", systemImage: "cursorarrow.motionlines")
                    .font(.system(size: 12)).foregroundStyle(Ink.secondary)
                Spacer()
                Button { model.catPreviewPaused.toggle() } label: {
                    Label(model.catPreviewPaused ? "继续预览" : "暂停预览", systemImage: model.catPreviewPaused ? "play.fill" : "pause.fill")
                }.buttonStyle(.bordered)
            }
            Divider()
            Text("满意后点击“应用”。预览的暂停和切换不会影响已应用的桌面。")
                .font(.system(size: 11)).foregroundStyle(Ink.secondary)
        }.padding(24)
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
    }
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("图标")
                Spacer()
                Text("\(model.count) 个").font(.system(size: 11)).foregroundStyle(Ink.secondary)
                Button { action(.reload) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新图标").accessibilityLabel("刷新图标")
            }
            Picker("来源", selection: Binding(get: { model.source }, set: { model.source = $0; action(.sourceChanged) })) {
                Text("桌面与应用").tag(0)
                Text("仅桌面文件").tag(1)
                Text("自选文件夹").tag(2)
            }.labelsHidden().frame(maxWidth: .infinity)
            if model.source == 2 {
                Button("更换文件夹…") { action(.chooseFolder) }.buttonStyle(.link).font(.system(size: 11))
            }
        }
    }
    private var arrangementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("图标排列")
            HStack(spacing: 6) {
                ForEach(IconArrangement.allCases, id: \.self) { value in
                    Button { action(.arrangement(value)) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: value.symbol).font(.system(size: 18, weight: .light))
                            Text(value.title).font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).frame(height: 62)
                        .foregroundStyle(model.arrangement == value ? Ink.accent : Ink.secondary)
                        .background(model.arrangement == value ? Ink.accent.opacity(0.07) : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.arrangement == value ? Ink.accent.opacity(0.4) : Ink.line))
                    }.buttonStyle(.plain).accessibilityLabel("图标\(value.title)")
                        .accessibilityAddTraits(model.arrangement == value ? .isSelected : [])
                }
            }
            Picker("停靠边缘", selection: Binding(get: { model.edge }, set: { action(.edge($0)) })) {
                ForEach(IconEdge.allCases, id: \.self) { edge in Text(edge.title).tag(edge) }
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
    private var motionSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("3D 动作")
            HStack {
                Label("掉落", systemImage: "arrow.down").font(.system(size: 11)).foregroundStyle(Ink.secondary)
                Spacer()
                Picker("掉落方式", selection: Binding(get: { model.dropMode }, set: { action(.dropMode($0)) })) {
                    ForEach(DropMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                }.labelsHidden().frame(width: 116)
            }
            HStack {
                Label("归位", systemImage: "arrow.up").font(.system(size: 11)).foregroundStyle(Ink.secondary)
                Spacer()
                Picker("归位方式", selection: Binding(get: { model.returnMode }, set: { action(.returnMode($0)) })) {
                    ForEach(ReturnMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                }.labelsHidden().frame(width: 116)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("视频预览").font(.system(size: 14, weight: .semibold))
                    Text(video.name ?? "对齐画面中的动作，安排图标的进与退。")
                        .font(.system(size: 11)).foregroundStyle(Ink.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Button(video.ready ? "更换视频…" : "导入视频…") { action(.chooseVideo) }
                    .controlSize(.regular)
                Menu {
                    Button("使用当前壁纸") { action(.useWallpaper) }
                    Button("移除视频") { action(.clearVideo) }.disabled(!video.ready)
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 16)) }
                    .menuStyle(.borderlessButton).frame(width: 25).accessibilityLabel("背景选项")
            }
            preview
            transport
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("动作时间轴").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("拖动设置区间，点击应用后生效").font(.system(size: 10)).foregroundStyle(Ink.secondary)
                }
                VideoTimeline(video: video).frame(height: 130)
                HStack(spacing: 18) {
                    cueEditor(.drop)
                    cueEditor(.dropEnd)
                    cueEditor(.restore)
                    cueEditor(.restoreEnd)
                }
            }.disabled(!video.ready).opacity(video.ready ? 1 : 0.45)
            if let error = video.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
            }
        }.padding(22)
    }
    private var preview: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.075)
            if video.ready { MoviePreview(player: video.previewPlayer) }
            else {
                VStack(spacing: 12) {
                    if video.isLoading { ProgressView().controlSize(.small).colorScheme(.dark) }
                    else { Image(systemName: "play.rectangle").font(.system(size: 36, weight: .ultraLight)) }
                    Text(video.isLoading ? "正在准备视频…" : "在这里预览你的动态壁纸")
                        .font(.system(size: 12, weight: .medium))
                    if !video.isLoading {
                        Button("选择视频") { action(.chooseVideo) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }.foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.black.opacity(0.12)))
    }
    private var transport: some View {
        HStack(spacing: 14) {
            Text(timecode(video.currentTime)).font(.system(size: 11, weight: .medium, design: .monospaced))
            Text("/ " + timecode(video.duration)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.secondary)
            Spacer()
            transportButton("backward.end", "上一帧") { video.step(-1) }
            transportButton(video.isPlaying ? "pause.fill" : "play.fill", video.isPlaying ? "暂停视频" : "播放视频") { video.playPause() }
            transportButton("forward.end", "下一帧") { video.step(1) }
            Spacer()
            Button { video.loop.toggle() } label: { Image(systemName: "repeat").foregroundStyle(video.loop ? Ink.accent : Ink.secondary) }
                .buttonStyle(.plain).help("循环播放").accessibilityLabel(video.loop ? "关闭循环" : "开启循环")
            Button { video.muted.toggle() } label: { Image(systemName: video.muted ? "speaker.slash" : "speaker.wave.2") }
                .buttonStyle(.plain).help("视频声音").accessibilityLabel(video.muted ? "取消静音" : "静音")
        }.disabled(!video.ready)
    }
    private func transportButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 13)).frame(width: 20, height: 24) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    private func cueEditor(_ kind: CueKind) -> some View {
        let isDrop = kind.isDrop
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(isDrop ? Ink.accent : Ink.restore).frame(width: 6, height: 6)
                Text(kind.title).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Button("设为当前") { video.setCue(kind, to: video.currentTime) }
                    .buttonStyle(.link).font(.system(size: 10)).accessibilityLabel(kind.title + "设为当前帧")
            }
            HStack(spacing: 6) {
                TextField("秒", value: Binding(get: { video.schedule.time(kind) }, set: { video.setCue(kind, to: $0) }), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                    .accessibilityLabel(kind.title + "，秒")
                Text("秒").font(.system(size: 11)).foregroundStyle(Ink.secondary)
            }
        }.frame(maxWidth: .infinity)
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(model.isFalling ? Ink.accent : Ink.restore).frame(width: 5, height: 5)
            Text(model.status).lineLimit(1).truncationMode(.middle).help(model.status)
            Spacer()
            Text("Esc 返回窗口").fixedSize()
        }.font(.system(size: 10)).foregroundStyle(Ink.secondary)
            .padding(.horizontal, 22).frame(height: 30).background(Color.black.opacity(0.025))
    }
}

private struct VideoTimeline: View {
    @ObservedObject var video: VideoSession
    private func x(_ time: Double, _ width: CGFloat) -> CGFloat {
        12 + CGFloat(video.duration > 0 ? time / video.duration : 0) * max(1, width - 24)
    }
    private func seconds(_ location: CGFloat, _ width: CGFloat) -> Double {
        Double(min(1, max(0, (location - 12) / max(1, width - 24)))) * video.duration
    }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 1) {
                    ForEach(Array(video.thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(nsImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).clipped()
                    }
                }.frame(width: max(1, width - 24), height: 34).clipped()
                    .background(Color.black.opacity(0.08)).cornerRadius(4).offset(x: 12, y: 6)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("ranges")).onChanged { value in
                        video.seek(to: seconds(value.location.x, width))
                    })
                    .accessibilityLabel("视频播放位置")
                if video.ready {
                    range(drop: true, width: width, y: 52)
                    range(drop: false, width: width, y: 94)
                    Rectangle().fill(Ink.text.opacity(0.65)).frame(width: 1, height: 120)
                        .offset(x: x(video.currentTime, width), y: 4).allowsHitTesting(false)
                }
            }.coordinateSpace(name: "ranges")
        }
    }
    private func range(drop: Bool, width: CGFloat, y: CGFloat) -> some View {
        let start: CueKind = drop ? .drop : .restore
        let end: CueKind = drop ? .dropEnd : .restoreEnd
        let left = x(video.schedule.time(start), width)
        let right = x(video.schedule.time(end), width)
        let color = drop ? Ink.accent : Ink.restore
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.08))
                .frame(width: max(1, width - 24), height: 28).offset(x: 12, y: y)
            RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.24))
                .overlay(Text(drop ? "掉落" : "归位").font(.system(size: 10, weight: .medium)).foregroundStyle(color).lineLimit(1))
                .frame(width: max(2, right - left), height: 28).offset(x: left, y: y)
                .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                    video.moveRange(dropRange: drop, translation: Double(value.translation.width / max(1, width - 24)) * video.duration)
                }.onEnded { _ in video.endRangeDrag() })
                .accessibilityLabel(drop ? "掉落区间" : "归位区间")
            handle(start, width: width, y: y, color: color)
            handle(end, width: width, y: y, color: color)
        }
    }
    private func handle(_ kind: CueKind, width: CGFloat, y: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color)
            .overlay(Capsule().fill(.white.opacity(0.85)).frame(width: 2, height: 12))
            .frame(width: 10, height: 30).padding(.horizontal, 5)
            .contentShape(Rectangle())
            .position(x: x(video.schedule.time(kind), width), y: y + 14)
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("ranges")).onChanged { value in
                video.setCue(kind, to: seconds(value.location.x, width))
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.title)
            .accessibilityValue(timecode(video.schedule.time(kind)))
            .accessibilityAdjustableAction { direction in
                video.setCue(kind, to: video.schedule.time(kind) + (direction == .increment ? 0.05 : -0.05))
            }.help(kind.title + "：拖动调整时间")
    }
}
