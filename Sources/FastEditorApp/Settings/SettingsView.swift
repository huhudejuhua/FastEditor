import SwiftUI

/// 设置窗口内容：展示 + 录制两个全局热键。
///
/// 观察 `HotKeySettings.shared`（ObservableObject 桥）：用户改键后这里自动刷新显示。
/// 录制走 `HotKeyRecorder`；抓到合法组合后在 `apply` 里做「语义校验（与另一槽位冲突）→
/// 写入设置 → 调 AppDelegate 重注册」三步。
struct SettingsView: View {
    @ObservedObject var settings: HotKeySettings
    @StateObject private var recorder = HotKeyRecorder()

    /// 注册失败（组合被占用）时的横幅提示。
    @State private var registerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("快捷键")
                .font(.headline)
                .padding(.bottom, 4)
            Text("全局热键，在任意应用里都能触发。点右侧按钮后按下新组合键，Esc 取消。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)

            hotKeyRow(slot: .editor, title: "打开编辑器", subtitle: "抓取焦点文本并呼出编辑器",
                      config: settings.editor)
            Divider().padding(.vertical, 10)
            hotKeyRow(slot: .history, title: "历史记录", subtitle: "呼出历史浮窗检索 / 复用",
                      config: settings.history)

            // 录制中的提示（如缺修饰键）/ 注册失败横幅。
            if let hint = recorder.hint {
                Text(hint).font(.caption).foregroundColor(.orange).padding(.top, 10)
            } else if let err = registerError {
                Text(err).font(.caption).foregroundColor(.red).padding(.top, 10)
            }

            Spacer()

            HStack {
                Spacer()
                Button("恢复默认") {
                    settings.resetToDefaults()
                    applyRegistration()
                }
            }
        }
        .padding(20)
        .frame(width: 420, height: 280)
        .onAppear {
            recorder.onCapture = { slot, cfg in apply(slot, cfg) }
        }
        .onDisappear {
            recorder.stop()
        }
    }

    private func hotKeyRow(slot: HotKeySlot, title: String, subtitle: String,
                           config: HotKeyConfig) -> some View {
        let isRecording = recorder.recording == slot
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                if isRecording { recorder.stop() } else {
                    registerError = nil
                    recorder.start(slot)
                }
            } label: {
                Text(isRecording ? "按下组合键…" : config.displayString)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundColor(isRecording ? .accentColor : .primary)
                    .frame(minWidth: 90)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                    lineWidth: isRecording ? 2 : 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 抓到组合后的处理

    private func apply(_ slot: HotKeySlot, _ cfg: HotKeyConfig) {
        // 语义校验：不能跟另一个槽位撞键。
        let other = (slot == .editor) ? settings.history : settings.editor
        if cfg == other {
            recorder.hint = "和另一个快捷键冲突了，换一个组合"
            // 停在错误态，用户可再点录制重试。
            return
        }

        switch slot {
        case .editor:  settings.editor = cfg
        case .history: settings.history = cfg
        }
        applyRegistration()
    }

    /// 调 AppDelegate 重注册，注册失败（组合被系统/别的 App 占用）时给横幅。
    private func applyRegistration() {
        recorder.hint = nil
        let ok = AppDelegate.shared?.reregisterHotKeys() ?? false
        registerError = ok ? nil : "有热键注册失败，可能被系统或别的 App 占用，换一个组合试试。"
    }
}
