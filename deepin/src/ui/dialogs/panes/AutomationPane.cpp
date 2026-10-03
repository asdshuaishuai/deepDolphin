#include "AutomationPane.h"
#include "../../../app/Settings.h"
#include "../../DesignTokens.h"
#include <QButtonGroup>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>

namespace {
const int kHours[] = { 0, 1, 3, 6, 12, 24 };
const char *kLabels[] = { "关闭", "每 1 小时", "每 3 小时", "每 6 小时", "每 12 小时",
    "每 24 小时" };

// 自包含（坑 #3 的反面教材位：跨函数 .arg 曾让 %1 落空刷告警）；未选中档从 DS::*
// 取值（原 palette(midlight)/palette(text)——与全仓同一颜色语言）
QString segSheet(bool checked)
{
    // 按钮 padding 一档 = buttonPaddingQss（M3-5，原 3px 12px 自成一档）；仍自包含（坑 #3）
    const QString base = QStringLiteral(
        "QPushButton { border: none; border-radius: %1px; %2 }")
        .arg(DS::Radius::chip)
        .arg(DS::buttonPaddingQss());
    if (checked)
        return base + QStringLiteral("QPushButton { background: %1; color: white; }")
            .arg(DS::semColor(DS::SemColor::accent).name());
    return base + QStringLiteral("QPushButton { background: %1; color: %2; }")
        .arg(DS::surfaceAlt().name(), DS::textPrimary().name());
}
} // namespace

AutomationPane::AutomationPane(QWidget *parent)
    : QWidget(parent)
{
    auto *v = new QVBoxLayout(this);
    v->setContentsMargins(DS::Spacing::xxl, DS::Spacing::lg, DS::Spacing::xxl, DS::Spacing::lg);
    v->setSpacing(DS::Spacing::md);

    auto *title = new QLabel(QStringLiteral("定时更新"), this);
    title->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(title);

    auto *segHost = new QWidget(this);
    auto *h = new QHBoxLayout(segHost);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(2);
    m_group = new QButtonGroup(this);
    m_group->setExclusive(true);
    for (int i = 0; i < 6; ++i) {
        auto *b = new QPushButton(QString::fromUtf8(kLabels[i]), segHost);
        b->setCheckable(true);
        m_group->addButton(b, i);
        h->addWidget(b);
        connect(b, &QPushButton::clicked, this, [this, i] {
            reflect(kHours[i]);
            Settings::instance().setAutoUpdateHours(kHours[i]);
            emit autoHoursChanged(kHours[i]); // 立即 restartAutoTimer（不经过保存按钮）
        });
    }
    h->addStretch(1);
    v->addWidget(segHost);

    m_current = new QLabel(this);
    m_current->setFont(DS::font(DS::FontT::label));
    DS::tagSecondaryStyle(m_current);
    m_current->setWordWrap(true);
    v->addWidget(m_current);

    auto *note = new QLabel(this);
    note->setText(QStringLiteral(
        "开启后按间隔对全部项目执行浅更新；AI 已配置时会生成简报并推送通知。\n"
        "改完立即生效，不经过下面的保存按钮。"));
    note->setFont(DS::font(DS::FontT::label));
    DS::tagSecondaryStyle(note);
    note->setWordWrap(true);
    v->addWidget(note);
    v->addStretch(1);

    reflect(Settings::instance().autoUpdateHours());
}

void AutomationPane::reflect(int hours)
{
    for (int i = 0; i < 6; ++i) {
        if (QAbstractButton *b = m_group->button(i)) {
            b->setChecked(kHours[i] == hours);
            b->setStyleSheet(segSheet(kHours[i] == hours));
        }
    }
    m_current->setText(hours <= 0
            ? QStringLiteral("当前：关闭（不会自动执行更新）")
            : QStringLiteral("当前：每 %1 小时对全部项目执行一次浅更新").arg(hours));
}
