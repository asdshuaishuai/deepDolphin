#include "SetupGuidePage.h"
#include "../../logic/IconNames.h"
#include "../../platform/IconResolver.h"
#include "../DesignTokens.h"
#include "../common/FlatButton.h"
#include "../common/SecondaryLabel.h"
#include <DDialog>
#include <DPushButton>
#include <DSpinner>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <dspinner.h>

DWIDGET_USE_NAMESPACE

SetupGuidePage::SetupGuidePage(const QString &problem, const QString &downloadLabel,
    const QString &downloadTooltip, QWidget *parent)
    : QWidget(parent)
{
    auto *v = new QVBoxLayout(this);
    v->setContentsMargins(DS::Spacing::xxl, DS::Spacing::xxl, DS::Spacing::xxl, DS::Spacing::xxl);
    v->setSpacing(DS::Spacing::md);
    v->addStretch(1);

    m_icon = new QLabel(this);
    m_icon->setPixmap(platform::icon(IconNames::Id::warning).pixmap(42, 42));
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

    m_problem = new SecondaryLabel(this);
    m_problem->setWordWrap(true);
    m_problem->setAlignment(Qt::AlignCenter);
    v->addWidget(m_problem);
    setProblem(problem);

    // ── 下载态提示行（下载中/失败原因）──
    // ⚠ 文案由**判定层**生成（AppModel::engineDownloadMessage），UI 不自己写。
    m_downloadMsg = new SecondaryLabel(this);
    m_downloadMsg->setWordWrap(true);
    m_downloadMsg->setAlignment(Qt::AlignCenter);
    m_downloadMsg->hide();
    v->addWidget(m_downloadMsg);

    auto *row = new QHBoxLayout;
    row->addStretch(1);
    // ⚠ **主操作**：引擎缺失时用户唯一的出路就在这块屏幕上（不许绕到设置页去找）。
    //   标签与悬停说明由**上层传入**（判定层真相源）⇒ 本页不自己写。
    m_download = new DPushButton(downloadLabel, this);
    m_download->setToolTip(downloadTooltip);
    connect(m_download, &QPushButton::clicked, this, &SetupGuidePage::downloadClicked);
    row->addWidget(m_download);
    // 次操作：已经装好了、只是这次没探到 ⇒ 重探一次。
    m_redetect = new FlatButton(QStringLiteral("重新检测引擎"), this);
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
    m_busy = busy;
    // 发现链在跑（M0-2）：马上下结论会闪烁"未找到→已找到"，用忙态如实表达"还在探"；
    // busy 结束由 setProblem + refreshChrome 收尾（found/未找到都会走一遍）。
    m_title->setText(busy ? QStringLiteral("正在检测引擎…") : QStringLiteral("引擎未找到"));
    m_icon->setVisible(!busy);
    m_spinner->setVisible(busy);
    m_spinner->start(); // 非 busy 时由 setVisible(false) 收尾（隐藏即停渲染）
    m_problem->setVisible(!busy);
    if (m_redetect)
        m_redetect->setEnabled(!busy);
    // ⚠ 探测中不许同时下载（两条链都在动引擎目录 ⇒ 互相干扰）。
    if (m_download)
        m_download->setEnabled(!busy && !m_downloading);
}

void SetupGuidePage::setDownloadState(bool downloading, const QString &message)
{
    m_downloading = downloading;
    // ⚠ 下载中禁用「重新检测」：发现链会探到**半装**的引擎目录 ⇒ 结论会是假的。
    if (m_redetect)
        m_redetect->setEnabled(!downloading && !m_busy);
    if (m_download)
        m_download->setEnabled(!downloading && !m_busy);
    if (m_downloadMsg) {
        m_downloadMsg->setText(message);
        m_downloadMsg->setVisible(!message.isEmpty());
    }
}
