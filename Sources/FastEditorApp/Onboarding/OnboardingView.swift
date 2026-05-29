import SwiftUI

/// 权限引导视图。
/// 本 Step（3）：只显示两行权限项 + 实时状态徽章（绑定 PermissionState）。
/// 后续：去授权按钮（Step 5）/ 重启按钮（Step 6）/ 完成按钮。
struct OnboardingView: View {
    @ObservedObject var state: PermissionState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FastEditor 需要两项权限")
                    .font(.title2).bold()
                Text("授权后才能读取当前焦点文本框的内容，并把编辑结果写回应用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            permissionRow(
                icon: "figure.wave.circle",
                name: "辅助功能 / Accessibility",
                why: "读取当前焦点文本框里的内容",
                granted: state.accessibilityGranted,
                authorize: PermissionManager.authorizeAccessibility)

            permissionRow(
                icon: "keyboard",
                name: "输入监控 / Input Monitoring",
                why: "模拟快捷键，把编辑结果写回应用",
                granted: state.inputMonitoringGranted,
                authorize: PermissionManager.authorizeInputMonitoring)

            // 「授权后需重启才生效」逃生口：任一项仍 ⚠️ 时给一个重启按钮。
            // 输入监控勾选后运行进程 preflight 常仍 false，需重启才认（CLAUDE.md §6）。
            if !state.allGranted {
                Divider()
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已在系统设置里勾选、但上面仍显示 ⚠️？")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("某些权限（尤其输入监控）需重启 App 才生效。")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        OnboardingWindowController.relaunchApp()
                    } label: {
                        Label("重启 App", systemImage: "arrow.clockwise")
                    }
                }
            }

            // 两项都 ✅ → 全部就绪 + 完成按钮（关窗但不退进程）。
            if state.allGranted {
                Divider()
                HStack(alignment: .center, spacing: 12) {
                    Label("全部就绪，FastEditor 可以正常工作了", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("完成") {
                        OnboardingWindowController.shared.hide()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 300)
    }

    @ViewBuilder
    private func permissionRow(icon: String, name: String, why: String,
                               granted: Bool, authorize: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(granted)
            if !granted {
                Button("去授权", action: authorize)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ granted: Bool) -> some View {
        if granted {
            Label("已授权", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline.weight(.medium))
        } else {
            Label("待授权", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline.weight(.medium))
        }
    }
}
