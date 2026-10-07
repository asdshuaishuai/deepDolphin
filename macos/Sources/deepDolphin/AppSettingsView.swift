// AppSettingsView.swift — 完整设置面板（SwiftUI Settings scene 的 content）。
// Tab 结构：通用 / AI 配置 / 关于 / 帮助 / 开源感谢 / 更新日志
import SwiftUI

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
            AboutTab()
                .tabItem { Label(l10n.tabAbout, systemImage: "info.circle") }
            HelpTab()
                .tabItem { Label(l10n.tabHelp, systemImage: "questionmark.circle") }
            OpenSourceTab()
                .tabItem { Label(l10n.tabOpenSource, systemImage: "heart") }
            ChangelogTab()
                .tabItem { Label(l10n.tabChangelog, systemImage: "list.bullet") }
        }
        .frame(width: 580, height: 520)
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

struct AboutTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView { MarkdownView(text: l10n.doc(.about)).padding(16) }
    }
}

struct HelpTab: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView { MarkdownView(text: l10n.doc(.help)).padding(16) }
    }
}

struct OpenSourceTab: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView { MarkdownView(text: l10n.doc(.openSource)).padding(16) }
    }
}

struct ChangelogTab: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView { MarkdownView(text: l10n.doc(.changelog)).padding(16) }
    }
}
