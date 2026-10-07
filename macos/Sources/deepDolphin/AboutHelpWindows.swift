// AboutHelpWindows.swift — 原生菜单栏「关于 / 帮助」打开的独立窗口。
//
// 为什么不是标准 About 面板：`orderFrontStandardAboutPanel` 只能显示
// Info.plist 里的版本号与 credits 纯文本，而关于页要同时交代
// 「这是谁 · 引擎是什么 · 仓库在哪」——这三件事在标准面板里放不下。
// 窗口本身仍是标准 Window 场景（可拖动 / 可关闭 / 出现在窗口菜单），
// 只是把内容换成了产品封面。帮助窗口与设置面板的「帮助」Tab
// 共用同一份 `L10n.shared.doc(.help)` —— 两处内容必须同源。
import SwiftUI
import AppKit

// MARK: - 关于窗口

struct AboutWindowView: View {
    @ObservedObject private var l10n = L10n.shared

    /// 版本号取 Info.plist（build.sh 写入 0.1.0）；取不到时宁可显示占位
    /// 也不崩 —— 关于窗口崩溃是最难看的崩溃。
    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── 封面：与仪表盘 hero 同一张渐变底（DSGradient.hero 唯一出处）──
            VStack(spacing: DSSpacing.sm) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                Text("deepDolphin")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(L10n.t("about.tagline"))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DSSpacing.xxl)
            .padding(.bottom, DSSpacing.xl)
            .padding(.horizontal, DSSpacing.xl)
            .background {
                ZStack {
                    DSGradient.hero
                    Circle()
                        .fill(.white.opacity(0.07))
                        .frame(width: 180, height: 180)
                        .offset(x: 130, y: -110)
                }
                .ignoresSafeArea()
            }

            // ── 事实区：版本 + 引擎 + 仓库 ──
            VStack(spacing: DSSpacing.md) {
                HStack(spacing: DSSpacing.xs) {
                    Text("v\(version)")
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(L10n.t("about.engineLine")) moonGit Engine · Cangjie")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: DSSpacing.sm) {
                    Link(destination: URL(string: "https://github.com/asdshuaishuai/deepDolphin")!) {
                        Label("deepDolphin · \(L10n.t("about.viewRepo"))", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    Link(destination: URL(string: "https://github.com/asdshuaishuai/moongit")!) {
                        Label("moonGit", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.bordered)
                }
                .buttonStyle(.bordered)
            }
            .padding(DSSpacing.xl)
        }
        .frame(width: 400)
    }
}

// MARK: - 帮助窗口

struct HelpWindowView: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            MarkdownView(text: l10n.doc(.help))
                .padding(DSSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 520)
        .navigationTitle(L10n.t("menu.help"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Link(destination: URL(string: "https://github.com/asdshuaishuai/deepDolphin")!) {
                    Label(L10n.t("menu.github"), systemImage: "link")
                }
            }
        }
    }
}
