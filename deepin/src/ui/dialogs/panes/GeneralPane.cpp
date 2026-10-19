#include "GeneralPane.h"
#include "../../../app/AppModel.h"
#include "../../../logic/ClientDecisions.h"
#include "../../../logic/EngineDoctor.h"
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

GeneralPane::GeneralPane(AppModel *model, QWidget *parent)
    : QWidget(parent)
    , m_model(model)
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

    // ── 环境自检卡（引擎 doctor）──
    // 「环境坏了」是最难自查的一类问题：界面看着好好的，引擎在后台早就跑不动了。
    // 这里给一个**用户自己就能按**的入口，并把引擎的逐项检查原样摊开。
    auto *doctorCard = new QWidget(this);
    auto *doctorRow = new QHBoxLayout(doctorCard);
    doctorRow->setSpacing(DS::Spacing::md);
    auto *doctorCol = new QVBoxLayout;
    auto *doctorTitle = new QLabel(QStringLiteral("环境自检"), doctorCard);
    doctorTitle->setFont(DS::font(DS::FontT::cardTitle));
    doctorCol->addWidget(doctorTitle);
    auto *doctorSub = new SecondaryLabel(
        QStringLiteral("检查引擎与本地环境是否可用（引擎 doctor）。"), doctorCard);
    doctorSub->setFont(DS::font(DS::FontT::label));
    doctorCol->addWidget(doctorSub);
    m_doctorSummary = new QLabel(doctorCard);
    m_doctorSummary->setFont(DS::font(DS::FontT::label));
    m_doctorSummary->setWordWrap(true);
    m_doctorSummary->hide();
    doctorCol->addWidget(m_doctorSummary);
    m_doctorBody = new QWidget(doctorCard);
    auto *doctorBodyLayout = new QVBoxLayout(m_doctorBody);
    doctorBodyLayout->setContentsMargins(0, 0, 0, 0);
    doctorBodyLayout->setSpacing(DS::Spacing::xs);
    m_doctorBody->hide();
    doctorCol->addWidget(m_doctorBody);
    doctorRow->addLayout(doctorCol, 1);
    m_doctorButton = new DPushButton(QStringLiteral("运行自检"), doctorCard);
    m_doctorButton->setToolTip(QStringLiteral("运行引擎自检（moongit doctor）"));
    connect(m_doctorButton, &DPushButton::clicked, this, [this] {
        if (!m_model)
            return;
        m_doctorButton->setEnabled(false);
        m_doctorSummary->setText(QStringLiteral("正在自检…"));
        m_doctorSummary->show();
        m_model->runDoctor();
    });
    doctorRow->addWidget(m_doctorButton);
    v->addWidget(doctorCard);

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

    // 自检回执：引擎 doctor 有问题时**退出码是 1**但 stdout 仍是合法 JSON，
    // AppModel 读的是载荷 —— 这里收到的报告「有效」不等于「环境没问题」。
    if (m_model) {
        connect(m_model, &AppModel::doctorFinished, this, [this](const EngineDoctor::Report &r) {
            m_doctorButton->setEnabled(true);
            applyDoctorReport(r);
        });
    } else {
        // 没有模型就**禁用按钮**：给个点了没反应的入口比不给更糟
        m_doctorButton->setEnabled(false);
    }
}

void GeneralPane::reflectSystemState(bool enabled)
{
    QSignalBlocker block(m_switch);
    m_switch->setChecked(enabled);
}

void GeneralPane::applyDoctorReport(const EngineDoctor::Report &r)
{
    // 逐行重建（旧行全部清掉）：报告条数每次都可能不同。
    if (m_doctorBody->layout()) {
        auto *lay = m_doctorBody->layout();
        while (lay->count() > 0) {
            QLayoutItem *it = lay->takeAt(0);
            if (it->widget())
                it->widget()->deleteLater();
            delete it;
        }
    }
    auto *bodyLayout = qobject_cast<QVBoxLayout *>(m_doctorBody->layout());
    if (!bodyLayout)
        bodyLayout = new QVBoxLayout(m_doctorBody);

    // 视图层只上色，档由判定层给（EngineDoctor::toneOf）。
    DS::SemColor tone = DS::SemColor::gray;
    QString headline;
    switch (EngineDoctor::toneOf(r)) {
    case EngineDoctor::Tone::ok:
        tone = DS::SemColor::shallow;
        headline = QStringLiteral("环境自检：一切正常");
        break;
    case EngineDoctor::Tone::problem:
        tone = DS::SemColor::red;
        headline = QStringLiteral("环境自检：发现 %1 个问题").arg(r.problems);
        break;
    case EngineDoctor::Tone::unknown:
        // 问题数未知 ≠ 没问题：不能按「0 个问题」显示。
        tone = DS::SemColor::orange;
        headline = QStringLiteral("环境自检：问题数未知（引擎契约可能过旧）");
        break;
    case EngineDoctor::Tone::unreadable:
        tone = DS::SemColor::orange;
        headline = QStringLiteral("环境自检：报告读不出来");
        break;
    }
    m_doctorSummary->setText(headline + QStringLiteral(" · ") + EngineDoctor::summary(r));
    m_doctorSummary->setStyleSheet(QStringLiteral("color: %1;").arg(DS::semColor(tone).name()));
    m_doctorSummary->show();

    if (!r.ok) {
        auto *err = new SecondaryLabel(r.error.isEmpty() ? QStringLiteral("自检报告读不出来。") : r.error,
            m_doctorBody);
        err->setFont(DS::font(DS::FontT::label));
        err->setWordWrap(true);
        bodyLayout->addWidget(err);
        m_doctorBody->show();
        return;
    }

    for (const EngineDoctor::Check &c : r.checks) {
        const QString line = EngineDoctor::checkLine(c);
        if (line.isEmpty())
            continue;
        auto *l = new SecondaryLabel(line, m_doctorBody);
        l->setFont(DS::font(DS::FontT::label));
        l->setWordWrap(true);
        bodyLayout->addWidget(l);
    }
    m_doctorBody->setVisible(!r.checks.isEmpty());
}

void GeneralPane::showEvent(QShowEvent *event)
{
    QWidget::showEvent(event);
    // DLogManager::getlogFilePath() 在 registerFileAppender 之后才有效，故延迟到显示时读
    const QString path = DLogManager::getlogFilePath();
    m_logPath->setText(path.isEmpty() ? QStringLiteral("日志文件路径不可用。") : path);
    m_logButton->setEnabled(!path.isEmpty());
}
