#include "DocsDialog.h"

#include "../../logic/DocPages.h"
#include "../DesignTokens.h"
#include "../common/FlatButton.h"
#include "../common/SecondaryLabel.h"
#include "../common/SegmentedButton.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QTextBrowser>
#include <QVBoxLayout>

DocsDialog::DocsDialog(QWidget *parent)
    : DDialog(parent)
{
    setWindowTitle(QStringLiteral("deepDolphin 文档"));
    resize(760, 640);
    setMinimumSize(520, 400);
    setOnButtonClickedClose(false);

    auto *content = new QWidget(this);
    auto *v = new QVBoxLayout(content);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::sm);

    // 顶部分段：四类目（顺序取自 DocPages::kinds() —— 单一真相源）
    m_segments = new SegmentedButton(content);
    const QVector<DocPages::Kind> all = DocPages::kinds();
    for (int i = 0; i < all.size(); ++i) {
        const DocPages::Kind k = all.at(i);
        m_segments->addButton(DocPages::kindTitle(k), DocPages::kindKey(k));
    }
    m_segments->setChecked(0);
    m_segments->onClicked = [this](int id) { onSegment(id); };
    v->addWidget(m_segments);

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
    m_repo->setText(QStringLiteral("查看客户端仓库"));
    connect(m_repo, &QPushButton::clicked, this,
        [this] { emit openUrl(DocPages::clientRepo()); });
    row->addWidget(m_repo);
    v->addLayout(row);

    addContent(content);
    addButton(QStringLiteral("关闭"), true);

    showKind(0);
}

void DocsDialog::onSegment(int id)
{
    showKind(id);
}

void DocsDialog::showKind(int index)
{
    const QVector<DocPages::Kind> all = DocPages::kinds();
    if (index < 0 || index >= all.size())
        return;
    const DocPages::Kind k = all.at(index);
    const QString text = DocPages::content(k);
    // 内容取不到（类目/语言不认识）→ 如实说「读不到」，不给空壳页。
    if (text.isEmpty()) {
        m_body->setPlainText(QStringLiteral("这一篇文档读不到（类目 %1 没有对应内容）。")
                                 .arg(DocPages::kindKey(k)));
        m_hint->setText(QString());
        return;
    }
    m_body->setMarkdown(text);
    m_hint->setText(QStringLiteral("内容与 %1 引擎仓库：%2")
                         .arg(QStringLiteral("moongit"), DocPages::engineRepo()));
}
