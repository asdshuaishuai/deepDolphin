#include "AutomationPane.h"
#include "../../../app/Settings.h"
#include "../../DesignTokens.h"
#include "../../common/SecondaryLabel.h"
#include "../../common/SegmentedButton.h"
#include <QLabel>
#include <QVBoxLayout>

namespace {
const int kHours[] = { 0, 1, 3, 6, 12, 24 };
const char *kLabels[] = { "关闭", "每 1 小时", "每 3 小时", "每 6 小时", "每 12 小时",
    "每 24 小时" };
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

    // 定时分段：ui/common/SegmentedButton 单一实现（本页与 DashboardFilterBar 原各自
    // 持有一份 segSheet——跨函数 .arg 的坑 #3 曾在此，M3b 收编）
    m_seg = new SegmentedButton(this);
    for (int i = 0; i < 6; ++i)
        m_seg->addButton(QString::fromUtf8(kLabels[i]));
    v->addWidget(m_seg);

    m_current = new SecondaryLabel(this);
    m_current->setFont(DS::font(DS::FontT::label));
    m_current->setWordWrap(true);
    v->addWidget(m_current);

    auto *note = new SecondaryLabel(QStringLiteral(
        "开启后按间隔对全部项目执行浅更新；AI 已配置时会生成简报并推送通知。\n"
        "改完立即生效，不经过下面的保存按钮。"), this);
    note->setFont(DS::font(DS::FontT::label));
    note->setWordWrap(true);
    v->addWidget(note);
    v->addStretch(1);

    m_seg->onClicked = [this](int id) {
        reflect(kHours[id]);
        Settings::instance().setAutoUpdateHours(kHours[id]);
        emit autoHoursChanged(kHours[id]); // 立即 restartAutoTimer（不经过保存按钮）
    };

    reflect(Settings::instance().autoUpdateHours());
}

void AutomationPane::reflect(int hours)
{
    for (int i = 0; i < 6; ++i) {
        if (kHours[i] == hours) {
            m_seg->setChecked(i); // 内部按选中态重刷两档 QSS
            break;
        }
    }
    m_current->setText(hours <= 0
            ? QStringLiteral("当前：关闭（不会自动执行更新）")
            : QStringLiteral("当前：每 %1 小时对全部项目执行一次浅更新").arg(hours));
}
