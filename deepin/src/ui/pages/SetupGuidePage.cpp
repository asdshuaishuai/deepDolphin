#include "SetupGuidePage.h"
#include "../DesignTokens.h"
#include <DDialog>
#include <DSpinner>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <dspinner.h>

DWIDGET_USE_NAMESPACE

SetupGuidePage::SetupGuidePage(const QString &problem, QWidget *parent)
    : QWidget(parent)
{
    auto *v = new QVBoxLayout(this);
    v->setContentsMargins(DS::Spacing::xxl, DS::Spacing::xxl, DS::Spacing::xxl, DS::Spacing::xxl);
    v->setSpacing(DS::Spacing::md);
    v->addStretch(1);

    m_icon = new QLabel(this);
    m_icon->setPixmap(QIcon::fromTheme(QStringLiteral("dialog-warning")).pixmap(42, 42));
    m_icon->setAlignment(Qt::AlignCenter);
    v->addWidget(m_icon);

    m_spinner = new DSpinner(this);
    m_spinner->setFixedSize(28, 28);
    m_spinner->setVisible(false);
    v->addWidget(m_spinner, 0, Qt::AlignHCenter);

    m_title = new QLabel(QStringLiteral("引擎未找到"), this);
    m_title->setFont(DS::font(DS::FontT::sectionTitle));
    m_title->setAlignment(Qt::AlignCenter);
    v->addWidget(m_title);

    m_problem = new QLabel(this);
    m_problem->setWordWrap(true);
    m_problem->setAlignment(Qt::AlignCenter);
    DS::tagSecondaryStyle(m_problem);
    v->addWidget(m_problem);
    setProblem(problem);

    auto *row = new QHBoxLayout;
    row->addStretch(1);
    m_redetect = new QPushButton(QStringLiteral("重新检测引擎"), this);
    connect(m_redetect, &QPushButton::clicked, this, &SetupGuidePage::redetectClicked);
    row->addWidget(m_redetect);
    row->addStretch(1);
    v->addLayout(row);
    v->addStretch(2);
}

void SetupGuidePage::setProblem(const QString &problem)
{
    // CONTRACT §1.1 原文口径（EngineLocator::installHint）+ 逐条失败原因
    m_problem->setText(problem.isEmpty()
            ? QStringLiteral("未在常见路径找到 moongit/deepgit 引擎。")
            : problem);
}

void SetupGuidePage::setBusy(bool busy)
{
    // 发现链在跑（M0-2）：马上下结论会闪烁"未找到→已找到"，用忙态如实表达"还在探"；
    // busy 结束由 setProblem + refreshChrome 收尾（found/未找到都会走一遍）。
    m_title->setText(busy ? QStringLiteral("正在检测引擎…") : QStringLiteral("引擎未找到"));
    m_icon->setVisible(!busy);
    m_spinner->setVisible(busy);
    m_spinner->start(); // 非 busy 时由 setVisible(false) 收尾（隐藏即停渲染）
    m_problem->setVisible(!busy);
    if (m_redetect)
        m_redetect->setEnabled(!busy);
}
