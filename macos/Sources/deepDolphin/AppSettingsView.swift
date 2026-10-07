// AppSettingsView.swift — 完整设置面板（SwiftUI Settings scene 的 content）。
// Tab 结构：通用 / AI 配置 / 自动化 / 关于（含帮助/开源/日志）
import SwiftUI
import AppKit

struct AppSettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared
    @State private var aiDraft = AIConfig.load()

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label(l10n.tabGeneral, systemImage: "gear") }
            AISettingsPane(draft: $aiDraft)
                .tabItem { Label(l10n.tabAI, systemImage: "sparkles") }
            ScheduleCard().environmentObject(AppModel.shared)
                .tabItem { Label(l10n.tabAutomation, systemImage: "clock") }
            AboutCombinedTab()
                .tabItem { Label(l10n.tabAbout, systemImage: "info.circle") }
        }
        .frame(width: 620, height: 560)
        .onDisappear { aiDraft.save() }
    }
}

// MARK: - Tab 内容

struct GeneralTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Form {
            Section(L10n.t("settings.language")) {
                Picker(L10n.t("settings.language"), selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
            }
            Section(L10n.t("settings.autostart")) {
                if #available(macOS 13.0, *) {
                    Toggle(L10n.t("settings.autostartToggle"), isOn: Binding(
                        get: { LoginItem.shared.isEnabled },
                        set: { LoginItem.shared.setEnabled($0) }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// 关于页（合并 About + Help + OpenSource + Changelog）。
/// 顶部是与仪表盘 hero 同源的渐变封面（图标 + 名字 + 一句话）——
/// 四段文档（关于/帮助/开源/日志）跟在封面下面滚动。
struct AboutCombinedTab: View {
    @ObservedObject private var l10n = L10n.shared

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                VStack(spacing: DSSpacing.sm) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    Text("deepDolphin")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text(L10n.t("about.tagline"))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("v\(version) · \(L10n.t("about.engineLine")) moonGit Engine")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.xxl)
                .background {
                    ZStack {
                        DSGradient.hero
                        Circle()
                            .fill(.white.opacity(0.07))
                            .frame(width: 150, height: 150)
                            .offset(x: 120, y: -90)
                    }
                }
                .clipShape(DSRect.shape(DSRadius.card))

                docSection(l10n.doc(.about))
                Divider()
                docSection(l10n.doc(.help))
                Divider()
                docSection(l10n.doc(.openSource))
                Divider()
                docSection(l10n.doc(.changelog))
            }
            .padding(DSSpacing.lg)
        }
    }

    private func docSection(_ text: String) -> some View {
        MarkdownView(text: text)
    }
}
