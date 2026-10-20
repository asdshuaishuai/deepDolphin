#include "GeneralPane.h"
#include "../../../app/AppModel.h"
#include "../../../app/Settings.h"
#include "../../../logic/ClientDecisions.h"
#include "../../../logic/ArchReceipt.h"
#include "../../../logic/EngineDoctor.h"
#include "../../../logic/Notifications.h"
#include "../../../platform/AutostartManager.h"
#include "../../../platform/SysOpen.h"
#include "../../DesignTokens.h"
#include "../../common/SecondaryLabel.h"
#include <DComboBox>
#include <DLineEdit>
#include <DLog>
#include <DPushButton>
#include <DSwitchButton>
#include <QComboBox>
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

    // ── 引擎卡（引擎缺失时**唯一的出路**：下载并安装）──
    // ⚠ 为什么放第一张：引擎没装，客户端其他一切都是空的 —— 用户先看到的应该是这件事。
    // ⚠ **整块只在有 model 时才建**：没有 model 就没有引擎状态可说，
    //   而下面要在**构造期**取判定层文案（裸解 m_model->）⇒ m_model 为 null 时会崩
    //   在启动路径上。判空不建卡 ⇒ 那个按钮与状态位一律不出现。
    if (m_model) {
        auto *engineCard = new QWidget(this);
        auto *engineRow = new QHBoxLayout(engineCard);
        engineRow->setSpacing(DS::Spacing::md);
        auto *engineCol = new QVBoxLayout;
        auto *engineTitle = new QLabel(QStringLiteral("引擎"), engineCard);
        engineTitle->setFont(DS::font(DS::FontT::cardTitle));
        engineCol->addWidget(engineTitle);
        m_engineStatus = new SecondaryLabel(engineCard);
        m_engineStatus->setFont(DS::font(DS::FontT::label));
        m_engineStatus->setWordWrap(true);
        engineCol->addWidget(m_engineStatus);
        m_engineDownloadMsg = new QLabel(engineCard);
        m_engineDownloadMsg->setFont(DS::font(DS::FontT::label));
        m_engineDownloadMsg->setWordWrap(true);
        m_engineDownloadMsg->hide();
        engineCol->addWidget(m_engineDownloadMsg);
        engineRow->addLayout(engineCol, 1);
        // ⚠ 标签与悬停说明取**判定层真相源**（经 AppModel 转来）——
        //   首屏与这里共用同一份说法，不两处各写一遍。
        m_engineDownloadButton = new DPushButton(m_model->engineDownloadActionLabel(), engineCard);
        m_engineDownloadButton->setToolTip(m_model->engineDownloadActionTooltip());
        connect(m_engineDownloadButton, &DPushButton::clicked, this, [this] {
            if (!m_model)
                return;
            m_model->downloadEngine();
        });
        engineRow->addWidget(m_engineDownloadButton);
        v->addWidget(engineCard);
    }

    // ── 通知卡（显示时长可配；M1-4 收尾）──
    // ⚠ 为什么要有：通知在桌面上停留多久**该由用户定**（缺省 5s）。
    //   硬编码 5000 的话，想细看失败原因的用户只能干瞪眼。
    // ⚠ 时长归一在判定层（logic/Notifications）—— D-Bus 语义里 0 = 「永不消失」，
    //   越界值会让「设定的」与「看到的」不一致。
    {
        auto *notifyCard = new QWidget(this);
        auto *notifyRow = new QHBoxLayout(notifyCard);
        notifyRow->setSpacing(DS::Spacing::md);
        auto *notifyCol = new QVBoxLayout;
        auto *notifyTitle = new QLabel(QStringLiteral("通知"), notifyCard);
        notifyTitle->setFont(DS::font(DS::FontT::cardTitle));
        notifyCol->addWidget(notifyTitle);
        auto *notifySub = new SecondaryLabel(
            QStringLiteral("通知在桌面上停留多久。失败/停滞这类通知会顶替上一条，不会堆成一摞。"),
            notifyCard);
        notifySub->setFont(DS::font(DS::FontT::label));
        notifySub->setWordWrap(true);
        notifyCol->addWidget(notifySub);
        notifyRow->addLayout(notifyCol, 1);
        m_notifyTimeout = new DComboBox(notifyCard);
        m_notifyTimeout->setSizeAdjustPolicy(QComboBox::AdjustToContents);
        for (int s : { 5, 10, 30, 60 })
            m_notifyTimeout->addItem(QStringLiteral("%1 秒").arg(s), s * 1000);
        notifyRow->addWidget(m_notifyTimeout);
        v->addWidget(notifyCard);
        connect(m_notifyTimeout, &DComboBox::currentIndexChanged, this, [this](int) {
            // ⚠ 回填时不写回（否则「打开这一页」本身就会改设置）。
            if (!m_notifyTimeout || m_syncingTimeout)
                return;
            Settings::instance().setNotifyTimeoutMs(m_notifyTimeout->currentData().toInt());
        });
    }


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

    // ── 引擎配置卡（引擎 config）──
    // 展示**引擎实际在用的策略**：浅更新只记前 N 个分支、文档备份留 N 份。
    // 这两条是用户能直接看到后果的 —— 「这个分支怎么没更新」「备份怎么不见了」，
    // 答案就在这里。用户不必去猜「是不是坏了」。
    auto *configCard = new QWidget(this);
    auto *configRow = new QHBoxLayout(configCard);
    configRow->setSpacing(DS::Spacing::md);
    auto *configCol = new QVBoxLayout;
    auto *configTitle = new QLabel(QStringLiteral("引擎配置"), configCard);
    configTitle->setFont(DS::font(DS::FontT::cardTitle));
    configCol->addWidget(configTitle);
    auto *configSub = new SecondaryLabel(
        QStringLiteral("引擎当前实际在用的策略（改动在下次更新/备份时生效）。"), configCard);
    configSub->setFont(DS::font(DS::FontT::label));
    configCol->addWidget(configSub);
    m_configBody = new QWidget(configCard);
    auto *configBodyLayout = new QVBoxLayout(m_configBody);
    configBodyLayout->setContentsMargins(0, 0, 0, 0);
    configBodyLayout->setSpacing(DS::Spacing::xs);
    m_configBody->hide();
    configCol->addWidget(m_configBody);

    // 可改的两个数字项（引擎只认这两个键是「数量」语义）
    auto *editRow = new QHBoxLayout;
    editRow->setSpacing(DS::Spacing::sm);
    editRow->addWidget(new SecondaryLabel(QStringLiteral("浅更新分支上限"), configCard));
    m_shallowInput = new DLineEdit(configCard);
    m_shallowInput->setPlaceholderText(QStringLiteral("分支数"));
    m_shallowInput->setMaximumWidth(90);
    editRow->addWidget(m_shallowInput);
    editRow->addWidget(new SecondaryLabel(QStringLiteral("文档备份份数"), configCard));
    m_backupInput = new DLineEdit(configCard);
    m_backupInput->setPlaceholderText(QStringLiteral("份数"));
    m_backupInput->setMaximumWidth(90);
    editRow->addWidget(m_backupInput);
    // 用户手改输入框 → 记脏（重读时别把没写回的值冲掉）
    connect(m_shallowInput, &DLineEdit::textEdited, this, [this] { m_configInputsDirty = true; });
    connect(m_backupInput, &DLineEdit::textEdited, this, [this] { m_configInputsDirty = true; });

    auto *applyConfig = new DPushButton(QStringLiteral("应用"), configCard);
    applyConfig->setToolTip(QStringLiteral("写回引擎配置（引擎 config set）"));
    connect(applyConfig, &DPushButton::clicked, this, [this] {
        if (!m_model)
            return;
        m_configError->hide();
        // ⚠ 客户端先校验一遍：引擎也会拒，但那是**事后**（用户看到的是一句
        //   引擎的报错）。这里先拦一道，界面立刻说清是哪个值不对。
        bool ok = true;
        const int shallow = m_shallowInput->text().trimmed().toInt(&ok);
        if (!ok || shallow < 0) {
            m_configError->setText(QStringLiteral("浅更新分支上限要是非负整数。"));
            m_configError->show();
            return;
        }
        bool ok2 = true;
        const int backup = m_backupInput->text().trimmed().toInt(&ok2);
        if (!ok2 || backup < 0) {
            m_configError->setText(QStringLiteral("文档备份份数要是非负整数。"));
            m_configError->show();
            return;
        }
        m_model->setEngineConfig(QStringLiteral("update.maxShallowBranches"),
            QString::number(shallow));
        m_model->setEngineConfig(QStringLiteral("update.backupKeep"), QString::number(backup));
    });
    editRow->addWidget(applyConfig);
    editRow->addStretch(1);
    configCol->addLayout(editRow);

    auto *configNote = new SecondaryLabel(
        QStringLiteral("浅更新只记前 N 个分支的进度 —— 别的分支没动是撞上了上限，不是坏了。"),
        configCard);
    configNote->setFont(DS::font(DS::FontT::label));
    configNote->setWordWrap(true);
    configCol->addWidget(configNote);

    m_configError = new QLabel(configCard);
    m_configError->setFont(DS::font(DS::FontT::label));
    m_configError->setWordWrap(true);
    m_configError->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::red).name()));
    m_configError->hide();
    configCol->addWidget(m_configError);

    configRow->addLayout(configCol, 1);
    m_configButton = new DPushButton(QStringLiteral("读取引擎配置"), configCard);
    m_configButton->setToolTip(QStringLiteral("读取引擎当前配置（引擎 config list）"));
    // ⚠ 这行**故意写成单行**：接线门要能精确区分「按钮 → 读」与
    //   「打开本页 → 自动读」两个调用点（写成多行就区分不开了）。
    connect(m_configButton, &DPushButton::clicked, this, [this] { reloadEngineConfig(); });
    configRow->addWidget(m_configButton);
    v->addWidget(configCard);

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
        connect(m_model, &AppModel::engineDownloadingChanged, this, [this] { applyEngineState(); });
        connect(m_model, &AppModel::engineDownloadFinished, this,
            [this](bool ok, const QString &text) {
                m_engineDownloadMsg->setText(text);
                m_engineDownloadMsg->setStyleSheet(
                    QStringLiteral("color: %1;").arg(DS::semColor(
                        ok ? DS::SemColor::shallow : DS::SemColor::red).name()));
                m_engineDownloadMsg->show();
                applyEngineState();
            });
        connect(m_model, &AppModel::engineConfigChanged, this, [this] { applyEngineConfig(); });
        connect(m_model, &AppModel::engineConfigSaved, this, [this](bool ok, const QString &text) {
            if (ok) {
                // 写回成功 → 输入框不再是「待写」状态，后续重读可以正常回填
                m_configInputsDirty = false;
                m_configError->hide();
                return;
            }
            // 失败原因**原样**给引擎的（引擎自己会校验值：非整数会被拒）。
            m_configError->setText(ArchReceipt::plain(text));
            m_configError->show();
        });
    } else {
        // 没有模型就**禁用按钮**：给个点了没反应的入口比不给更糟
        m_doctorButton->setEnabled(false);
        m_configButton->setEnabled(false);
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

void GeneralPane::applyEngineConfig()
{
    if (!m_model)
        return;
    // 逐行重建（旧行全部清掉）：只读项每次都可能不同。
    if (m_configBody->layout()) {
        auto *lay = m_configBody->layout();
        while (lay->count() > 0) {
            QLayoutItem *it = lay->takeAt(0);
            if (it->widget())
                it->widget()->deleteLater();
            delete it;
        }
    }
    auto *bodyLayout = qobject_cast<QVBoxLayout *>(m_configBody->layout());
    if (!bodyLayout)
        bodyLayout = new QVBoxLayout(m_configBody);

    const auto addLine = [&](const QString &text) {
        auto *l = new SecondaryLabel(text, m_configBody);
        l->setFont(DS::font(DS::FontT::label));
        l->setWordWrap(true);
        bodyLayout->addWidget(l);
    };

    const LoadStateBox &st = m_model->engineConfigState();
    if (st.state == LoadState::loading) {
        addLine(QStringLiteral("正在读取引擎配置…"));
        m_configBody->show();
        return;
    }
    if (st.state == LoadState::failed) {
        addLine(QStringLiteral("读不出来：%1").arg(st.message));
        m_configBody->show();
        return;
    }

    const EngineConfig::Config &c = *m_model->engineConfig();
    if (!c.ok) {
        addLine(c.error.isEmpty() ? QStringLiteral("引擎配置读不出来。") : c.error);
        m_configBody->show();
        return;
    }

    // 只读项：界面语言（引擎侧）、受管文档、扫描根。
    // ⚠ **不展示引擎的 ai**（恒为空对象）—— AI 设置是客户端的事（app/Settings），
    //   两边各有一份会形成两个真相源。
    if (!c.language.isEmpty())
        addLine(QStringLiteral("界面语言（引擎侧）：%1").arg(c.language));
    addLine(QStringLiteral("受管文档：%1")
                .arg(c.docs.isEmpty() ? QStringLiteral("（无）")
                                       : c.docs.join(QStringLiteral("、"))));
    addLine(QStringLiteral("扫描根：%1")
                .arg(c.roots.isEmpty() ? QStringLiteral("（未设置）")
                                       : c.roots.join(QStringLiteral("、"))));
    m_configBody->show();

    // 可改项回填引擎**当前真的在用**的值（缺项就留空，不填 0 —— 那可能是合法值 0）。
    // ⚠ 用户手改过但还没写回时**不回填** —— 回填会把用户刚填的值冲掉
    //   （点「应用」写回第一个键会触发一次重读，第二个还没写回的值就没了）。
    if (!m_configInputsDirty) {
        if (c.hasMaxShallowBranches())
            m_shallowInput->setText(QString::number(c.maxShallowBranches));
        if (c.hasBackupKeep())
            m_backupInput->setText(QString::number(c.backupKeep));
    }
}

void GeneralPane::showEvent(QShowEvent *event)
{
    QWidget::showEvent(event);
    // DLogManager::getlogFilePath() 在 registerFileAppender 之后才有效，故延迟到显示时读
    const QString path = DLogManager::getlogFilePath();
    m_logPath->setText(path.isEmpty() ? QStringLiteral("日志文件路径不可用。") : path);
    m_logButton->setEnabled(!path.isEmpty());
    // 引擎配置是**引擎当前在用的策略**（别的进程/命令行也可能改过它）——
    // 每次打开这一页都重读一次，别让用户看着一份过期的值做决定。
    reloadEngineConfig();
    applyEngineState();
    // 通知时长：回填当前设置（打开这一页就能看到并改）。
    // ⚠ 设置里的值**可能不在下拉档位里**（手工改过配置文件）⇒ 如实加一项显示它，
    //   绝不「显示 5 秒、实际是别的」—— 那是在骗用户。
    if (m_notifyTimeout) {
        const int cur = Settings::instance().notifyTimeoutMs();
        int idx = m_notifyTimeout->findData(cur);
        if (idx < 0) {
            m_notifyTimeout->addItem(QStringLiteral("%1 秒").arg(cur / 1000), cur);
            idx = m_notifyTimeout->count() - 1;
        }
        m_syncingTimeout = true;
        m_notifyTimeout->setCurrentIndex(idx);
        m_syncingTimeout = false;
    }
}

void GeneralPane::applyEngineState()
{
    if (!m_model)
        return;
    const bool downloading = m_model->engineDownloading();
    m_engineDownloadButton->setEnabled(!downloading);
    // ⚠ 下载中按钮要**看得见**在动（否则用户以为没反应）⇒ 换成忙态文案。
    m_engineDownloadButton->setText(downloading ? m_model->engineDownloadBusyLabel()
                                                : m_model->engineDownloadActionLabel());
    // ⚠ 状态说明走判定层四态（已找到/正在查找/正在下载/没找到）——界面不自己写。
    m_engineStatus->setText(m_model->engineStatusText());
}

void GeneralPane::reloadEngineConfig()
{
    if (m_model)
        m_model->loadEngineConfig();
}
