#include "LanguageCoverage.h"
#include "CommitTypeComposition.h"

namespace LanguageCoverage {

Rows coverage(const DashboardData &d)
{
    Rows r;
    const int total = static_cast<int>(d.languages.size());
    const int shown = qMin(total, LANG_BAR_MAX);

    QStringList notes;
    if (d.languagesTruncated)
        notes << QStringLiteral("有项目撞到跟踪文件上限，被丢掉的文件里可能还有整类语言");
    if (d.languagesTopCut)
        notes << QStringLiteral("语言种类超过引擎上限，只列了排名靠前的一部分（不是全部语言）");
    if (shown < total)
        notes << QStringLiteral("这张卡片只显示前 %1 种语言（共 %2 种）").arg(shown).arg(total);
    if (d.languagesFailed > 0) {
        QString line = QStringLiteral("%1 个项目语言采集失败，未计入这份分布（不是「这个项目群没有这些语言」）")
                           .arg(d.languagesFailed);
        if (!d.languagesFailedReasons.isEmpty() && !d.languagesFailedReasons.first().isEmpty())
            line += QStringLiteral("；原因示例：%1").arg(d.languagesFailedReasons.first());
        notes << line;
    }
    r.note = notes.join(QLatin1Char('\n'));

    // 采集失败时 languages 为空是**正常结果**，不是「没数据」。
    r.emptyTitle = (d.languagesFailed > 0 && total == 0) ? QStringLiteral("未采集到语言数据")
                                                         : QStringLiteral("暂无数据");

    for (int i = 0; i < shown; ++i) {
        const auto &lang = d.languages.at(i);
        r.rows.append({ lang.language, lang.count });
        r.barData.append({ CommitTypes::sequenceColor(i), lang.count });
    }
    return r;
}

} // namespace LanguageCoverage
