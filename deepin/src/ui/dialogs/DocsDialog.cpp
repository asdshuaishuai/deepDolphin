#include "DocsDialog.h"

#include "../../app/Settings.h"
#include "../../logic/DocPages.h"
#include "../DesignTokens.h"
#include "../common/FlatButton.h"
#include "../common/SecondaryLabel.h"
#include "../common/SegmentedButton.h"

#include <QComboBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QTextBrowser>
#include <QVBoxLayout>

DocsDialog::DocsDialog(QWidget *parent)
    : DDialog(parent)
{
    resize(760, 640);
    setMinimumSize(520, 400);
    setOnButtonClickedClose(false);

    // 语言：读持久化值 → 判定层解析（认不出 ⇒ 回落 + 标记 recovered）。
    const QString storedKey = Settings::instance().docsLanguageKey();
    const DocPages::LanguageResolution res = DocPages::resolveLanguage(storedKey);
    m_language = res.language;
    m_recovered = res.recovered;
    m_recoveredKey = storedKey;
    if (m_recovered) {
        // 自愈：把坏掉的键改回落到的语言（并说一句）。
        // 留着坏值 ⇒ 每次打开都提示，也坑到读同一个键的别的工具。
        Settings::instance().setDocsLanguageKey(DocPages::languageKey(m_language));
    }

    auto *content = new QWidget(this);
    auto *v = new QVBoxLayout(content);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::sm);

    // 顶行：左 = 四类目分段（顺序取自 DocPages::kinds() —— 单一真相源），
    //       右 = 语言选择器（页内切换）。
    auto *topRow = new QHBoxLayout;
    topRow->setSpacing(DS::Spacing::sm);

    m_segments = new SegmentedButton(content);
    const QVector<DocPages::Kind> all = DocPages::kinds();
    for (int i = 0; i < all.size(); ++i) {
        const DocPages::Kind k = all.at(i);
        m_segments->addButton(DocPages::kindTitle(k, m_language), DocPages::kindKey(k));
    }
    m_segments->setChecked(0);
    m_segments->onClicked = [this](int id) { onSegment(id); };
    topRow->addWidget(m_segments);
    topRow->addStretch(1);

    m_langBox = new QComboBox(content);
    m_langBox->setSizeAdjustPolicy(QComboBox::AdjustToContents);
    const QVector<DocPages::Language> langs = DocPages::languages();
    int current = 0;
    for (int i = 0; i < langs.size(); ++i) {
        m_langBox->addItem(DocPages::languageLabel(langs.at(i)));
        if (langs.at(i) == m_language)
            current = i;
    }
    // ⚠ 先设当前项、**后**连信号：否则程序化设值会立刻触发回调 ⇒ 写回设置。
    m_langBox->setCurrentIndex(current);
    connect(m_langBox, &QComboBox::currentIndexChanged, this,
        [this](int idx) { onLanguagePicked(idx); });
    topRow->addWidget(m_langBox);

    v->addLayout(topRow);

    // 正文（markdown）
    m_body = new QTextBrowser(content);
    m_body->setOpenExternalLinks(true);
    m_body->setOpenLinks(true);
    v->addWidget(m_body, 1);

    // 底部：仓库链接 + 说明
    auto *row = new QHBoxLayout;
    m_hint = new SecondaryLabel(QString(), content);
    m_hint->setWordWrap(true);
    row->addWidget(m_hint, 1);
    m_repo = new FlatButton(content);
    m_repo->setText(DocPages::repoLabel(m_language));
    connect(m_repo, &QPushButton::clicked, this,
        [this] { emit openUrl(DocPages::clientRepo()); });
    row->addWidget(m_repo);
    v->addLayout(row);

    addContent(content);
    addButton(DocPages::closeLabel(m_language), true); // 索引 0

    applyLanguage();
}

void DocsDialog::onSegment(int id)
{
    showKind(id);
}

void DocsDialog::onLanguagePicked(int index)
{
    const QVector<DocPages::Language> langs = DocPages::languages();
    if (index < 0 || index >= langs.size())
        return;
    if (langs.at(index) == m_language)
        return;
    m_language = langs.at(index);
    // 用户自己选过了 ⇒ 「存的值坏掉」这件事已经过去，不再提示。
    m_recovered = false;
    m_recoveredKey.clear();
    Settings::instance().setDocsLanguageKey(DocPages::languageKey(m_language));
    applyLanguage();
}

void DocsDialog::applyLanguage()
{
    // ⚠ 换语言时**所有**随语言变的文案一起换（分段名 / 标题 / 按钮 / 底部说明）——
    //   只换正文会留下「中文分段名 + 英文正文」的半截状态，比不做更糟。
    setWindowTitle(DocPages::windowTitle(m_language));

    const QVector<DocPages::Kind> all = DocPages::kinds();
    for (int i = 0; i < all.size(); ++i)
        m_segments->setButtonText(i, DocPages::kindTitle(all.at(i), m_language));

    m_repo->setText(DocPages::repoLabel(m_language));
    setButtonText(0, DocPages::closeLabel(m_language));

    showKind(m_kindIndex);
}

void DocsDialog::showKind(int index)
{
    const QVector<DocPages::Kind> all = DocPages::kinds();
    if (index < 0 || index >= all.size())
        return;
    m_kindIndex = index;
    const DocPages::Kind k = all.at(index);
    const QString text = DocPages::content(k, m_language);
    // 内容取不到（类目/语言不认识）→ 如实说「读不到」，不给空壳页。
    if (text.isEmpty()) {
        m_body->setPlainText(DocPages::unavailableText(k, m_language));
        updateHint();
        return;
    }
    m_body->setMarkdown(text);
    updateHint();
}

void DocsDialog::updateHint()
{
    if (m_recovered) {
        // 坏值提示优先于出处说明（此时更该告诉用户「你的设置没被认出来」）。
        m_hint->setText(DocPages::recoveredNotice(m_recoveredKey, m_language));
        return;
    }
    m_hint->setText(DocPages::engineRepoHint(m_language, DocPages::engineRepo()));
}
