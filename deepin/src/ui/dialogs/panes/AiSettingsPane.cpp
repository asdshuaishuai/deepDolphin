#include "AiSettingsPane.h"
#include "../../../ai/AIChannel.h"
#include "../../../ai/AIConfig.h"
#include "../../../ai/AIEngineFactory.h"
#include "../../../ai/ModelsDevCatalog.h"
#include "../../../ai/SecretStore.h"
#include "../../../app/Settings.h"
#include "../../DesignTokens.h"
#include "../../common/SecondaryLabel.h"
#include <QFormLayout>
#include <QFrame>
#include <QLabel>
#include <QPointer>
#include <QThreadPool>
#include <QVBoxLayout>

DWIDGET_USE_NAMESPACE

namespace {
constexpr int PROVIDER_PICKER_MAX = 40;

QFrame *sectionTitle(const QString &text, QWidget *parent)
{
    auto *f = new QFrame(parent);
    f->setFrameShape(QFrame::NoFrame);
    auto *v = new QVBoxLayout(f);
    v->setContentsMargins(0, 0, 0, 0);
    auto *l = new QLabel(text, f);
    l->setFont(DS::font(DS::FontT::cardTitle));
    v->addWidget(l);
    return f;
}
} // namespace

AiSettingsPane::AiSettingsPane(QWidget *parent)
    : QWidget(parent)
{
    // 【滚动归属】AI 页**不套外层 QScrollArea**（本 pane 自身布局即可滚——
    // 由 AiSettingsDialog 的 QScrollArea 归属纪律：AI 页不套）
    auto *v = new QVBoxLayout(this);
    v->setContentsMargins(DS::Spacing::xxl, DS::Spacing::lg, DS::Spacing::xxl, DS::Spacing::lg);
    v->setSpacing(DS::Spacing::md);

    // ── Section「Provider」──
    v->addWidget(sectionTitle(QStringLiteral("Provider"), this));
    m_provider = new DComboBox(this);
    m_provider->setSizeAdjustPolicy(QComboBox::AdjustToContents);
    v->addWidget(m_provider);
    m_providerNote = new SecondaryLabel(this);
    m_providerNote->setFont(DS::font(DS::FontT::label));
    m_providerNote->setWordWrap(true);
    v->addWidget(m_providerNote);
    m_endpoint = new SecondaryLabel(this);
    m_endpoint->setFont(DS::font(DS::FontT::label));
    m_endpoint->setWordWrap(true);
    v->addWidget(m_endpoint);

    // ── Section「模型」──
    v->addWidget(sectionTitle(QStringLiteral("模型"), this));
    m_modelFilter = new DLineEdit(this);
    m_modelFilter->setPlaceholderText(QStringLiteral("过滤模型（可选）"));
    m_modelFilter->setClearButtonEnabled(true);
    v->addWidget(m_modelFilter);
    m_model = new DComboBox(this);
    m_model->setEditable(false);
    v->addWidget(m_model);
    m_badges = new SecondaryLabel(this);
    m_badges->setFont(DS::font(DS::FontT::label));
    m_badges->setWordWrap(true);
    v->addWidget(m_badges);
    m_modelManual = new DLineEdit(this);
    m_modelManual->setPlaceholderText(QStringLiteral("或手动输入模型 id"));
    m_modelManual->setClearButtonEnabled(true);
    v->addWidget(m_modelManual);

    // ── Section「API Key」──
    v->addWidget(sectionTitle(QStringLiteral("API Key（存入系统密钥环 libsecret）"), this));
    m_key = new DPasswordEdit(this);
    v->addWidget(m_key);
    m_baseURLOverride = new DLineEdit(this);
    m_baseURLOverride->setPlaceholderText(QStringLiteral("Base URL 覆盖（留空 = 目录默认）"));
    m_baseURLOverride->setClearButtonEnabled(true);
    v->addWidget(m_baseURLOverride);

    // ── Section「测试连接」──
    v->addWidget(sectionTitle(QStringLiteral("测试连接"), this));
    m_test = new DPushButton(QStringLiteral("测试连接"), this);
    v->addWidget(m_test);
    m_testResult = new QLabel(this);
    m_testResult->setFont(DS::font(DS::FontT::label));
    m_testResult->setWordWrap(true);
    v->addWidget(m_testResult);

    auto *disclosure = new SecondaryLabel(QStringLiteral(
        "AI 全部在客户端执行：项目路径、分支、文档摘要等上下文会发送到你所配置的 provider 服务器。"), this);
    disclosure->setFont(DS::font(DS::FontT::label));
    disclosure->setWordWrap(true);
    v->addWidget(disclosure);
    v->addStretch(1);

    // ── 行为 ──
    rebuildProviderOptions(QString());
    connect(m_provider, &DComboBox::activated, this, [this](int index) {
        const QString pid = m_provider->itemData(index).toString();
        // 切 provider：清 model、清过滤词；baseURL 重置为目录 api（AISettingsView 对位）；
        // 特殊通道给专用基址：system 无需端点；mock 基址 = mac README 的自测基准值
        //（本实现里 mock 基址只是 # 脚本载体，不起网络）。
        m_modelManual->clear();
        m_modelFilter->clear();
        m_filterWord.clear();
        if (pid == QLatin1String("system")) {
            m_baseURLOverride->clear();
        } else if (pid == QLatin1String("mock")) {
            m_baseURLOverride->setText(QStringLiteral("http://127.0.0.1:5999/v1"));
        } else {
            const ModelsDevCatalog cat = ModelsDevCatalog::loadCached();
            if (const CatalogProvider *p = cat.find(pid)) {
                m_baseURLOverride->setText(p->api.value_or(QString()));
            } else if (pid == QLatin1String("anthropic")) {
                m_baseURLOverride->setText(QStringLiteral("https://api.anthropic.com"));
            }
        }
        rebuildModelOptions();
        reflectProviderMeta();
        emit dirty();
    });
    connect(m_modelFilter, &DLineEdit::textChanged, this, [this](const QString &t) {
        m_filterWord = t;
        rebuildModelOptions();
    });
    connect(m_model, &DComboBox::currentIndexChanged, this, [this](int) {
        reflectProviderMeta();
        emit dirty();
    });
    connect(m_modelManual, &DLineEdit::textChanged, this, [this](const QString &t) {
        if (!t.isEmpty() && m_model->currentIndex() != 0)
            m_model->setCurrentIndex(0); // 手动输入优先
        reflectProviderMeta();
        emit dirty();
    });
    connect(m_key, &DLineEdit::textChanged, this, [this](const QString &) { emit dirty(); });
    connect(m_baseURLOverride, &DLineEdit::textChanged, this,
        [this](const QString &) { emit dirty(); });
    connect(m_test, &QPushButton::clicked, this, [this] {
        const AIConfig d = draft();
        setTestBusy(true);
        // 同步 HTTP（20s）不能在 GUI 线程跑——放 QThreadPool，结果经 invokeMethod 回主线程。
        // key：用户没重输时从安全存储补（否则「没重输 key」被误判成未配置）。
        // Settings 明文回退键在 GUI 线程读好按值带进 worker（M0-4 不跨线程碰 Settings）。
        QPointer<AiSettingsPane> guard(this);
        const QString fallbackKey = Settings::instance().aiApiKeyPlaintext();
        QThreadPool::globalInstance()->start([this, guard, d, fallbackKey] {
            AIConfig cfg = d;
            if (cfg.apiKey.trimmed().isEmpty()) {
                SecretStore store;
                cfg.apiKey = AIConfig::loadKey(&store, fallbackKey);
            }
            const QString message = AIEngineFactory::testConnection(cfg);
            QMetaObject::invokeMethod(this, [this, guard, message] {
                if (!guard)
                    return; // 窗口已关
                setTestBusy(false);
                setTestResult(message.startsWith(QStringLiteral("连通：")), message);
                emit saveTested();
            }, Qt::QueuedConnection);
        });
    });
}

void AiSettingsPane::rebuildProviderOptions(const QString &currentId)
{
    QSignalBlocker block(m_provider);
    m_provider->clear();
    // 两个特殊通道（models.dev 目录之外，恒置顶）：
    //   · 系统级 AI（默认）—— 未配置显式渠道时的后端（UOS AI：唤起对话窗口，
    //     不支持程序化补全；AIEngineFactory 优先级「显式渠道 > 系统 AI」的可见入口）
    //   · mock · 本地自测 —— 对位 mac ai.providerID=mock 的全链路自测通道
    m_provider->addItem(QStringLiteral("系统级 AI（默认）"), QStringLiteral("system"));
    m_provider->addItem(QStringLiteral("mock · 本地自测"), QStringLiteral("mock"));
    const ModelsDevCatalog cat = ModelsDevCatalog::loadCached();
    const auto sorted = cat.sortedProviders();
    int added = 0;
    QStringList shownIds;
    for (const CatalogProvider &p : sorted) {
        const bool hasApi = p.api.has_value() && !p.api->isEmpty();
        if (!hasApi || added >= PROVIDER_PICKER_MAX)
            continue;
        m_provider->addItem(QStringLiteral("%1 (%2)").arg(p.name, p.id), p.id);
        shownIds << p.id;
        ++added;
    }
    // 当前 providerID 不在列表时追加一项兜底（防丢配置）
    if (!currentId.isEmpty() && !shownIds.contains(currentId) && currentId != QLatin1String("system")
        && currentId != QLatin1String("mock")) {
        QString name = currentId;
        if (const CatalogProvider *p = cat.find(currentId))
            name = p->name;
        m_provider->addItem(QStringLiteral("%1 (%2)").arg(name, currentId), currentId);
    }
    // 恒发披露（providerPickerSlice 原文口径）
    m_providerNote->setText(
        QStringLiteral("只列模型最多的前 %1 家（共 %2 家有可用端点，目录共 %3 家）；"
                       "其余的可用下方「Base URL 覆盖」手填端点")
            .arg(PROVIDER_PICKER_MAX)
            .arg(cat.withEndpointCount())
            .arg(cat.totalProviders()));
}

void AiSettingsPane::rebuildModelOptions()
{
    QSignalBlocker block(m_model);
    const QString pid = m_provider->currentData().toString();
    m_model->clear();
    m_model->addItem(QStringLiteral("（手动输入）"), QString()); // 首项 tag ""
    if (pid.isEmpty())
        return;
    const ModelsDevCatalog cat = ModelsDevCatalog::loadCached();
    const CatalogProvider *p = cat.find(pid);
    if (!p)
        return;
    const QString f = m_filterWord.trimmed();
    // 无过滤词时 tool_call 优先 + 其余；有过滤词按子串
    QVector<const CatalogModel *> withTool;
    QVector<const CatalogModel *> others;
    for (const CatalogModel &m : p->models) {
        if (!f.isEmpty() && !m.id.contains(f, Qt::CaseInsensitive))
            continue;
        if (f.isEmpty() && m.toolCall.has_value() && *m.toolCall)
            withTool.append(&m);
        else
            others.append(&m);
    }
    for (const CatalogModel *m : withTool)
        m_model->addItem(m->id, m->id);
    for (const CatalogModel *m : others)
        m_model->addItem(m->id, m->id);
}

void AiSettingsPane::reflectProviderMeta()
{
    const QString pid = m_provider->currentData().toString();
    const bool isSystem = pid == QLatin1String("system");
    const bool isMock = pid == QLatin1String("mock");
    const ModelsDevCatalog cat = ModelsDevCatalog::loadCached();
    const CatalogProvider *p = cat.find(pid);
    const bool isAnthropic = pid == QLatin1String("anthropic");

    // 特殊通道：模型目录区/Key 区不适用（禁用但保留布局，避免切换时窗口跳动）
    m_modelFilter->setEnabled(!isSystem && !isMock);
    m_model->setEnabled(!isSystem && !isMock);
    m_modelManual->setEnabled(!isSystem);
    m_key->setEnabled(!isSystem);
    m_badges->setEnabled(true);

    // 端点展示：系统 AI 无端点；mock 基址=脚本载体；其余用户覆盖 > 目录 api > 默认
    if (isSystem) {
        m_endpoint->setText(QStringLiteral(
            "端点：系统级 AI（com.deepin.copilot）——无需端点。"
            "只支持唤起 UOS AI 对话窗口（inputPrompt 无返回值），不支持程序化补全；"
            "未选择其他渠道时它是默认后端。"));
        m_providerNote->setText(QStringLiteral(
            "检测以会话总线上的 com.deepin.copilot 为准；服务不可用时 AI 入口会明确报错"
            "（更新动作不受影响）。要启用生成能力请选择 OpenAI 兼容或 Anthropic 渠道。"));
    } else if (isMock) {
        m_endpoint->setText(QStringLiteral(
            "端点：%1（mock 基址只是脚本载体：#final / #tool=<名>;args=<json> / #fail；"
            "无片段时自动编排：先回一个无参工具调用，收到工具结果后回最终文本）")
            .arg(m_baseURLOverride->text().trimmed().isEmpty()
                    ? QStringLiteral("（空 = 自动编排）")
                    : m_baseURLOverride->text().trimmed()));
        m_providerNote->setText(QStringLiteral(
            "本地全链路自测通道（对位 mac ai.providerID=mock）：配好后跑"
            " build/deepDolphin --agent-selftest [问题]，不联网验证工具循环；"
            "key 走明文 Settings（仅 mock 专用）。"));
    } else {
        QString effective = m_baseURLOverride->text().trimmed();
        if (effective.isEmpty())
            effective = p && p->api.has_value() ? *p->api
                : isAnthropic                   ? QStringLiteral("https://api.anthropic.com")
                                                : QString();
        m_endpoint->setText(effective.isEmpty()
                ? QStringLiteral("端点：（空 — 将在测试时报错）")
                : QStringLiteral("端点：%1").arg(effective));
        // 恒发披露（rebuildProviderOptions 已写，恢复默认文案防串台）
        m_providerNote->setText(
            QStringLiteral("只列模型最多的前 %1 家（共 %2 家有可用端点，目录共 %3 家）；"
                           "其余的可用下方「Base URL 覆盖」手填端点")
                .arg(PROVIDER_PICKER_MAX)
                .arg(cat.withEndpointCount())
                .arg(cat.totalProviders()));
    }
    // ollama / 系统 / mock placeholder
    m_key->setPlaceholderText(isSystem
            ? QStringLiteral("系统级 AI 无需 Key")
            : isMock
            ? QStringLiteral("自测通道：key 存明文（仅 mock 专用）")
            : pid == QLatin1String("ollama")
            ? QStringLiteral("本地服务通常无需 Key")
            : QStringLiteral("API Key（只存入系统密钥环，不落明文）"));

    // 徽标行：tool_call ✓ 绿 / reasoning 紫 / ctx Nk / $x.xx/M in
    const QString mid = m_model->currentData().toString();
    if (isSystem) {
        m_badges->setText(QStringLiteral("唤起对话窗口 ✓ · 程序化补全 ✗"));
        return;
    }
    if (isMock) {
        m_badges->setText(QStringLiteral("本地自测 · 无网络 · 脚本化响应"));
        return;
    }
    if (p && !mid.isEmpty()) {
        for (const CatalogModel &m : p->models) {
            if (m.id != mid)
                continue;
            QStringList badges;
            if (m.toolCall.has_value())
                badges << QStringLiteral("tool_call %1").arg(*m.toolCall ? "✓" : "—");
            if (m.reasoning.has_value() && *m.reasoning)
                badges << QStringLiteral("reasoning 🧠");
            if (m.context.has_value())
                badges << QStringLiteral("ctx %1k").arg(*m.context / 1000);
            if (m.costIn.has_value())
                badges << QStringLiteral("$%1/M in").arg(*m.costIn, 0, 'f', 2);
            m_badges->setText(badges.join(QStringLiteral(" · ")));
            return;
        }
    }
    m_badges->setText(m_modelManual->text().isEmpty() ? QString()
                                                      : QStringLiteral("手动输入的模型 id"));
}

void AiSettingsPane::setDraft(const AIConfig &draft)
{
    rebuildProviderOptions(draft.providerID);
    const int pidx = m_provider->findData(draft.providerID);
    QSignalBlocker pb(m_provider);
    m_provider->setCurrentIndex(qMax(0, pidx));
    rebuildModelOptions();
    QSignalBlocker mb(m_model);
    if (draft.model.isEmpty()) {
        m_model->setCurrentIndex(0);
    } else {
        const int midx = m_model->findData(draft.model);
        if (midx >= 0)
            m_model->setCurrentIndex(midx);
        else
            m_modelManual->setText(draft.model);
    }
    m_key->setText(draft.apiKey);
    m_baseURLOverride->setText(draft.baseURL);
    reflectProviderMeta();
}

AIConfig AiSettingsPane::draft() const
{
    AIConfig d;
    d.providerID = m_provider->currentData().toString();
    // 模型：手动输入优先；否则下拉选中
    d.model = !m_modelManual->text().trimmed().isEmpty() ? m_modelManual->text().trimmed()
                                                         : m_model->currentData().toString();
    d.baseURL = m_baseURLOverride->text().trimmed();
    d.apiKey = m_key->text();
    return d;
}

void AiSettingsPane::setTestResult(bool ok, const QString &message)
{
    m_testResult->setText((ok ? QStringLiteral("✓ ") : QStringLiteral("✗ ")) + message);
    m_testResult->setStyleSheet(QStringLiteral("color: %1;")
            .arg(ok ? DS::semColor(DS::SemColor::shallow).name()
                    : DS::semColor(DS::SemColor::red).name()));
}

void AiSettingsPane::setTestBusy(bool busy)
{
    m_test->setEnabled(!busy);
    m_test->setText(busy ? QStringLiteral("测试中…") : QStringLiteral("测试连接"));
}
