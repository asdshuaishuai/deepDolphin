#include "AgentDialog.h"
#include "../../ai/AIConfig.h"
#include "../../ai/AIEngineFactory.h"
#include "../../ai/AgentConversation.h"
#include "../../ai/SecretStore.h"
#include "../../ai/SystemAiEngine.h"
#include "../DesignTokens.h"
#include "../common/MarkdownView.h"
#include <DSpinner>
#include <QEvent>
#include <QFrame>
#include <QHBoxLayout>
#include <QKeyEvent>
#include <QLabel>
#include <QPlainTextEdit>
#include <QPointer>
#include <QPropertyAnimation>
#include <QPushButton>
#include <QScrollBar>
#include <QScrollArea>
#include <QShortcut>
#include <QThreadPool>
#include <QTimer>
#include <QVBoxLayout>
#include <memory>

namespace {
// 空态示例（mac AgentView groupSamples/projectSamples 逐字）
QStringList groupSamples()
{
    return { QStringLiteral("哪些项目有未提交改动？"), QStringLiteral("最近一周哪些项目停滞了？"),
        QStringLiteral("按里程碑汇总一下当前进度。") };
}
QStringList projectSamples()
{
    return { QStringLiteral("这个项目现在什么状态？"), QStringLiteral("有哪些未完成的里程碑？"),
        QStringLiteral("跑一次浅更新并总结变化。") };
}
} // namespace

AgentDialog::AgentDialog(QWidget *parent, const QString &engineBin, const AgentCore::Target &target)
    : DDialog(parent)
    , m_engineBin(engineBin)
    , m_target(target)
    , m_cancelFlag(QSharedPointer<QAtomicInt>::create())
{
    setWindowTitle(QStringLiteral("AI 助手 · %1").arg(m_target.label()));
    resize(720, 620);
    setFixedSize(720, 620); // mac sheet 720×620 固定
    setOnButtonClickedClose(false);

    // AI 配置初判（判定空态/发送按钮）：GUI 线程只读 Settings 身份（不含 key——
    // 同步 libsecret 不进 GUI 线程，PLAN §2.5）；key 与最终「已配置」在 worker 取回后回填
    AIConfig cfg = AIConfig::load();
    m_configured = AIEngineFactory::create(cfg)->isConfigured(&m_notConfiguredWhy);

    buildUi();
    rebuildTranscript();
    refreshSendButton();
    probeConfiguredAsync();
}

AgentDialog::~AgentDialog()
{
    if (m_cancelFlag)
        m_cancelFlag->storeRelaxed(1); // 关窗后不再回写状态；在跑的 worker 持自己的旗标副本，安全退出
}

void AgentDialog::probeConfiguredAsync()
{
    // key 读取（secret_password_lookup_sync 阻塞）不进 GUI 线程（PLAN §2.5）；
    // 结论经 invokeMethod 回 GUI，回填 m_configured 与空态指引
    QPointer<AgentDialog> guard(this);
    QThreadPool::globalInstance()->start([this, guard] {
        AIConfig cfg = AIConfig::load();
        {
            SecretStore store;
            cfg.apiKey = AIConfig::loadKey(&store);
        }
        QString why;
        const std::unique_ptr<AIEngine> engine = AIEngineFactory::create(cfg);
        const bool configured = engine->isConfigured(&why);
        if (!guard)
            return;
        QMetaObject::invokeMethod(
            guard,
            [this, guard, configured, why] {
                if (!guard)
                    return;
                m_configured = configured;
                m_notConfiguredWhy = why;
                rebuildTranscript();
                refreshSendButton();
            },
            Qt::QueuedConnection);
    });
}

void AgentDialog::retarget(const AgentCore::Target &t)
{
    if (m_busy)
        return; // 对话开着不换范围（历史属于打开时的范围，且任务在飞）
    if (t.kind == m_target.kind && t.projectName == m_target.projectName)
        return;
    m_target = t;
    setWindowTitle(QStringLiteral("AI 助手 · %1").arg(m_target.label()));
    // 历史与上下文包属于旧范围——带着群历史的「项目 X」追问必然答非所问
    m_history.clear();
    m_errorBanner->hide();
    m_eventLabel->clear();
    m_eventRow->hide();
    rebuildTranscript();
    refreshSendButton();
}

void AgentDialog::buildUi()
{
    auto *content = new QWidget(this);
    auto *v = new QVBoxLayout(content);
    v->setContentsMargins(DS::Spacing::lg, DS::Spacing::md, DS::Spacing::lg, DS::Spacing::md);
    v->setSpacing(DS::Spacing::sm);

    // ── 消息区（滚动） ──
    m_transcriptHost = new QWidget(content);
    m_transcriptLayout = new QVBoxLayout(m_transcriptHost);
    m_transcriptLayout->setContentsMargins(0, 0, 0, 0);
    m_transcriptLayout->setSpacing(DS::Spacing::md);
    m_transcriptLayout->addStretch(1);
    m_scroll = new QScrollArea(content);
    m_scroll->setWidgetResizable(true);
    m_scroll->setFrameShape(QFrame::NoFrame);
    m_scroll->setWidget(m_transcriptHost);
    m_scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    v->addWidget(m_scroll, 1);

    // 过程事件行（busy 时可见）
    m_eventRow = new QWidget(content);
    auto *evLay = new QHBoxLayout(m_eventRow);
    evLay->setContentsMargins(0, 0, 0, 0);
    m_eventLabel = new QLabel(m_eventRow);
    m_eventLabel->setFont(DS::font(DS::FontT::badge));
    m_eventLabel->setStyleSheet(
        QStringLiteral("color: %1; font-family: monospace;").arg(DS::textSecondary().name()));
    m_eventLabel->setWordWrap(true);
    evLay->addWidget(m_eventLabel, 1);
    m_eventRow->hide();
    v->addWidget(m_eventRow);

    // busy 行
    auto *busyRow = new QWidget(content);
    auto *busyLay = new QHBoxLayout(busyRow);
    busyLay->setContentsMargins(0, 0, 0, 0);
    busyLay->setSpacing(DS::Spacing::xs);
    m_spinner = new DSpinner(busyRow);
    m_busyLabel = new QLabel(QStringLiteral("AI 正在思考…"), busyRow);
    m_busyLabel->setFont(DS::font(DS::FontT::label));
    DS::tagSecondaryStyle(m_busyLabel);
    busyLay->addWidget(m_spinner);
    busyLay->addWidget(m_busyLabel);
    busyLay->addStretch(1);
    busyRow->hide();
    v->addWidget(busyRow);
    m_busyLabel->setProperty("row", QVariant::fromValue<QWidget *>(busyRow)); // setBusy 复位用
    m_spinner->setProperty("row", QVariant::fromValue<QWidget *>(busyRow));

    // 错误横幅（含「重发上一条」——失败后重发同一条，不惩罚用户重新打字）
    m_errorBanner = new QWidget(content);
    auto *errLay = new QHBoxLayout(m_errorBanner);
    errLay->setContentsMargins(0, 0, 0, 0);
    errLay->setSpacing(DS::Spacing::sm);
    m_errorLabel = new QLabel(m_errorBanner);
    m_errorLabel->setFont(DS::font(DS::FontT::label));
    m_errorLabel->setStyleSheet(
        QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::red).name()));
    m_errorLabel->setWordWrap(true);
    m_resendBtn = new QPushButton(QStringLiteral("重发上一条"), m_errorBanner);
    m_resendBtn->setFlat(true);
    connect(m_resendBtn, &QPushButton::clicked, this, &AgentDialog::resendLast);
    errLay->addWidget(m_errorLabel, 1);
    errLay->addWidget(m_resendBtn, 0, Qt::AlignTop);
    m_errorBanner->hide();
    v->addWidget(m_errorBanner);

    // ── 输入区 ──
    auto *inputRow = new QWidget(content);
    auto *inLay = new QHBoxLayout(inputRow);
    inLay->setContentsMargins(0, 0, 0, 0);
    inLay->setSpacing(DS::Spacing::sm);
    m_input = new QPlainTextEdit(inputRow);
    m_input->setPlaceholderText(QStringLiteral("问点什么…（Ctrl+Return 发送）"));
    m_input->setFixedHeight(72);
    m_input->setTabChangesFocus(true);
    inLay->addWidget(m_input, 1);
    auto *btnCol = new QVBoxLayout;
    btnCol->setSpacing(DS::Spacing::xs);
    m_sendBtn = new QPushButton(QStringLiteral("发送"), inputRow);
    m_stopBtn = new QPushButton(QStringLiteral("停止"), inputRow);
    m_stopBtn->setToolTip(QStringLiteral("终止当前回答；运行中的引擎调用会被终止"));
    m_stopBtn->hide();
    btnCol->addWidget(m_sendBtn);
    btnCol->addWidget(m_stopBtn);
    inLay->addLayout(btnCol);
    v->addWidget(inputRow);

    // 底部：清空 + 「用 UOS AI 打开这个问题」（系统级 AI 的唯一有意义用法）
    auto *footRow = new QWidget(content);
    auto *footLay = new QHBoxLayout(footRow);
    footLay->setContentsMargins(0, 0, 0, 0);
    footLay->setSpacing(DS::Spacing::sm);
    m_clearBtn = new QPushButton(QStringLiteral("清空对话"), footRow);
    m_clearBtn->setFlat(true);
    m_uosBtn = new QPushButton(QStringLiteral("用 UOS AI 打开这个问题"), footRow);
    m_uosBtn->setFlat(true);
    m_uosBtn->setToolTip(QStringLiteral(
        "把问题交给 UOS AI 对话窗口继续（系统级 AI 不支持程序化补全，只能唤起窗口）"));
    footLay->addWidget(m_clearBtn);
    footLay->addStretch(1);
    footLay->addWidget(m_uosBtn);
    v->addWidget(footRow);

    addContent(content);

    // ── 行为 ──
    connect(m_sendBtn, &QPushButton::clicked, this, &AgentDialog::send);
    connect(m_stopBtn, &QPushButton::clicked, this, &AgentDialog::stop);
    connect(m_clearBtn, &QPushButton::clicked, this, &AgentDialog::clearChat);
    connect(m_input, &QPlainTextEdit::textChanged, this, &AgentDialog::refreshSendButton);
    // Ctrl+Return / Ctrl+Enter 发送（mac ⌘↩ 对位）
    auto *ret = new QShortcut(QKeySequence(QStringLiteral("Ctrl+Return")), this);
    connect(ret, &QShortcut::activated, this, &AgentDialog::send);
    auto *enter = new QShortcut(QKeySequence(QStringLiteral("Ctrl+Enter")), this);
    connect(enter, &QShortcut::activated, this, &AgentDialog::send);
    connect(m_uosBtn, &QPushButton::clicked, this, [this] {
        QString q = m_input->toPlainText().trimmed();
        if (q.isEmpty()) {
            for (int i = m_history.size() - 1; i >= 0; --i) {
                if (m_history.at(i).role == ChatMessage::Role::user) {
                    q = m_history.at(i).text;
                    break;
                }
            }
        }
        if (q.isEmpty())
            q = QStringLiteral("总结一下项目群现状");
        SystemAiEngine sys;
        const bool launched = sys.launchChat(q);
        if (launched) {
            m_errorBanner->hide();
        } else {
            m_errorLabel->setText(QStringLiteral(
                "未能唤起 UOS AI 对话窗口（服务不在会话总线上或调用失败）。"));
            m_errorBanner->show();
        }
    });
}

void AgentDialog::closeEvent(QCloseEvent *event)
{
    // 有历史时先停、再关：否则关窗后 agent 还在后台跑，跑完往已销毁的界面上写状态
    if (m_busy)
        stop();
    DDialog::closeEvent(event);
}

void AgentDialog::rebuildTranscript()
{
    for (const QPointer<QWidget> &w : m_bubbles) {
        if (w)
            w->deleteLater();
    }
    m_bubbles.clear();

    // 空态：示例（群/项目两套；未配置给橙色指引）
    const QList<AgentConversation::TranscriptEntry> entries
        = AgentConversation::transcript(m_history);
    const bool empty = entries.isEmpty();
    m_emptyHint = new QWidget(m_transcriptHost);
    auto *ev = new QVBoxLayout(m_emptyHint);
    ev->setContentsMargins(0, DS::Spacing::lg, 0, 0);
    ev->setSpacing(DS::Spacing::sm);
    auto *title = new QLabel(QStringLiteral("可以问："), m_emptyHint);
    title->setFont(DS::font(DS::FontT::cardTitle));
    ev->addWidget(title);
    const QStringList samples = m_target.isGroup() ? groupSamples() : projectSamples();
    for (const QString &s : samples) {
        auto *btn = new QPushButton(s, m_emptyHint);
        btn->setFlat(true);
        btn->setCursor(Qt::PointingHandCursor);
        btn->setStyleSheet(QStringLiteral(
            "QPushButton { color: %1; text-align: left; border: none; }")
            .arg(DS::semColor(DS::SemColor::accent).name()));
        btn->setEnabled(m_configured && !m_busy);
        connect(btn, &QPushButton::clicked, this, [this, s] {
            m_input->setPlainText(s);
            send();
        });
        ev->addWidget(btn);
    }
    if (!m_configured) {
        auto *hint = new QLabel(m_emptyHint);
        hint->setWordWrap(true);
        hint->setFont(DS::font(DS::FontT::label));
        hint->setStyleSheet(
            QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
        hint->setText(QStringLiteral("AI 尚未配置 —— %1").arg(m_notConfiguredWhy));
        ev->addWidget(hint);
    }
    m_transcriptLayout->insertWidget(m_transcriptLayout->count() - 1, m_emptyHint);
    m_bubbles.append(m_emptyHint);
    m_emptyHint->setVisible(empty);

    for (const AgentConversation::TranscriptEntry &e : entries) {
        QWidget *bubble = nullptr;
        if (e.kind == AgentConversation::TranscriptEntry::Kind::user) {
            auto *w = new QWidget(m_transcriptHost);
            auto *lay = new QHBoxLayout(w);
            lay->setContentsMargins(0, 0, 0, 0);
            auto *lab = new QLabel(e.text, w);
            lab->setWordWrap(true);
            lab->setTextInteractionFlags(Qt::TextSelectableByMouse);
            // 用户气泡 = accent 蓝 18% 透明底（对位 mac tinted accentColor.opacity(0.18)）
            const QColor accent = DS::semColor(DS::SemColor::accent);
            lab->setStyleSheet(QStringLiteral(
                "background: rgba(%1, %2, %3, 0.18); border-radius: 10px; padding: 10px;")
                .arg(accent.red())
                .arg(accent.green())
                .arg(accent.blue()));
            lay->addStretch(40);
            lay->addWidget(lab, 160);
            bubble = w;
        } else if (e.kind == AgentConversation::TranscriptEntry::Kind::assistant) {
            auto *view = new MarkdownView(m_transcriptHost);
            view->setMarkdownText(e.text);
            view->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Minimum);
            view->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
            bubble = view;
        } else { // note（⚠ 工具失败/被拒—— isError 标记驱动，不靠文案）
            auto *w = new QWidget(m_transcriptHost);
            auto *lay = new QHBoxLayout(w);
            lay->setContentsMargins(0, 0, 0, 0);
            auto *lab = new QLabel(e.text, w);
            lab->setWordWrap(true);
            lab->setFont(DS::font(DS::FontT::label));
            lab->setStyleSheet(
                QStringLiteral("color: %1;").arg(DS::semColor(DS::SemColor::orange).name()));
            lay->addWidget(lab, 1);
            bubble = w;
        }
        m_transcriptLayout->insertWidget(m_transcriptLayout->count() - 1, bubble);
        m_bubbles.append(bubble);
    }

    // 唯一动效：新消息自动滚动（0.20s easeInOut）
    if (m_scroll->verticalScrollBar()) {
        const int target = m_scroll->verticalScrollBar()->maximum();
        auto *anim = new QPropertyAnimation(m_scroll->verticalScrollBar(), "value", this);
        anim->setDuration(DS::MotionStandardMs);
        anim->setStartValue(m_scroll->verticalScrollBar()->value());
        anim->setEndValue(target);
        anim->setEasingCurve(QEasingCurve::InOutQuad);
        anim->start(QAbstractAnimation::DeleteWhenStopped);
    }
}

void AgentDialog::appendEvent(const QString &ev)
{
    const QString prev = m_eventLabel->text();
    m_eventLabel->setText(prev.isEmpty() ? ev : prev + QStringLiteral("\n") + ev);
    m_eventRow->show();
}

void AgentDialog::setBusy(bool busy)
{
    m_busy = busy;
    if (QWidget *row = m_busyLabel->property("row").value<QWidget *>())
        row->setVisible(busy);
    if (busy)
        m_spinner->start();
    else
        m_spinner->stop();
    m_busyLabel->setText(m_cancelled ? QStringLiteral("正在停止…（运行中的引擎调用将被终止）")
                                     : QStringLiteral("AI 正在思考…"));
    m_eventRow->setVisible(busy && !m_eventLabel->text().isEmpty());
    if (busy) {
        m_errorBanner->hide();
        m_errorText.clear();
    }
    if (m_emptyHint) {
        for (QPushButton *b : m_emptyHint->findChildren<QPushButton *>())
            b->setEnabled(!busy && m_configured);
    }
    refreshSendButton();
    m_stopBtn->setVisible(
        AgentConversation::canStop(m_busy, m_cancelled));
}

void AgentDialog::refreshSendButton()
{
    const AgentConversation::SendDecision d
        = AgentConversation::canSend(m_input->toPlainText(), m_busy, m_configured);
    m_sendBtn->setEnabled(d.allowed);
    QString tip = QStringLiteral("发送");
    switch (d.block) {
    case AgentConversation::SendBlock::empty:
        tip = QStringLiteral("先输入内容");
        break;
    case AgentConversation::SendBlock::notConfigured:
        tip = QStringLiteral("AI 未配置 —— 先到 AI 设置填写");
        break;
    case AgentConversation::SendBlock::busy:
        tip = QStringLiteral("正在回答上一条");
        break;
    case AgentConversation::SendBlock::none:
        break;
    }
    m_sendBtn->setToolTip(tip);
    m_clearBtn->setEnabled(!m_history.isEmpty() && !m_busy);
    m_stopBtn->setVisible(AgentConversation::canStop(m_busy, m_cancelled));
}

void AgentDialog::send()
{
    const AgentConversation::SendDecision d
        = AgentConversation::canSend(m_input->toPlainText(), m_busy, m_configured);
    if (!d.allowed) {
        if (d.block == AgentConversation::SendBlock::notConfigured && m_errorLabel) {
            m_errorLabel->setText(QStringLiteral("AI 未配置：%1").arg(m_notConfiguredWhy));
            m_errorBanner->show();
        }
        return;
    }
    m_input->clear();
    m_errorText.clear();
    m_cancelled = false;
    m_cancelFlag = QSharedPointer<QAtomicInt>::create(); // 每次发送一枚新旗标（旧 worker 持旧副本不受影响）
    m_eventLabel->clear();
    m_eventRow->hide();
    const QList<ChatMessage> before = m_history;
    const QString question = d.text;
    setBusy(true);
    rebuildTranscript();

    QPointer<AgentDialog> guard(this);
    // shared 副本进 worker：对话框析构置位的是当前旗标，worker 持旧副本不受 UAF 影响
    QSharedPointer<QAtomicInt> cancelFlag = m_cancelFlag;
    const QString engineBin = m_engineBin;
    const AgentCore::Target target = m_target;
    QThreadPool::globalInstance()->start([this, guard, question, before, cancelFlag, engineBin,
                                             target] {
        // key 在 worker 里取（libsecret 同步 API 阻塞——不占 GUI 线程）
        AIConfig cfg = AIConfig::load();
        {
            SecretStore store;
            cfg.apiKey = AIConfig::loadKey(&store);
        }
        AgentCore core(engineBin);
        QString err;
        const QList<ChatMessage> convo
            = core.run(question, before, target, cfg, 4,
                [guard](const QString &ev) {
                    if (!guard)
                        return;
                    QMetaObject::invokeMethod(guard, [guard, ev] { if (guard) guard->appendEvent(ev); },
                        Qt::QueuedConnection);
                },
                &err, cancelFlag.data());
        if (!guard)
            return;
        QMetaObject::invokeMethod(
            guard,
            [this, guard, convo, err, question, before] {
                if (!guard)
                    return;
                setBusy(false);
                m_eventRow->hide();
                if (!err.isEmpty()) {
                    // 失败回滚：已发提问留回 history（用户的问题不消失）
                    m_history = before;
                    m_history.append(ChatMessage::makeUser(question));
                    m_errorLabel->setText(err);
                    m_errorBanner->show();
                } else {
                    m_history = convo;
                    m_errorBanner->hide();
                }
                rebuildTranscript();
                refreshSendButton();
            },
            Qt::QueuedConnection);
    });
}

void AgentDialog::stop()
{
    if (!AgentConversation::canStop(m_busy, m_cancelled))
        return;
    m_cancelled = true;
    m_cancelFlag->storeRelaxed(1); // 运行中的引擎调用在 ≤200ms 内被 terminate（M0-5 切片响应）
    m_busyLabel->setText(QStringLiteral("正在停止…（运行中的引擎调用将被终止）"));
    refreshSendButton();
}

void AgentDialog::resendLast()
{
    for (int i = m_history.size() - 1; i >= 0; --i) {
        if (m_history.at(i).role == ChatMessage::Role::user) {
            m_input->setPlainText(m_history.at(i).text);
            send();
            return;
        }
    }
}

void AgentDialog::clearChat()
{
    if (m_busy)
        stop();
    m_history.clear();
    m_errorText.clear();
    m_errorBanner->hide();
    m_eventLabel->clear();
    m_eventRow->hide();
    m_cancelled = false;
    rebuildTranscript();
    refreshSendButton();
}
