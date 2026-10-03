#include "DualTrackButtons.h"
#include "DesignTokens.h"
#include "common/BusyRow.h"
#include <DPushButton>
#include <DSuggestButton>
#include <QHBoxLayout>
#include <QLabel>

DWIDGET_USE_NAMESPACE

DualTrackButtons::DualTrackButtons(QWidget *parent)
    : QWidget(parent)
{
    auto *h = new QHBoxLayout(this);
    h->setContentsMargins(0, 0, 0, 0);
    h->setSpacing(DS::Spacing::xs);

    // 主操作 = DSuggestButton（DTK 推荐按钮：真机上是强调色实底，与 DDE 内建应用同源，
    // 且随系统强调色走——手写死蓝值做不到）。dev 容器 chameleon 插件不加载时
    // DSuggestButton 画成白底白字（真机截图实证），此时才上 DS:: 取值的兜底 QSS
    //（原则 R2：兜底只准从 DS::* 取值）；判据与 main 的调色板兜底同一探针。
    m_shallow = new DSuggestButton(this);
    m_shallow->setCursor(Qt::PointingHandCursor);
    if (!DS::paletteIsThemeConsistent()) {
        m_shallow->setStyleSheet(
            QStringLiteral("DSuggestButton, QPushButton { background: %1; color: white;"
                           " border: none; border-radius: %2px; %3 }"
                           "DSuggestButton:disabled, QPushButton:disabled { background: %4; }")
                .arg(DS::semColor(DS::SemColor::accent).name())
                .arg(DS::Radius::control)
                .arg(DS::buttonPaddingQss()) // 按钮 padding 一档（M3-5，原 4px 14px 自成一档）
                .arg(DS::textSecondary().name()));
    }
    connect(m_shallow, &QPushButton::clicked, this, &DualTrackButtons::shallowClicked);
    h->addWidget(m_shallow);

    // 待记录徽章：白字绿底胶囊（pending>0 才出现）。保持 QLabel+语义色 QSS：
    // 浅绿是跨页状态语义色（mac 对位契约，D-2），DTipLabel 的灰色气泡承载不了它
    m_badge = new QLabel(this);
    m_badge->setStyleSheet(
        QStringLiteral("QLabel { background: %1; color: white; border-radius: %2px;"
                       " padding: 1px 7px; font-size: 11px; }")
            .arg(DS::semColor(DS::SemColor::shallow).name())
            .arg(DS::Radius::pill)); // 胶囊徽章 = pill 档（M3-5，原 8 硬编码）
    m_badge->hide();
    h->addWidget(m_badge);

    m_deep = new DPushButton(this);
    m_deep->setCursor(Qt::PointingHandCursor);
    // help 写明会改写哪些文件（ScopeRules.deepTouches = "README · AGENTS · CLAUDE"）
    m_deep->setToolTip(
        QStringLiteral("重写托管文档：README · AGENTS · CLAUDE。这一步会改写你的文件"));
    connect(m_deep, &QPushButton::clicked, this, &DualTrackButtons::deepClicked);
    h->addWidget(m_deep);

    // 忙态 = BusyRow 转圈 + 文案（plan §3b 五处 busy 表达之一，原 reflect 只静默禁用
    // 两钮、不说「在忙」——忙态必须说出来，与决策 59 同一原则）
    m_busyRow = new BusyRow(QStringLiteral("正在更新…"), this);
    m_busyRow->setBusy(false);
    h->addWidget(m_busyRow);

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
    m_busyRow->setBusy(m_busy); // 忙态说出来（转圈 + 「正在更新…」），禁用只是附带结果
    // 浅更新按钮仅在 pending>0 时显示待记录徽章
    m_badge->setText(QString::number(m_pending));
    m_badge->setVisible(m_pending > 0);
}
