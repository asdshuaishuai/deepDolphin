#include "DocsDialogProbe.h"

#include "DocsDialog.h"

#include "../../logic/DocPages.h"

#include <QComboBox>

QString docsLangProbeReport(DocsDialog *dlg)
{
    // ⚠ 走**真实信号路径**（currentIndexChanged → onLanguagePicked → applyLanguage）：
    //   直接调内部函数的话，测的就不是「用户点下去」那条路。
    auto *box = dlg->findChild<QComboBox *>();
    if (!box)
        return QString();

    const QVector<DocPages::Language> langs = DocPages::languages();
    QStringList out;
    for (int i = 0; i < box->count(); ++i) {
        box->setCurrentIndex(i);
        const QStringList v = dlg->probeValues();
        // v 的顺序：标题 / 关闭按钮 / 四个类目分段名 / 正文 / 底部说明
        const QString key = i < langs.size() ? DocPages::languageKey(langs.at(i)) : QString();
        out << QStringLiteral("lang=%1").arg(key);
        out << QStringLiteral("title=%1").arg(v.value(0));
        out << QStringLiteral("close=%1").arg(v.value(1));
        QStringList segs;
        for (int s = 2; s <= 5 && s < v.size(); ++s)
            segs << v.at(s);
        out << QStringLiteral("segments=%1").arg(segs.join(QLatin1Char('|')));
        QString body = v.value(6);
        body.replace(QLatin1Char('\n'), QLatin1Char('|'));
        out << QStringLiteral("body=%1").arg(body.left(120));
        out << QStringLiteral("hint=%1").arg(v.value(7));
    }
    return out.join(QLatin1Char('\n'));
}
