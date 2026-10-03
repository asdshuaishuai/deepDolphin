#include "AiSettingsDialog.h"
#include "../../ai/SecretStore.h"
#include "../../app/Settings.h"
#include "../DesignTokens.h"
#include "panes/AutomationPane.h"
#include "panes/GeneralPane.h"
#include "panes/AiSettingsPane.h"
#include <DTabBar>
#include <QAbstractButton>
#include <QHBoxLayout>
#include <QLabel>
#include <QMetaObject>
#include <QPointer>
#include <QScrollArea>
#include <QStackedWidget>
#include <QThreadPool>
#include <QVBoxLayout>

AiSettingsDialog::AiSettingsDialog(QWidget *parent)
    : DDialog(parent)
    , m_store(new SecretStore)
{
    setWindowTitle(QStringLiteral("设置"));
    resize(520, 460);
    setMinimumSize(480, 400);
    setOnButtonClickedClose(false);

    auto *content = new QWidget(this);
    auto *v = new QVBoxLayout(content);
    v->setContentsMargins(0, 0, 0, 0);
    v->setSpacing(DS::Spacing::sm);

    // header：分段三页签（DTabBar + QStackedWidget——实测无 DTabWidget）
    m_tabs = new DTabBar(content);
    m_tabs->addTab(QIcon::fromTheme(QStringLiteral("preferences-system")), QStringLiteral("通用"));
    m_tabs->addTab(QIcon::fromTheme(QStringLiteral("preferences-system-time")),
        QStringLiteral("自动化"));
    m_tabs->addTab(QIcon::fromTheme(QStringLiteral("applications-engineering")),
        QStringLiteral("AI"));
    m_tabs->setExpanding(false);
    v->addWidget(m_tabs);

    // 【滚动归属逐页写死】通用/自动化两页套 QScrollArea；**AI 页不套**
    //（其内容自滚，再套外层会滚不动且把页脚顶出窗口——mac 实测教训）
    auto *wrapGeneral = new QScrollArea(content);
    wrapGeneral->setWidgetResizable(true);
    wrapGeneral->setFrameShape(QFrame::NoFrame);
    wrapGeneral->setWidget(new GeneralPane(wrapGeneral));
    m_generalPane = wrapGeneral->widget();

    auto *wrapAutomation = new QScrollArea(content);
    wrapAutomation->setWidgetResizable(true);
    wrapAutomation->setFrameShape(QFrame::NoFrame);
    m_automationWidget = new AutomationPane(wrapAutomation);
    wrapAutomation->setWidget(m_automationWidget);

    auto *aiPane = new AiSettingsPane(content);
    m_aiPane = aiPane;

    m_stack = new QStackedWidget(content);
    m_stack->addWidget(wrapGeneral);
    m_stack->addWidget(wrapAutomation);
    m_stack->addWidget(aiPane);
    v->addWidget(m_stack, 1);

    addContent(content);

    // 页脚：随页签换语义（AI=取消/保存（aiDirty 才可用）；另两页只有「关闭」——
    // 摆「取消」是死控件）
    addButton(QStringLiteral("关闭"), true); // 索引 0：AI 页时改标「取消」
    addButton(QStringLiteral("保存"), false, DDialog::ButtonRecommend); // 索引 1
    m_footerError = new QLabel(this);
    m_footerError->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::red).name()));
    m_footerError->setWordWrap(true);
    m_footerError->hide();
    addContent(m_footerError);

    // ── 加载当前配置（original 存**补过 baseURL 之后**的那份，否则一打开恒 dirty）──
    // key 不在这里同步读（M0-3）：libsecret 读可能在密钥环未解锁/卡住时阻塞秒级，
    // 构造里同步做 = 第一次打开设置冻结界面。身份先就位，key 由 worker 回填。
    AIConfig loaded = AIConfig::load();
    if (loaded.baseURL.isEmpty() && loaded.providerID == QLatin1String("anthropic"))
        loaded.baseURL = QStringLiteral("https://api.anthropic.com");
    m_original = loaded;
    aiPane->setDraft(loaded);
    m_loadedOnce = true;
    m_keyPending = true;

    QPointer<AiSettingsDialog> guard(this);
    QThreadPool::globalInstance()->start([this, guard, loaded, store = m_store] {
        const QString key = AIConfig::loadKey(store);
        if (!guard)
            return;
        QMetaObject::invokeMethod(
            guard,
            [this, guard, loaded, key] {
                if (!guard)
                    return;
                AIConfig withKey = loaded;
                withKey.apiKey = key;
                m_original = withKey;
                if (auto *pane = qobject_cast<AiSettingsPane *>(m_aiPane))
                    pane->setDraft(withKey);
                m_keyPending = false;
                refreshFooter();
            },
            Qt::QueuedConnection);
    });

    connect(aiPane, &AiSettingsPane::dirty, this, &AiSettingsDialog::refreshFooter);
    connect(m_tabs, &DTabBar::currentChanged, this, &AiSettingsDialog::switchTab);
    connect(this, &DDialog::buttonClicked, this, [this](int, const QString &text) {
        const bool aiTab = m_stack->currentIndex() == 2;
        if (text == QStringLiteral("保存")) {
            if (!aiTab)
                return;
            saveAi();
            return;
        }
        // 「关闭」（另两页）或「取消」（AI 页，丢弃草稿）
        reject();
    });
    switchTab(0);
}

void AiSettingsDialog::switchTab(int index)
{
    m_stack->setCurrentIndex(index);
    m_footerError->hide();
    refreshFooter();
}

bool AiSettingsDialog::aiDirty() const
{
    const AIConfig d = qobject_cast<AiSettingsPane *>(m_aiPane)->draft();
    return d.providerID != m_original.providerID || d.model != m_original.model
        || d.baseURL != m_original.baseURL || d.apiKey != m_original.apiKey;
}

void AiSettingsDialog::refreshFooter()
{
    const bool aiTab = m_stack->currentIndex() == 2;
    setButtonText(0, aiTab ? QStringLiteral("取消") : QStringLiteral("关闭"));
    if (QAbstractButton *save = getButton(1)) {
        // m_keyPending：回填 key 的 libsecret 读还没回来。期间不许保存——
        // 否则会把"还没读到的 key"当成空 key 覆盖掉（M0-3）。
        save->setVisible(aiTab);
        save->setEnabled(aiTab && !m_keyPending && aiDirty());
    }
}

void AiSettingsDialog::saveAi()
{
    auto *pane = qobject_cast<AiSettingsPane *>(m_aiPane);
    const AIConfig d = pane->draft();
    // AIConfig::saveTo 的语义在此拆开落位：QSettings 单例只在 GUI 线程写（身份 + 明文
    // 副本策略，代价小）；真正会卡秒级的 libsecret 同步写放 worker（PLAN §2.5）。
    Settings::instance().setAiIdentity(d.providerID, d.model, d.baseURL);
    if (d.providerID == QLatin1String("mock")) {
        // mock 通道：明文 Settings（PLAN §8 T9），不动 keychain
        Settings::instance().setAiApiKeyPlaintext(d.apiKey);
        m_original = d;
        m_footerError->hide();
        accept();
        return;
    }
    // 正常渠道：清明文副本；key 只进 libsecret（空 key = 删除条目）
    Settings::instance().setAiApiKeyPlaintext(QString());
    if (QAbstractButton *save = getButton(1))
        save->setEnabled(false); // 写入期间防双击
    QPointer<AiSettingsDialog> guard(this);
    SecretStore *store = m_store;
    const QString key = d.apiKey;
    QThreadPool::globalInstance()->start([this, guard, store, key, d] {
        QString err;
        const SecretStore::Status st
            = key.trimmed().isEmpty() ? store->remove(&err) : store->save(key, &err);
        const bool ok = st == SecretStore::Status::Ok;
        if (!guard)
            return;
        QMetaObject::invokeMethod(
            guard,
            [this, guard, d, ok, err] {
                if (!guard)
                    return;
                if (QAbstractButton *save = getButton(1))
                    save->setEnabled(true);
                if (!ok) {
                    // 保存失败：红字贴页脚、**不关窗**、tab 强切回 AI
                    m_tabs->setCurrentIndex(2);
                    m_stack->setCurrentIndex(2);
                    m_footerError->setText(err);
                    m_footerError->show();
                    return;
                }
                m_original = d; // 保存成功 → 新基线
                m_footerError->hide();
                accept();
            },
            Qt::QueuedConnection);
    });
}
