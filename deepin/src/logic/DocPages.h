// DocPages.h — 固定文档页的内容（关于 / 帮助 / 开源感谢 / 更新日志）。
//
// 【这些内容是「写死的」】mac 的 `DocsPages.swift` 把四类长文写进源码
// （每类四种语言），理由是「固定内容写在代码里（跨平台一致）」—— 文档不是数据、
// 不随仓库变、不需要引擎供数。deepin 同样写死，不去引擎取。
//
// 【但事实必须按平台写对】mac 的「关于」写的是「客户端（deepDolphin, Swift, AI 层）」、
// 「v0.1.0 — macOS ARM64 首发版」；deepin 对应的是「Qt 6 + DDE / DTK」与 deepin / UOS 桌面。
// 直接抄 mac 的文案会**说错平台**（用户看到的「关于」页把本客户端说成另一个平台的）——
// 所以这里按 deepin 的事实另写一份：**类目结构与 mac 一致，事实各平台各写**。
//
// 【多语言位已填（批 AA）】批 G 留的接口位（`Language` 参数）在本批填上：
//   `Language` 从「只有 zhCN」扩到 **zhCN / en / zhTW / ja**（与 mac 的 `AppLanguage`
//   一一对齐），四类文档各四种语言的正文**全部给全**。
//   ⚠ mac 的 zhTW / ja 译文本身是**残缺的**（比 zhCN 少好几节）⇒ 本批不抄它，
//     按 deepin 的中文底本逐篇写全，事实按 deepin 写对（Qt 6 + DDE / DTK）。
//   ⚠ 本批只覆盖**固定文档页**这一个模块：全应用 i18n（1000+ 条界面串）仍待做
//     （台账 B8）—— 但 Qt 的 `tr()` 找不到译文会**回落成中文**⇒ 半吊子本地化会
//     **中英混杂**，比不做更糟 ⇒ 宁可整块做一块，不做半块。
#pragma once
#include <QString>
#include <QVector>

#include <optional>

namespace DocPages {

/// 文档类目（与 mac 的 `DocPageKind` 一一对应）。
enum class Kind { about, help, openSource, changelog };

/// 文档语言（与 mac 的 `AppLanguage` 对齐）。
///
/// ⚠ **顺序即展示顺序**（UI 的语言选择器按这个顺序排）—— 与 mac 的
///   `AppLanguage: String, CaseIterable` 同一口径。
enum class Language { zhCN, en, zhTW, ja };

/// 文档类目的稳定标识（判据/存档用，不随显示名或文案改）。
QString kindKey(Kind k);

/// 全部类目（UI 排序用；**单一真相源** —— 新增类目只改这一处）。
QVector<Kind> kinds();

/// 全部语言（UI 排序用；**单一真相源** —— 新增语言只改这一处）。
QVector<Language> languages();

/// 语言的稳定标识（持久化用；「zh-CN」/「en」/「zh-TW」/「ja」）。
///
/// ⚠ 用**语言标签**（BCP 47 风格）而不是枚举名 —— 持久化值将来要能被别的工具读。
QString languageKey(Language lang);

/// 解析持久化里的语言标识。
///
/// ⚠ **认不出 ⇒ `std::nullopt`**（不猜、不回落成 zhCN）：
///   回落会让「拼错的值」静默变成「简体中文」，用户改了设置却看不到变化。
///   调用方自己决定回落策略（客户端的落点是「回落到默认语言 + 说一句」）。
std::optional<Language> languageFromKey(const QString &key);

/// 语言的显示名（语言选择器里那一项；**自指** —— 简体中文那项显示「简体中文」）。
QString languageLabel(Language lang);

/// 持久化值的解析结果（落地方案：**认不出的存值怎么办**）。
///
/// ⚠ 「存的值认不出」与「还没存过」是**两回事**：
///   · 空串 = 还没选过 ⇒ 用默认语言，**不算**出错，不提示；
///   · 非空但认不出 = 存的值坏了（手改过配置 / 换了版本）⇒ 回落 + **说一句**。
struct LanguageResolution {
    Language language = Language::zhCN; ///< 实际生效的语言
    bool recovered = false;             ///< true = 存的键认不出，已回落到 fallback
};

/// 把持久化值解析成可用的语言（**纯函数** —— 判定层不碰 Settings）。
///
/// ⚠ 回落策略在这一层**定死**（回落 + 标记 recovered），但**不说那句提示**
///   —— 提示是 UI 的事（判定层只出「结果」，不产出会话内的副作用）。
LanguageResolution resolveLanguage(const QString &key, Language fallback = Language::zhCN);

/// 类目的显示名（UI 切换按钮用；按语言取）。
QString kindTitle(Kind k, Language lang = Language::zhCN);

/// 某类目某语言的正文（markdown）。
///
/// ⚠ 认不出的类目/语言 → 返回**空串**，不回落成「关于」的正文：
///   回落的话，加错了类目会静默显示一段「看着像那么回事」的关于页，
///   用户根本分不清自己看的是哪一篇。
QString content(Kind k, Language lang = Language::zhCN);

/// 窗口标题（「deepDolphin 文档」）。
QString windowTitle(Language lang);

/// 关闭按钮文字。
QString closeLabel(Language lang);

/// 「查看客户端仓库」按钮文字。
QString repoLabel(Language lang);

/// 底部出处说明（**传进去的仓库地址原样带上**）。
///
/// ⚠ 约定：这三个提示函数**入参给值、出口即成品**（不留 `%1` 给调用方填）。
///   留半成品模板出去 ⇒ 调用方忘了 `.arg` 就把「%1」原样显示给用户。
QString engineRepoHint(Language lang, const QString &engineRepoUrl);

/// 正文读不到时的说明（**带上类目标识**）。
QString unavailableText(Kind k, Language lang);

/// 语言设置认不出时的提示（**带上存下来的原值**）。
QString recoveredNotice(const QString &badKey, Language lang);

/// 引擎仓库地址（关于页/致谢页共用一个出处 —— 不许各写一份）。
QString engineRepo();

/// 客户端仓库地址。
QString clientRepo();

} // namespace DocPages
