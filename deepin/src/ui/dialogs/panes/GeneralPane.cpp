#include "GeneralPane.h"
#include "../../../logic/ClientDecisions.h"
#include "../../../platform/AutostartManager.h"
#include "../../../platform/SysOpen.h"
#include "../../DesignTokens.h"
#include "../../common/SecondaryLabel.h"
#include <DLog>
#include <DPushButton>
#include <DSwitchButton>
#include <QHBoxLayout>
#include <QLabel>
#include <QVBoxLayout>

DCORE_USE_NAMESPACE
DWIDGET_USE_NAMESPACE

GeneralPane::GeneralPane(QWidget *parent)
    : QWidget(parent)
{
    auto *v = new QVBoxLayout(this);
    v->setContentsMargins(DS::Spacing::xxl, DS::Spacing::lg, DS::Spacing::xxl, DS::Spacing::lg);
    v->setSpacing(DS::Spacing::md);

    auto *card = new QWidget(this);
    auto *row = new QHBoxLayout(card);
    row->setSpacing(DS::Spacing::md);
    auto *textCol = new QVBoxLayout;
    auto *title = new QLabel(QStringLiteral("开机自启"), card);
    title->setFont(DS::font(DS::FontT::cardTitle));
    textCol->addWidget(title);
    auto *sub = new SecondaryLabel(QStringLiteral("登录桌面后自动在后台启动 deepDolphin 面板并常驻托盘。"), card);
    sub->setFont(DS::font(DS::FontT::label));
    textCol->addWidget(sub);
    m_status = new QLabel(card);
    m_status->setFont(DS::font(DS::FontT::label));
    m_status->setWordWrap(true);
    m_status->hide();
    textCol->addWidget(m_status);
    row->addLayout(textCol, 1);
    m_switch = new DSwitchButton(card);
    row->addWidget(m_switch);
    v->addWidget(card);

    // 日志卡片（M0-9）：报障时要能自己拿到日志——日志目录一键定位，不再让用户去猜
    auto *logCard = new QWidget(this);
    auto *logRow = new QHBoxLayout(logCard);
    logRow->setSpacing(DS::Spacing::md);
    auto *logCol = new QVBoxLayout;
    auto *logTitle = new QLabel(QStringLiteral("日志"), logCard);
    logTitle->setFont(DS::font(DS::FontT::cardTitle));
    logCol->addWidget(logTitle);
    m_logPath = new SecondaryLabel(logCard);
    m_logPath->setFont(DS::font(DS::FontT::label));
    m_logPath->setWordWrap(true);
    logCol->addWidget(m_logPath);
    logRow->addLayout(logCol, 1);
    m_logButton = new DPushButton(QStringLiteral("打开日志目录"), logCard);
    connect(m_logButton, &DPushButton::clicked, this, [] {
        // 取不到路径时按钮点不动（下方按能力置 enabled），别给个静默失败的入口
        SysOpen::revealInFileManager(DLogManager::getlogFilePath());
    });
    logRow->addWidget(m_logButton);
    v->addWidget(logCard);

    v->addStretch(1);

    reflectSystemState(AutostartManager::isEnabled());

    connect(m_switch, &DSwitchButton::checkedChanged, this, [this](bool checked) {
        QString err;
        const bool ok = AutostartManager::setEnabled(checked, &err);
        const bool systemState = AutostartManager::isEnabled();
        const auto rollback = ClientDecisions::autostartFailure(checked, systemState);
        if (!ok || rollback.rolledBack) {
            // 回滚开关到**系统真实状态** + 红字说明（不假装成功）
            QSignalBlocker block(m_switch);
            m_switch->setChecked(systemState);
            m_status->setText(!ok && !err.isEmpty() ? err : rollback.message);
            m_status->setStyleSheet(
                QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::red).name()));
            m_status->show();
        } else {
            m_status->setText(QStringLiteral("自启文件：%1").arg(AutostartManager::desktopFilePath()));
            DS::tagSecondaryStyle(m_status);
            m_status->show();
        }
        emit autostartToggled(m_switch->isChecked());
    });
}

void GeneralPane::reflectSystemState(bool enabled)
{
    QSignalBlocker block(m_switch);
    m_switch->setChecked(enabled);
}

void GeneralPane::showEvent(QShowEvent *event)
{
    QWidget::showEvent(event);
    // DLogManager::getlogFilePath() 在 registerFileAppender 之后才有效，故延迟到显示时读
    const QString path = DLogManager::getlogFilePath();
    m_logPath->setText(path.isEmpty() ? QStringLiteral("日志文件路径不可用。") : path);
    m_logButton->setEnabled(!path.isEmpty());
}
