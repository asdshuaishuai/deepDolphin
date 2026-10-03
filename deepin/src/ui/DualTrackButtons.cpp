#include "DualTrackButtons.h"
#include "DesignTokens.h"
#include <DPushButton>
#include <QHBoxLayout>
#include <QLabel>

DWIDGET_USE_NAMESPACE

DualTrackButtons::DualTrackButtons(QWidget *parent)
    : QWidget(parent)
{
    auto *h = new QHBoxLayout(this);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(DS::Spacing::xs);

    // DDE 集成感：主操作 = 强调色实底按钮（deepin 蓝 #0081FF，跟主题走），次操作 =
    // 普通 DTK 按钮。这里刻意不用 DSuggestButton：本容器里 DTK 样式插件（chameleon）
    // 不加载，DSuggestButton 画成白底白字（真机截图实证）；强调色 QSS 不依赖插件加载，
    // 在任何环境观感一致。
    m_shallow = new QPushButton(this);
    m_shallow->setCursor(Qt::PointingHandCursor);
    m_shallow->setStyleSheet(
        QStringLiteral("QPushButton { background: %1; color: white; border: none;"
                       " border-radius: %2px; padding: 4px 14px; }"
                       "QPushButton:disabled { background: %3; }")
            .arg(DS::semColor(DS::SemColor::accent).name())
            .arg(DS::Radius::control)
            .arg(DS::textSecondary().name()));
    connect(m_shallow, &QPushButton::clicked, this, &DualTrackButtons::shallowClicked);
    h->addWidget(m_shallow);

    // 待记录徽章：白字绿底胶囊（pending>0 才出现）
    m_badge = new QLabel(this);
    m_badge->setStyleSheet(
        QStringLiteral("QLabel { background: %1; color: white; border-radius: 8px;"
                       " padding: 1px 7px; font-size: 11px; }")
            .arg(DS::semColor(DS::SemColor::shallow).name()));
    m_badge->hide();
    h->addWidget(m_badge);

    m_deep = new DPushButton(this);
    m_deep->setCursor(Qt::PointingHandCursor);
    // help 写明会改写哪些文件（ScopeRules.deepTouches = "README · AGENTS · CLAUDE"）
    m_deep->setToolTip(
        QStringLiteral("重写托管文档：README · AGENTS · CLAUDE。这一步会改写你的文件"));
    connect(m_deep, &QPushButton::clicked, this, &DualTrackButtons::deepClicked);
    h->addWidget(m_deep);

    reflect();
}

void DualTrackButtons::setScope(UpdateScope scope)
{
    m_scope = scope;
    reflect();
}

void DualTrackButtons::setPending(int pending)
{
    m_pending = pending;
    reflect();
}

void DualTrackButtons::setBusy(bool busy)
{
    m_busy = busy;
    reflect();
}

void DualTrackButtons::reflect()
{
    const QString range = scopeTitle(m_scope); // 「· 全部 / · <项目>」
    m_shallow->setText(QStringLiteral("浅更新 %1").arg(range));
    m_deep->setText(QStringLiteral("深更新 %1").arg(range));
    m_shallow->setEnabled(!m_busy);
    m_deep->setEnabled(!m_busy);
    // 浅更新按钮仅在 pending>0 时显示待记录徽章
    m_badge->setText(QString::number(m_pending));
    m_badge->setVisible(m_pending > 0);
}
