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
// 【多语言位先留空】mac 有 zhCN / en / zhTW / ja 四语言；deepin 的 i18n 还没接
// （台账 B8 未开始），故本层先只给简体中文，接口按 `Language` 参数留好位 ——
// 接 i18n 时只加数据、不动结构。
#pragma once
#include <QString>
#include <QVector>

namespace DocPages {

/// 文档类目（与 mac 的 `DocPageKind` 一一对应）。
enum class Kind { about, help, openSource, changelog };

/// 文档语言（与 mac 的 `AppLanguage` 对齐；deepin 目前只用简体中文）。
enum class Language { zhCN };

/// 类目的稳定标识（判据/存档用，不随显示名或文案改）。
QString kindKey(Kind k);

/// 类目的显示名（UI 切换按钮用）。
QString kindTitle(Kind k, Language lang = Language::zhCN);

/// 全部类目（UI 排序用；**单一真相源** —— 新增类目只改这一处）。
QVector<Kind> kinds();

/// 某类目某语言的正文（markdown）。
///
/// ⚠ 认不出的类目/语言 → 返回**空串**，不回落成「关于」的正文：
///   回落的话，加错了类目会静默显示一段「看着像那么回事」的关于页，
///   用户根本分不清自己看的是哪一篇。
QString content(Kind k, Language lang = Language::zhCN);

/// 引擎仓库地址（关于页/致谢页共用一个出处 —— 不许各写一份）。
QString engineRepo();

/// 客户端仓库地址。
QString clientRepo();

} // namespace DocPages
