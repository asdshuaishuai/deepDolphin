#include "BusyRow.h"
#include "../DesignTokens.h"
#include "SecondaryLabel.h"
#include <DGuiApplicationHelper>
#include <QHBoxLayout>

DGUI_USE_NAMESPACE // DGuiApplicationHelper（HasAnimations 动效判据）

// 行内转圈一档 16px（ProjectDetailPage 原 header busy spinner 口径；SetupGuide 的
// 28px 是整页忙态，不归本组件——见头文件口径边界）。
BusyRow::BusyRow(const QString &text, QWidget *parent)
    : QWidget(parent)
{
    auto *h = new QHBoxLayout(this);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(DS::Spacing::sm);
    m_spinner = new Dtk::Widget::DSpinner(this);
    m_spinner->setFixedSize(16, 16);
    h->addWidget(m_spinner);
    if (!text.isEmpty())
        h->addWidget(m_label = new SecondaryLabel(text, this));
    setBusy(true);
}

void BusyRow::setBusy(bool busy)
{
    setVisible(busy);
    // 关动画（无障碍/省电）：不 start()，转圈退化为静态弧 + 文案；信息不丢。
    if (busy && DGuiApplicationHelper::testAttribute(DGuiApplicationHelper::HasAnimations))
        m_spinner->start();
    else
        m_spinner->stop();
}
