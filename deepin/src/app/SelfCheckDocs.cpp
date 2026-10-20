// SelfCheckDocs.cpp — `--selfcheck` 分片：**固定文档页 + 四语言 + 语法高亮**。
//
// ⚠ 为什么拆出来（批 AJ · M4a）：`SelfCheck.cpp` 原本是**一个 3800 多行的函数**
//   ⇒ 改一条判据要跟三千行代码挤在一个文件里 ⇒ 冲突面大、review 难。
//   ⇒ 按主题拆成多分片；**「记一条判据」的实现仍只有一份**
//   （在 `SelfCheckInternal.h`，inline 变量 + inline 函数）。
//
// ⚠ 拆分的验收：**判据条数不许变**（393 条）—— 接线门与 ci.sh 都盯着
//   ⇒ 搬漏一条就红（见 scripts/ci.sh 的 SC_MIN）。
#include "SelfCheckInternal.h"
#include "../logic/DocPages.h"
#include "../logic/SyntaxHighlight.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <QStringList>

#include "SelfCheckInternal.h"
#include "../logic/DocPages.h"
#include "../logic/SyntaxHighlight.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <QStringList>

using SelfCheckInternal::check;
using SelfCheckInternal::J;
using SelfCheckInternal::JO;

namespace SelfCheckInternal {

void checkDocs(QStringList &log)
{
    // ── 固定文档页（关于 / 帮助 / 开源感谢 / 更新日志）──
    // 文档是「写死在代码里」的长文，但它**会撒谎**：抄 mac 的文案就把本客户端
    // 说成 Swift/macOS 的了。所以判据盯的是「事实写对没有」，不是「有没有字」：
    //   ① 四个类目齐全、正文非空、互不相同
    //   ② 平台词写对（Qt / DDE / deepin），且**不含** mac 的平台词
    //   ③ 仓库地址只有一个出处（正文里的 URL 必须都来自 clientRepo()/engineRepo()）
    //   ④ 帮助页提到的入口必须**真的存在**（架构图 / 代码图谱 / 补丁体检）
    //   ⑤ 认不出的语言 → 空串（不回落成中文）
    {
        const QVector<DocPages::Kind> all = DocPages::kinds();
        check(log, "文档页：四个类目齐全且标识稳定（about / help / openSource / changelog）",
            all.size() == 4 && DocPages::kindKey(DocPages::Kind::about) == QStringLiteral("about")
                && DocPages::kindKey(DocPages::Kind::help) == QStringLiteral("help")
                && DocPages::kindKey(DocPages::Kind::openSource)
                    == QStringLiteral("openSource")
                && DocPages::kindKey(DocPages::Kind::changelog)
                    == QStringLiteral("changelog"));

        bool allNonEmpty = !all.isEmpty();
        QSet<QString> seen;
        bool distinct = true;
        for (const DocPages::Kind &k : all) {
            const QString text = DocPages::content(k);
            allNonEmpty = allNonEmpty && !text.trimmed().isEmpty();
            distinct = distinct && !seen.contains(text);
            seen.insert(text);
        }
        check(log, "文档页：四类正文都非空且互不相同（不是同一篇复制四份）",
            allNonEmpty && distinct);

        {
            // 显示名也必须齐全且互不相同（切换按钮不能有两个「帮助」）
            QSet<QString> titles;
            bool ok = true;
            for (const DocPages::Kind &k : all) {
                const QString t = DocPages::kindTitle(k);
                ok = ok && !t.isEmpty() && !titles.contains(t);
                titles.insert(t);
            }
            check(log, "文档页：类目显示名齐全且互不相同", ok);
        }
        {
            // ② 平台词写对：必须是 deepin 的事实，且**不许**出现 mac 的平台词
            const QString about = DocPages::content(DocPages::Kind::about);
            check(log, "文档页：关于页写的是本平台事实（Qt / DDE / deepin），不含 mac 的平台词",
                about.contains(QStringLiteral("Qt")) && about.contains(QStringLiteral("DDE"))
                    && about.contains(QStringLiteral("deepin"))
                    && !about.contains(QStringLiteral("Swift"))
                    && !about.contains(QStringLiteral("macOS")));
        }
        {
            // ③ 仓库地址单一出处：正文里出现的仓库 URL 必须都来自两个函数之一。
            //   ⚠ 正则必须**吃掉路径段**（`/tree/dev` 之类）：只在 `/` 前截断的话，
            //   「https://…/moongit/tree/dev」会被截成「https://…/moongit」→ 蒙对。
            QRegularExpression urlRe(
                QStringLiteral("https://github\\.com/asdshuaishuai/[A-Za-z0-9_./-]+"));
            bool onlyKnown = true;
            for (const DocPages::Kind &k : all) {
                const QString text = DocPages::content(k);
                auto it = urlRe.globalMatch(text);
                while (it.hasNext()) {
                    QString u = it.next().captured(0);
                    while (u.endsWith(QLatin1Char('.'))) // 句末的点不算地址的一部分
                        u.chop(1);
                    onlyKnown = onlyKnown
                        && (u == DocPages::clientRepo() || u == DocPages::engineRepo());
                }
            }
            check(log, "文档页：正文里的仓库地址只有两个出处（不许手抄第三份）",
                onlyKnown && DocPages::content(DocPages::Kind::about)
                        .contains(DocPages::engineRepo())
                    && DocPages::content(DocPages::Kind::openSource)
                        .contains(DocPages::engineRepo()));
        }
        {
            // ④ 帮助页提到的入口必须真的存在（文档不许吹牛）
            const QString help = DocPages::content(DocPages::Kind::help);
            check(log, "文档页：帮助页提到的入口都真实存在（架构图 / 代码图谱 / 补丁体检）",
                help.contains(QStringLiteral("架构图")) && help.contains(QStringLiteral("代码图谱"))
                    && help.contains(QStringLiteral("补丁体检")));
        }
        {
            // 致谢页要点名引擎与模型目录
            const QString ack = DocPages::content(DocPages::Kind::openSource);
            check(log, "文档页：致谢页点名引擎与模型目录",
                ack.contains(QStringLiteral("moongit"))
                    && ack.contains(QStringLiteral("models.dev")));
        }
        {
            // 更新日志要给出版本
            check(log, "文档页：更新日志给出版本号",
                DocPages::content(DocPages::Kind::changelog)
                    .contains(QStringLiteral("v0.1.0")));
        }
        {
            // ⑤ 认不出的语言 → 空串，不回落成中文
            const bool empty = DocPages::content(DocPages::Kind::about,
                static_cast<DocPages::Language>(99))
                                   .isEmpty();
            check(log, "文档页：认不出的语言返回空串（不回落成中文冒充）", empty);
        }
    }

    // ── 固定文档页的四语言（批 AA）──
    // 半吊子本地化的典型症状是「**中英混杂**」：一半界面是英文一半是中文，
    // 用户读到的是碎片。所以判据盯的是「每种语言都真的换了」：
    //   ① 四语言齐全、顺序固定、key 稳定（持久化值的口径不许飘）
    //   ② 认不出 ⇒ nullopt（**不许**猜）；resolveLanguage 三态
    //      （没选过 / 认得出 / 存的值坏了）
    //   ③ 16 篇正文都非空；同类目四语言**两两不同**（抓「某语言回落成中文」）
    //   ④ 英文正文**不含汉字**、日文正文**含假名**（回落成中文的直接信号）
    //   ⑤ 四语言**小节数一致**（抓「某语言残缺」——mac 的 zhTW/ja 就是这么残缺的）
    //   ⑥ 四语言都写本平台事实（Qt / DDE / deepin），都不含 mac 的平台词
    //   ⑦ 外壳文案（标题 / 按钮 / 底部说明 / 提示）四语言齐全，且**出口即成品**
    //      （提示必须真的带上那个值，不留 %1 模板给调用方填）
    {
        const QVector<DocPages::Language> langs = DocPages::languages();
        check(log, "文档页：四种语言齐全且顺序固定（zhCN / en / zhTW / ja）",
            langs.size() == 4 && langs.at(0) == DocPages::Language::zhCN
                && langs.at(1) == DocPages::Language::en
                && langs.at(2) == DocPages::Language::zhTW
                && langs.at(3) == DocPages::Language::ja);

        {
            // 持久化 key 必须稳定且互不相同（key 变了 = 老用户的设置全丢）
            QSet<QString> keys;
            bool ok = true;
            for (const DocPages::Language &l : langs) {
                const QString key = DocPages::languageKey(l);
                ok = ok && !key.isEmpty() && !keys.contains(key);
                keys.insert(key);
            }
            check(log, "文档页：语言 key 稳定且互不相同（zh-CN / en / zh-TW / ja）",
                ok && DocPages::languageKey(DocPages::Language::zhCN) == QStringLiteral("zh-CN")
                    && DocPages::languageKey(DocPages::Language::zhTW) == QStringLiteral("zh-TW")
                    && DocPages::languageKey(DocPages::Language::ja) == QStringLiteral("ja")
                    && DocPages::languageKey(DocPages::Language::en) == QStringLiteral("en"));
        }

        {
            // ② 认不出 ⇒ nullopt（**不许**猜、不许静默回落成中文）。
            //   注意大小写：持久化里写 "ZH-CN" 不算数（key 的口径是固定的那四个）。
            const bool unknown = !DocPages::languageFromKey(QStringLiteral("fr")).has_value()
                && !DocPages::languageFromKey(QStringLiteral("ZH-CN")).has_value()
                && !DocPages::languageFromKey(QStringLiteral("zh")).has_value()
                && !DocPages::languageFromKey(QString()).has_value();
            check(log, "文档页：认不出的语言标识返回 nullopt（不猜、不回落成中文）", unknown);
        }

        {
            // resolveLanguage 三态：
            //   「没选过」（空串）⇒ 默认语言 + **不算出错**；
            //   「认得出」    ⇒ 就是它 + 不算出错；
            //   「存的值坏了」⇒ 回落 + **标记**（UI 据此说一句）。
            const DocPages::LanguageResolution fresh
                = DocPages::resolveLanguage(QString());
            const DocPages::LanguageResolution known
                = DocPages::resolveLanguage(QStringLiteral("ja"));
            const DocPages::LanguageResolution broken
                = DocPages::resolveLanguage(QStringLiteral("fr"));
            check(log, "文档页：语言解析三态正确（没选过 / 认得出 / 坏值回落并标记）",
                fresh.language == DocPages::Language::zhCN && !fresh.recovered
                    && known.language == DocPages::Language::ja && !known.recovered
                    && broken.language == DocPages::Language::zhCN && broken.recovered);
        }

        {
            // ③ 16 篇正文都非空；同类目四语言两两不同。
            bool allNonEmpty = true;
            bool allDistinct = true;
            for (const DocPages::Kind &k : DocPages::kinds()) {
                QSet<QString> seen;
                for (const DocPages::Language &l : langs) {
                    const QString text = DocPages::content(k, l);
                    allNonEmpty = allNonEmpty && !text.trimmed().isEmpty();
                    allDistinct = allDistinct && !seen.contains(text);
                    seen.insert(text);
                }
            }
            check(log, "文档页：四类 × 四语言共 16 篇正文都非空", allNonEmpty);
            check(log, "文档页：同类目四语言正文两两不同（不许某语言回落成中文）", allDistinct);
        }

        {
            // ④ 回落成中文的直接信号：英文正文里不该有汉字；日文正文里该有假名。
            const QRegularExpression han(QStringLiteral("[\\x{4E00}-\\x{9FFF}]"));
            const QRegularExpression kana(QStringLiteral("[\\x{3040}-\\x{30FF}]"));
            bool enHasNoHan = true;
            bool jaHasKana = true;
            for (const DocPages::Kind &k : DocPages::kinds()) {
                enHasNoHan = enHasNoHan
                    && !DocPages::content(k, DocPages::Language::en).contains(han);
                jaHasKana = jaHasKana
                    && DocPages::content(k, DocPages::Language::ja).contains(kana);
            }
            check(log, "文档页：英文正文不含任何汉字（回落成中文会立刻露馅）", enHasNoHan);
            check(log, "文档页：日文正文都含假名（回落成中文会立刻露馅）", jaHasKana);
        }

        {
            // ⑤ 四语言小节数一致 —— mac 的 zhTW/ja 就是「比 zhCN 少几节」的残缺译文，
            //   这里钉死「四语言结构对齐」，防止新写的语言又残缺。
            bool aligned = true;
            for (const DocPages::Kind &k : DocPages::kinds()) {
                QSet<int> sections;
                for (const DocPages::Language &l : langs)
                    sections.insert(DocPages::content(k, l).count(QStringLiteral("\n### ")));
                aligned = aligned && sections.size() == 1;
            }
            check(log, "文档页：四语言小节数一致（不许某语言残缺）", aligned);
        }

        {
            // ⑥ 四语言都写本平台事实，且都不含 mac 的平台词（说错平台比说错代码更危险）。
            bool factsOk = true;
            bool noMacWords = true;
            for (const DocPages::Language &l : langs) {
                const QString about = DocPages::content(DocPages::Kind::about, l);
                factsOk = factsOk && about.contains(QStringLiteral("Qt"))
                    && about.contains(QStringLiteral("DDE"))
                    && about.contains(QStringLiteral("deepin"));
                noMacWords = noMacWords && !about.contains(QStringLiteral("Swift"))
                    && !about.contains(QStringLiteral("macOS"));
            }
            check(log, "文档页：四语言关于页都写本平台事实（Qt / DDE / deepin）", factsOk);
            check(log, "文档页：四语言关于页都不含 mac 的平台词（Swift / macOS）", noMacWords);
        }

        {
            // 类目显示名：每种语言内齐全且互不相同（切换按钮不能有两个「帮助」）。
            bool ok = true;
            for (const DocPages::Language &l : langs) {
                QSet<QString> titles;
                for (const DocPages::Kind &k : DocPages::kinds()) {
                    const QString t = DocPages::kindTitle(k, l);
                    ok = ok && !t.isEmpty() && !titles.contains(t);
                    titles.insert(t);
                }
            }
            check(log, "文档页：四语言的类目显示名都齐全且各自互不相同", ok);
            check(log, "文档页：认不出的语言返回空类目名（不回落成中文）",
                DocPages::kindTitle(DocPages::Kind::about, static_cast<DocPages::Language>(99))
                    .isEmpty());
            {
                // 英文的类目名**不许含汉字** —— 否则「英文模式」的分段按钮写着中文，
                // 正是「中英混杂」的最小形态。
                const QRegularExpression han(QStringLiteral("[\\x{4E00}-\\x{9FFF}]"));
                bool enNoHan = true;
                for (const DocPages::Kind &k : DocPages::kinds())
                    enNoHan = enNoHan
                        && !DocPages::kindTitle(k, DocPages::Language::en).contains(han);
                check(log, "文档页：英文类目名不含汉字（不许中英混杂）", enNoHan);
            }
            {
                // 语言显示名：四项**互不相同**且都非空（选择器里两个「简体中文」= 选不了）。
                QSet<QString> labels;
                bool ok = true;
                for (const DocPages::Language &l : langs) {
                    const QString t = DocPages::languageLabel(l);
                    ok = ok && !t.isEmpty() && !labels.contains(t);
                    labels.insert(t);
                }
                check(log, "文档页：四种语言的显示名齐全且互不相同（选择器不重复）", ok);
            }
            {
                // 作用域提示：四语言都非空，英文那档**不含汉字** ——
                // 它要如实告诉用户「目前只有这一窗跟着语言走」。
                const QRegularExpression han(QStringLiteral("[\\x{4E00}-\\x{9FFF}]"));
                bool allPresent = true;
                for (const DocPages::Language &l : langs)
                    allPresent = allPresent && !DocPages::languageSelectorTip(l).isEmpty();
                check(log, "文档页：语言选择器的作用域提示四语言齐全（不承诺没做到的事）",
                    allPresent);
                check(log, "文档页：英文作用域提示不含汉字",
                    !DocPages::languageSelectorTip(DocPages::Language::en).contains(han));
            }
        }

        {
            // ⑦ 外壳文案：四语言齐全 + 出口即成品（提示必须真的带上那个值）。
            const QRegularExpression han(QStringLiteral("[\\x{4E00}-\\x{9FFF}]"));
            bool allPresent = true;
            bool enNoHan = true;
            for (const DocPages::Language &l : langs) {
                allPresent = allPresent && !DocPages::windowTitle(l).isEmpty()
                    && !DocPages::closeLabel(l).isEmpty() && !DocPages::repoLabel(l).isEmpty();
                enNoHan = enNoHan && !DocPages::windowTitle(DocPages::Language::en).contains(han)
                    && !DocPages::closeLabel(DocPages::Language::en).contains(han)
                    && !DocPages::repoLabel(DocPages::Language::en).contains(han)
                    && !DocPages::engineRepoHint(DocPages::Language::en, DocPages::engineRepo())
                                .contains(han)
                    && !DocPages::recoveredNotice(QStringLiteral("fr"),
                        DocPages::Language::en)
                               .contains(han);
            }
            check(log, "文档页：四语言外壳文案齐全（标题 / 关闭 / 仓库按钮）", allPresent);
            check(log, "文档页：英文外壳文案不含汉字（不许中英混杂）", enNoHan);
            {
                // 出口即成品：三条提示**必须真的带上那个值**（留 %1 给调用方填的话，
                // 调用方忘了填就会把「%1」原样显示给用户）。
                bool carries = true;
                for (const DocPages::Language &l : langs) {
                    const QString hint = DocPages::engineRepoHint(l, DocPages::engineRepo());
                    carries = carries && !hint.isEmpty()
                        && hint.contains(DocPages::engineRepo())
                        && !hint.contains(QStringLiteral("%1"));
                }
                check(log, "文档页：底部说明带上了引擎仓库地址（不留 %1 模板）", carries);
                check(log, "文档页：坏值提示带上了认不出的原值（不留 %1 模板）",
                    DocPages::recoveredNotice(QStringLiteral("fr"), DocPages::Language::zhCN)
                        .contains(QStringLiteral("fr"))
                    && !DocPages::recoveredNotice(QStringLiteral("fr"),
                        DocPages::Language::zhCN)
                               .contains(QStringLiteral("%1")));
                check(log, "文档页：读不到提示带上了类目标识（不留 %1 模板）",
                    DocPages::unavailableText(DocPages::Kind::about, DocPages::Language::zhCN)
                        .contains(DocPages::kindKey(DocPages::Kind::about))
                    && !DocPages::unavailableText(DocPages::Kind::about,
                        DocPages::Language::zhCN)
                               .contains(QStringLiteral("%1")));
            }
        }
    }

    // ── 语法高亮（9 语言，与引擎 detectLang 对齐）──
    // 判据盯的是「分类对不对」：颜色在界面上只是「怪了点」，分类错了没人会发现。
    //   ① 九种语言齐全且顺序与引擎 detectLang 一致（少一种 = 那种语言的源码是纯色）
    //   ② 每种语言的关键词表都真能用（拿表里的词去扫，必须扫出 keyword）
    //   ③ 四类 token：整行注释 / 字符串（含闭合引号）/ 关键字 / 数字
    //   ④ 字符串里的 # 不是注释（python）
    //   ⑤ 段不重叠、不越界、按 start 升序
    {
        const QVector<QString> langs = SyntaxHighlight::languages();
        check(log, "语法高亮：九种语言齐全且顺序与引擎 detectLang 一致",
            langs.size() == 9 && langs.at(0) == QStringLiteral("swift")
                && langs.at(1) == QStringLiteral("cangjie") && langs.at(2) == QStringLiteral("ts")
                && langs.at(3) == QStringLiteral("python") && langs.at(4) == QStringLiteral("go")
                && langs.at(5) == QStringLiteral("rust") && langs.at(6) == QStringLiteral("java")
                && langs.at(7) == QStringLiteral("kotlin") && langs.at(8) == QStringLiteral("c"));

        {
            // ② 每种语言的关键词表都能用：拿表里的词去扫，必须扫出 keyword
            bool allWork = !langs.isEmpty();
            for (const QString &lang : langs) {
                const QSet<QString> kws = SyntaxHighlight::keywords(lang);
                if (kws.isEmpty()) {
                    allWork = false;
                    break;
                }
                const QString word = *kws.constBegin();
                const QVector<SyntaxHighlight::Span> sp
                    = SyntaxHighlight::highlight(word, lang);
                if (sp.size() != 1 || sp.at(0).kind != SyntaxHighlight::Kind::keyword
                    || sp.at(0).start != 0 || sp.at(0).len != word.size()) {
                    allWork = false;
                    break;
                }
            }
            check(log, "语法高亮：九种语言的关键词表都真能扫出 keyword", allWork);
        }
        {
            // 不认识的语言 → 回落仓颉（mac 同款），且明确说不支持
            check(log, "语法高亮：不认识的语言回落仓颉且被标为不支持",
                !SyntaxHighlight::supportsLanguage(QStringLiteral("brainfuck"))
                    && SyntaxHighlight::supportsLanguage(QStringLiteral("cangjie"))
                    && SyntaxHighlight::keywords(QStringLiteral("brainfuck"))
                        == SyntaxHighlight::keywords(QStringLiteral("cangjie")));
        }
        {
            // 整行注释 → 一整段 comment
            // ⚠ 期望值从字符串**算**出来，不手数长度 —— 手数的那版判据自己数错了，
            //   实现是对的、判据是红的（判据写错比实现写错更难查）。
            const QString line = QStringLiteral("   // 这是注释");
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(line, QStringLiteral("c"));
            check(log, "语法高亮：整行注释扫成一整段",
                sp.size() == 1 && sp.at(0).kind == SyntaxHighlight::Kind::comment
                    && sp.at(0).start == 0 && sp.at(0).len == line.size());
        }
        {
            // 行尾注释 → 从 // 到行尾
            const QString line = QStringLiteral("int x = 1; // 尾注");
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(line, QStringLiteral("c"));
            const int at = line.indexOf(QStringLiteral("//"));
            bool ok = at > 0 && !sp.isEmpty();
            if (ok) {
                const SyntaxHighlight::Span &last = sp.last();
                ok = last.kind == SyntaxHighlight::Kind::comment && last.start == at
                    && last.start + last.len == line.size();
            }
            check(log, "语法高亮：行尾注释从 // 吃到行尾", ok);
        }
        {
            // ③ 字符串吃到**闭合引号**（半截着色的字符串最难看）
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(QStringLiteral("x = \"hi\""), QStringLiteral("c"));
            check(log, "语法高亮：字符串吃到闭合引号",
                sp.size() == 1 && sp.at(0).kind == SyntaxHighlight::Kind::string
                    && sp.at(0).start == 4 && sp.at(0).len == 4);
        }
        {
            // ④ python：字符串里的 # 不是注释
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(QStringLiteral("s = \"# not comment\""),
                    QStringLiteral("python"));
            bool ok = sp.size() == 1 && sp.at(0).kind == SyntaxHighlight::Kind::string;
            if (ok) {
                // 整行不是注释（否则会是一整段 comment）
                ok = sp.at(0).start == 4;
            }
            check(log, "语法高亮：字符串里的 # 不当注释（python）", ok);
        }
        {
            // ④ python：**字符串外**的 # 才是注释（行尾 #）
            //    上一条只验了「字符串里的 #」，碰不到行尾 # 那条分支 —— 夹具得覆盖它。
            const QString line = QStringLiteral("x = 1  # 尾注");
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(line, QStringLiteral("python"));
            const int at = line.indexOf(QLatin1Char('#'));
            bool ok = at > 0 && !sp.isEmpty();
            if (ok) {
                const SyntaxHighlight::Span &last = sp.last();
                ok = last.kind == SyntaxHighlight::Kind::comment && last.start == at
                    && last.start + last.len == line.size();
            }
            check(log, "语法高亮：python 行尾 # 是注释（字符串外才生效）", ok);
        }
        {
            // ③ 关键字 / 数字分类
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(QStringLiteral("return 0xFF;"), QStringLiteral("go"));
            check(log, "语法高亮：关键字与十六进制数字分得开",
                sp.size() == 2 && sp.at(0).kind == SyntaxHighlight::Kind::keyword
                    && sp.at(0).len == 6 && sp.at(1).kind == SyntaxHighlight::Kind::number
                    && sp.at(1).len == 4);
        }
        {
            // ⑤ 段不重叠 / 不越界 / 按 start 升序（乱了就涂花）
            const QString line = QStringLiteral("func main() { let x = 1; /* c */ } // 尾");
            const QVector<SyntaxHighlight::Span> sp
                = SyntaxHighlight::highlight(line, QStringLiteral("cangjie"));
            bool ordered = true, inRange = true, noOverlap = true;
            int prevEnd = 0;
            for (const SyntaxHighlight::Span &s : sp) {
                ordered = ordered && s.start >= prevEnd;
                inRange = inRange && s.start >= 0 && s.len > 0
                    && s.start + s.len <= line.size();
                prevEnd = s.start + s.len;
            }
            for (int i = 1; i < sp.size(); ++i)
                noOverlap = noOverlap && sp.at(i).start >= sp.at(i - 1).start + sp.at(i - 1).len;
            check(log, "语法高亮：段按 start 升序、不重叠、不越界", ordered && inRange && noOverlap);
        }
        {
            // 行注释前缀：python 用 #，其余 //
            check(log, "语法高亮：行注释前缀（python # / 其余 //）",
                SyntaxHighlight::lineCommentPrefix(QStringLiteral("python"))
                        == QStringLiteral("#")
                    && SyntaxHighlight::lineCommentPrefix(QStringLiteral("go"))
                        == QStringLiteral("//"));
        }
        {
            // 空行 → 空段（不产出垃圾）
            check(log, "语法高亮：空行不产出段",
                SyntaxHighlight::highlight(QString(), QStringLiteral("c")).isEmpty()
                    && SyntaxHighlight::highlight(QStringLiteral("   "), QStringLiteral("c"))
                           .isEmpty());
        }
    }

}

} // namespace SelfCheckInternal
