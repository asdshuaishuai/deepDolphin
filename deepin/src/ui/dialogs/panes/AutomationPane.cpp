#include "AutomationPane.h"
#include "../../../app/AppModel.h"
#include "../../../app/Settings.h"
#include "../../DesignTokens.h"
#include "../../common/SecondaryLabel.h"
#include "../../common/SegmentedButton.h"
#include <DPushButton>
#include <QLabel>
#include <QVBoxLayout>

namespace {
const int kHours[] = { 0, 1, 3, 6, 12, 24 };
const char *kLabels[] = { "关闭", "每 1 小时", "每 3 小时", "每 6 小时", "每 12 小时",
    "每 24 小时" };
} // namespace

AutomationPane::AutomationPane(AppModel *model, QWidget *parent)
    : QWidget(parent)
    , m_model(model)
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

    // ── 钩子卡（引擎 hook：post-commit / post-merge 托管块）──
    // 有了它，用户 commit 完就自动记了进度，不必回客户端点「更新」。
    auto *hookCard = new QWidget(this);
    auto *hookCol = new QVBoxLayout(hookCard);
    hookCol->setContentsMargins(0, 0, 0, 0);
    hookCol->setSpacing(DS::Spacing::xs);
    auto *hookTitle = new QLabel(QStringLiteral("提交后自动记录进度"), hookCard);
    hookTitle->setFont(DS::font(DS::FontT::cardTitle));
    hookCol->addWidget(hookTitle);
    auto *hookNote = new SecondaryLabel(QStringLiteral(
        "装上 post-commit / post-merge 钩子后，每次提交或合并都会自动记录分支进度，"
        "不必回客户端点「更新」。钩子以托管块形式写入各项目的 .git/hooks —— "
        "你自己写的钩子逻辑会原样保留，卸载时也只删托管块。"), hookCard);
    hookNote->setFont(DS::font(DS::FontT::label));
    hookNote->setWordWrap(true);
    hookCol->addWidget(hookNote);
    m_hookSummary = new QLabel(hookCard);
    m_hookSummary->setFont(DS::font(DS::FontT::label));
    m_hookSummary->setWordWrap(true);
    hookCol->addWidget(m_hookSummary);
    m_hookDetail = new SecondaryLabel(hookCard);
    m_hookDetail->setFont(DS::font(DS::FontT::label));
    m_hookDetail->setWordWrap(true);
    hookCol->addWidget(m_hookDetail);
    auto *hookRow = new QHBoxLayout;
    hookRow->setSpacing(DS::Spacing::sm);
    m_hookInstallButton = new Dtk::Widget::DPushButton(QStringLiteral("为所有项目安装"), hookCard);
    m_hookInstallButton->setToolTip(QStringLiteral("给每个已注册项目装上提交/合并钩子"));
    connect(m_hookInstallButton, &Dtk::Widget::DPushButton::clicked, this, [this] {
        if (m_model)
            m_model->installHooksAll();
    });
    hookRow->addWidget(m_hookInstallButton);
    m_hookUninstallButton = new Dtk::Widget::DPushButton(QStringLiteral("全部卸载"), hookCard);
    m_hookUninstallButton->setToolTip(
        QStringLiteral("从每个项目卸载钩子（只删托管块，你自己写的钩子逻辑保留）"));
    connect(m_hookUninstallButton, &Dtk::Widget::DPushButton::clicked, this, [this] {
        if (m_model)
            m_model->uninstallHooksAll();
    });
    hookRow->addWidget(m_hookUninstallButton);
    hookRow->addStretch(1);
    hookCol->addLayout(hookRow);
    v->addWidget(hookCard);

    if (m_model) {
        connect(m_model, &AppModel::hookStatusChanged, this, [this] { applyHookStatus(); });
        connect(m_model, &AppModel::hookActionFinished, this, [this](bool ok, const QString &text) {
            m_hookSummary->setText(text);
            m_hookSummary->setStyleSheet(
                QStringLiteral("color: %1;").arg(DS::semColor(
                    ok ? DS::SemColor::shallow : DS::SemColor::orange).name()));
            applyHookBusy();
        });
        connect(m_model, &AppModel::hookBusyChanged, this, [this] { applyHookBusy(); });
    }

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

void AutomationPane::applyHookStatus()
{
    if (!m_model)
        return;
    const QVector<EngineHook::Status> &list = m_model->hookStatus();
    int installed = 0;
    int unreadable = 0;
    QStringList detail;
    for (const EngineHook::Status &st : list) {
        if (!st.parsed || !st.installedPresent) {
            ++unreadable;
            detail << QStringLiteral("%1：状态读不出来").arg(st.project);
            continue;
        }
        if (EngineHook::installedCount(st) == 2) {
            ++installed;
        } else {
            detail << QStringLiteral("%1：%2").arg(st.project, EngineHook::summary(st));
        }
    }
    QString s = QStringLiteral("已为 %1 / %2 个项目装上钩子").arg(installed).arg(list.size());
    // ⚠ 「状态读不出来」要**单独说**：混进「没装」里会让人去重装一个已装的钩子。
    if (unreadable > 0)
        s += QStringLiteral("；%1 个项目状态读不出来").arg(unreadable);
    m_hookSummary->setText(s);
    m_hookDetail->setText(detail.isEmpty() ? QString() : detail.join(QStringLiteral("\n")));
    m_hookDetail->setVisible(!detail.isEmpty());
    applyHookBusy();
}

void AutomationPane::applyHookBusy()
{
    if (!m_model)
        return;
    const bool busy = m_model->hookBusy();
    m_hookInstallButton->setEnabled(!busy);
    m_hookUninstallButton->setEnabled(!busy);
    m_hookInstallButton->setText(busy ? QStringLiteral("正在处理…")
                                      : QStringLiteral("为所有项目安装"));
}

void AutomationPane::showEvent(QShowEvent *event)
{
    QWidget::showEvent(event);
    // 钩子状态是**引擎那边**的事实（别的进程/命令行也可能改过它）——
    // 每次打开这一页都重查一次，别让用户看着一份过期的状态做决定。
    if (m_model)
        m_model->loadHookStatus();
}
